/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package main

import (
	"net/http"

	"github.com/awslabs/knfsd-file-cache/image/resources/knfsd-agent/client"
)

var nodeInfo client.NodeInfo

// fetchNodeInfo populates the nodeData type from the AWS Instance MetaData Service (IMDSv2)
func fetchNodeInfo() error {
	var err error
	n := &nodeInfo

	// Populate name
	n.Name, err = getMetadataValue("tags/instance/Name", false)
	if err != nil {
		return err
	}

	// Populate instance ID
	n.InstanceID, err = getMetadataValue("instance-id", false)
	if err != nil {
		return err
	}

	// Populate hostname
	n.Hostname, err = getMetadataValue("local-hostname", false)
	if err != nil {
		return err
	}

	// Populate private IPv4 address
	n.InterfaceConfig.IPAddress, err = getMetadataValue("local-ipv4", false)
	if err != nil {
		return err
	}

	// Populate the MAC address of the primary NIC
	n.InterfaceConfig.MACAddress, err = getMetadataValue("mac", false)
	if err != nil {
		return err
	}

	// Populate the Private IPv4 Addresses
	n.InterfaceConfig.PrivateIPs, err = getMetadataValue("network/interfaces/macs/"+n.InterfaceConfig.MACAddress+"/local-ipv4s", true)
	if err != nil {
		return err
	}

	// Populate the VPC ID
	n.InterfaceConfig.VPCID, err = getMetadataValue("network/interfaces/macs/"+n.InterfaceConfig.MACAddress+"/vpc-id", false)
	if err != nil {
		return err
	}

	// Populate the Subnet ID
	n.InterfaceConfig.SubnetID, err = getMetadataValue("network/interfaces/macs/"+n.InterfaceConfig.MACAddress+"/subnet-id", false)
	if err != nil {
		return err
	}

	// Populate the Security Groups
	n.InterfaceConfig.SecurityGroups, err = getMetadataValue("network/interfaces/macs/"+n.InterfaceConfig.MACAddress+"/security-groups", true)
	if err != nil {
		return err
	}

	// Populate the Security Group IDs
	n.InterfaceConfig.SecurityGroupIDs, err = getMetadataValue("network/interfaces/macs/"+n.InterfaceConfig.MACAddress+"/security-group-ids", true)
	if err != nil {
		return err
	}

	// Populate the Domain
	n.Domain, err = getMetadataValue("services/domain", false)
	if err != nil {
		return err
	}

	// Populate the Partition
	n.Partition, err = getMetadataValue("services/partition", false)
	if err != nil {
		return err
	}

	// Populate the Region
	n.Region, err = getMetadataValue("placement/region", false)
	if err != nil {
		return err
	}

	// Populate the Availability Zone
	n.AvailabilityZone, err = getMetadataValue("placement/availability-zone", false)
	if err != nil {
		return err
	}

	// Populate the Availability Zone ID
	n.AvailabilityZoneID, err = getMetadataValue("placement/availability-zone-id", false)
	if err != nil {
		return err
	}

	// Populate the Instance Type
	n.InstanceType, err = getMetadataValue("instance-type", false)
	if err != nil {
		return err
	}

	// Populate the AMI ID
	n.AmiID, err = getMetadataValue("ami-id", false)
	if err != nil {
		return err
	}

	return nil
}

func handleNodeInfo(*http.Request) (*client.NodeInfo, error) {
	err := fetchNodeInfo()
	if err != nil {
		return nil, err
	}
	return &nodeInfo, nil
}
