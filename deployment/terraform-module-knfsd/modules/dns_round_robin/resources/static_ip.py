#!/usr/bin/env python

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

"""
This py script provides functionality for managing the secondary ENI (Elastic Network Interface)
to an EC2 instance during EC2 launch & termination events in an Auto Scaling Group. A DNS
"A" record is created/deleted to reflect the IPv4 address of the secondary ENI.

This py script ensures that the secondary private IP address is maintained (static)
across instance replacements in an Auto Scaling Group.
"""

import os
import json
import logging
import time
import boto3

# configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# initialize AWS clients
ec2 = boto3.client("ec2")
route53 = boto3.client("route53")
autoscaling = boto3.client("autoscaling")


"""
fn instance_launching():
    query if any ENIs are:
        "tag:knfsd-file-cache:asg-name==asg_name"
        "tag:knfsd-file-cache:instance-id==null"
        "status==available"
    if YES:
        "AttachNetworkInterface" eni[0] to launching EC2 instance
        & update "tag:knfsd-file-cache:instance-id={new instance-id}"
    if NO:
        CreateNetworkInterface, then follow the YES steps as above
    upsert DNS "A" record set
    set ENI to DeleteOnTermination=False
fn instance_terminated():
    find cause of termination of instance-id? ()"Cause" field in event)
    find DescribeNetWorkInterfaces where: (while-do loop)
        "tag:knfsd-file-cache:asg-name==asg_name"
        "tag:knfsd-file-cache:instance-id=={terminated instance-id}"
    if cause==SCALE_IN:
        DeleteNetworkInterface eni-id
    else:
        Modify TAG to: "tag:knfsd-file-cache:instance-id=null"
    delete DNS "A" record set
"""


# pylint: disable=unused-argument
def lambda_handler(event, context):
    """
    Main Lambda function handler that processes EC2 ASG
    launch-lifecycle & instance terminated events.
    """
    logger.info("Event: %s", json.dumps(event))

    status_code = 200
    message = "Event processed successfully"

    # event details
    detail_type = event.get("detail-type")
    termination_cause = event["detail"].get("Cause")
    autoscaling_group_name = event["detail"].get("AutoScalingGroupName")
    instance_id = event["detail"].get("EC2InstanceId")
    lifecycle_hook_name = event["detail"].get("LifecycleHookName")
    lifecycle_action_token = event["detail"].get("LifecycleActionToken")

    try:
        # handle instance LAUNCHING lifecycle ACTION
        if detail_type == "EC2 Instance-launch Lifecycle Action":
            logger.info("EVENT: instance-LAUNCHING lifecycle ACTION: %s", instance_id)
            instance_launching(
                instance_id,
                autoscaling_group_name,
                lifecycle_hook_name,
                lifecycle_action_token,
            )
            logger.info(
                "EVENT: instance-LAUNCHING lifecycle ACTION: COMPLETED SUCCESSFULLY"
            )

        # handle instance TERMINATED EVENT
        if detail_type == "EC2 Instance Terminate Successful":
            logger.info("EVENT: instance TERMINATED EVENT: %s", instance_id)
            instance_terminated(
                instance_id,
                autoscaling_group_name,
                termination_cause,
            )
            logger.info("EVENT: instance TERMINATED EVENT: COMPLETED SUCCESSFULLY")

    # pylint: disable=broad-exception-caught
    except Exception as e:
        logger.error("Error: %s", str(e))
        status_code = 500
        message = f"Error: {str(e)}"

        # abandon the launch lifecycle as failed
        if detail_type in ("EC2 Instance-launch Lifecycle Action"):
            try:
                complete_lifecycle_action(
                    autoscaling_group_name,
                    lifecycle_hook_name,
                    lifecycle_action_token,
                    "ABANDON",
                )
            # pylint: disable=broad-exception-caught
            except Exception as lifecycle_error:
                logger.error(
                    "Error completing lifecycle action: %s", str(lifecycle_error)
                )

    return {
        "statusCode": status_code,
        "body": json.dumps(message),
    }


# pylint: disable=too-many-locals
def instance_launching(instance_id, asg_name, hook_name, token):
    """
    Handle the EC2 instance launch lifecycle action.
    """
    proxy_basename = os.environ.get("PROXY_BASENAME")
    subnet_id = os.environ.get("SUBNET")

    # find available ENI tagged with this ASG name & status==available
    paginator = ec2.get_paginator("describe_network_interfaces")
    available_enis = []

    for page in paginator.paginate(
        Filters=[
            {"Name": "subnet-id", "Values": [subnet_id]},
            {"Name": "tag:knfsd-file-cache:asg-name", "Values": [asg_name]},
            {"Name": "tag:knfsd-file-cache:instance-id", "Values": [""]},
            {"Name": "status", "Values": ["available"]},
        ]
    ):
        available_enis.extend(page["NetworkInterfaces"])

    logger.info("Available ENIs: %s", available_enis)

    # get the security groups assigned to the instance's primary network interface
    instance = ec2.describe_instances(InstanceIds=[instance_id])
    primary_eni = instance["Reservations"][0]["Instances"][0]["NetworkInterfaces"][0]
    security_group_ids = [sg["GroupId"] for sg in primary_eni["Groups"]]
    logger.info("Security groups from primary ENI: %s", security_group_ids)

    # if no available ENIs, create a new ENI
    if not available_enis:
        logger.info("No available ENIs found, creating new ENI")
        eni_response = ec2.create_network_interface(
            SubnetId=subnet_id,
            Description="Static secondary private IPv4 address for nfsproxy instance",
            Groups=security_group_ids,
            TagSpecifications=[
                {
                    "ResourceType": "network-interface",
                    "Tags": [
                        {"Key": "Name", "Value": f"{proxy_basename}-static-ip"},
                        {"Key": "knfsd-file-cache:asg-name", "Value": asg_name},
                    ],
                }
            ],
        )
        logger.info("ENI created successfully")
        eni = eni_response["NetworkInterface"]
    else:
        eni = available_enis[0]
        logger.info("Found available ENI: %s", eni["NetworkInterfaceId"])

    # get the private IP address of the ENI
    private_ip = eni["PrivateIpAddress"]

    # create the DNS "A" record
    change_dns_record(private_ip, "UPSERT")
    logger.info("DNS 'A' record created successfully: %s", private_ip)

    logger.info(
        "Attaching ENI: %s to instance: %s",
        eni["NetworkInterfaceId"],
        instance_id,
    )

    # attach the ENI to the new instance
    attachment = ec2.attach_network_interface(
        NetworkInterfaceId=eni["NetworkInterfaceId"],
        InstanceId=instance_id,
        DeviceIndex=1,
    )
    attachment_id = attachment["AttachmentId"]

    logger.info(
        "Successfully attached ENI: %s to instance: %s",
        eni["NetworkInterfaceId"],
        instance_id,
    )

    # modify the attachment to prevent ENI from being deleted on termination
    ec2.modify_network_interface_attribute(
        Attachment={
            "AttachmentId": attachment_id,
            "DeleteOnTermination": False,
        },
        NetworkInterfaceId=eni["NetworkInterfaceId"],
    )

    logger.info(
        "Successfully modified attachment: %s to prevent ENI: %s from being deleted on termination",
        attachment_id,
        eni["NetworkInterfaceId"],
    )

    # update the ENI tags
    ec2.create_tags(
        Resources=[eni["NetworkInterfaceId"]],
        Tags=[{"Key": "knfsd-file-cache:instance-id", "Value": instance_id}],
    )

    logger.info(
        "Successfully updated tag to ENI: %s",
        eni["NetworkInterfaceId"],
    )

    # complete the lifecycle action
    complete_lifecycle_action(asg_name, hook_name, token, "CONTINUE")


def instance_terminated(instance_id, asg_name, cause):
    """
    Handle successful EC2 instance termination event.
    """
    reason = determine_reason(cause)
    logger.info(
        "Instance terminated: %s (ASG: %s) with reason: %s",
        instance_id,
        asg_name,
        reason,
    )

    subnet_id = os.environ.get("SUBNET")

    # find ENI that was attached to the terminated instance
    eni_response = get_eni(subnet_id, asg_name, instance_id)

    eni = eni_response[0]
    eni_id = eni["NetworkInterfaceId"]
    private_ip = eni["PrivateIpAddress"]

    if reason == "SCALE_IN":
        logger.info("Deleting ENI: %s", eni_id)
        ec2.delete_network_interface(NetworkInterfaceId=eni_id)
        logger.info("ENI deleted successfully")
    else:
        # in a termination event other than SCALE_IN or ASG deleted,
        # re-tag the ENI to remove the instance-id tag and return
        # it to the ENI pool
        logger.info("Re-tagging ENI: %s", eni_id)
        ec2.create_tags(
            Resources=[eni_id],
            Tags=[{"Key": "knfsd-file-cache:instance-id", "Value": ""}],
        )
        logger.info("ENI re-tagged successfully")

    # delete the DNS "A" record
    change_dns_record(private_ip, "DELETE")
    logger.info("DNS 'A' record deleted successfully: %s", private_ip)


def get_eni(subnet_id, asg_name, instance_id, max_attempts=10, delay_sec=30):
    """
    Attempt to get ENI with retries.

    Args:
        subnet_id: The subnet ID to search in
        asg_name: The Auto Scaling Group name
        instance_id: The EC2 instance ID
        max_attempts: Maximum number of retry attempts
        delay_sec: Delay between retries in seconds

    Returns:
        List of ENI responses

    Raises:
        Exception: If no ENIs found after max retries
    """
    attempt = 1
    while attempt <= max_attempts:
        logger.info(
            "Attempting to find ENI (attempt %d of %d) for instance: %s",
            attempt,
            max_attempts,
            instance_id,
        )

        paginator = ec2.get_paginator("describe_network_interfaces")
        eni_response = []

        for page in paginator.paginate(
            Filters=[
                {"Name": "subnet-id", "Values": [subnet_id]},
                {"Name": "tag:knfsd-file-cache:asg-name", "Values": [asg_name]},
                {"Name": "tag:knfsd-file-cache:instance-id", "Values": [instance_id]},
                {"Name": "status", "Values": ["available"]},
            ]
        ):
            eni_response.extend(page["NetworkInterfaces"])

        if eni_response:
            logger.info("Found ENI after %d attempt(s)", attempt)
            return eni_response

        if attempt < max_attempts:
            logger.info(
                "No ENIs found on attempt %d, waiting %d seconds before retry...",
                attempt,
                delay_sec,
            )
            time.sleep(delay_sec)

        attempt += 1

    # pylint: disable=broad-exception-raised
    raise Exception(
        f"Failed to find ENI for instance {instance_id} after {max_attempts} attempts"
    )


def change_dns_record(private_ip, action):
    """
    Upsert/Delete a DNS "A" record for the given private IP address.

    Args:
        private_ip: The private IP address to upsert/delete the DNS "A" record
        action: The action to perform (UPSERT or DELETE)
    """
    zone_id = os.environ.get("R53_ZONE_ID")
    zone_name = os.environ.get("R53_ZONE_NAME")

    route53.change_resource_record_sets(
        HostedZoneId=zone_id,
        ChangeBatch={
            "Changes": [
                {
                    "Action": action,
                    "ResourceRecordSet": {
                        "Name": zone_name,
                        "Type": "A",
                        "TTL": 300,
                        "ResourceRecords": [{"Value": private_ip}],
                        "Weight": 1,
                        "SetIdentifier": f"static-ip-{private_ip}",
                    },
                }
            ]
        },
    )


def determine_reason(cause):
    """
    Determine the reason for the termination.
    """
    cause = cause.lower()

    # "At 2025-03-21T20:37:37Z a user request update of AutoScalingGroup constraints
    # to min: 1, max: 1, desired: 1 changing the desired capacity from 2 to 1.  At
    # 2025-03-21T20:37:47Z an instance was taken out of service in response to a
    # difference between desired and actual capacity, shrinking the capacity from 2 to
    # 1.  At 2025-03-21T20:37:47Z instance i-0336d608613353cd6 was selected
    # for termination."
    if any(term in cause for term in ["shrinking the capacity"]):
        return "SCALE_IN"

    return "UNKNOWN"


def complete_lifecycle_action(asg_name, hook_name, token, result):
    """
    Helper function to complete the lifecycle action.

    Args:
        asg_name: The name of the Auto Scaling Group
        hook_name: The name of the lifecycle hook
        token: The lifecycle action token
        result: The result of the lifecycle action (CONTINUE or ABANDON)
    """
    autoscaling.complete_lifecycle_action(
        AutoScalingGroupName=asg_name,
        LifecycleHookName=hook_name,
        LifecycleActionToken=token,
        LifecycleActionResult=result,
    )
