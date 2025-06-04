# Check the KNFSD proxy instance is starting correctly

To check if a KNFSD proxy instance is starting correctly, check the output from the System log either via AWS Console or AWS CLI.

```bash
aws ec2 get-console-output --instance-id INSTANCE_ID --latest --output text --no-cli-pager | grep "cloud-init"
```

You can also connect via EC2 Instance Connect/Endpoint, Session Manager, SSH or EC2 Serial Console (depending on your config)
and check the [status](https://cloudinit.readthedocs.io/en/latest/howto/status.html) via cloud-init: `cloud-init status` or `tail -f /var/log/cloud-init-output.log`.

> NOTE: For EC2 Serial Console access, you will need to set a password for `root` or equivalent user account within your AMI during Packer image build. For a strong security posture, this is not automated for you.

Once connected to a KNFSD proxy instance, you can execute this command to `--wait` until cloud-init has finished:

```bash
/usr/bin/cloud-init status
status: running

/usr/bin/cloud-init status --wait
# should return one of the following at exit:
status: done
status: error
```

If the status is `error` then check the output from `cat /var/log/cloud-init-output.log` for more details.

Once the `proxy-startup.sh` script has completed, look for either of these messages:

```bash
"INFO: Reached Proxy Startup Exit. Happy caching!"
or
"ERROR: Failed to start proxy"
```

## AWS Console

Using the AWS Console:

1. In the AWS Console go to EC2 and select the [Auto Scaling Groups](https://console.aws.amazon.com/ec2/v2/#AutoScalingGroups) page.

2. Select the KNFSD Auto Scaling Group.

3. Click the **Instance ID** of one of the KNFSD proxy instances from the **Instances** list on the **Instance management** tab.

4. Click on **Actions**, **Monitor and troubleshoot**, and **Get system log** or **EC2 serial console**.

5. Search for `"INFO: Reached Proxy Startup Exit. Happy caching!"` or `"ERROR: Failed to start proxy"`.

If the proxy instance is still starting, then you will need to refresh until the start up script finishes running.

## AWS Command Line Interface

Using the `AWS CLI`:

Retrieve the instance ID of a KNFSD proxy instance in the Auto Scaling Group.

```bash
aws ec2 describe-instances --filters "Name=tag:aws:autoscaling:groupName,Values=<var.PROXY_BASENAME>-asg" --query "Reservations[].Instances[].InstanceId[0]" --output text
# where <var.PROXY_BASENAME> is the Terraform variable for the unique basename of the KNFSD proxy cluster, default is `nfsproxy`, which if present, is combined
# with a random 8 alphanumeric string, and "-asg". Example: "nfsproxy-a1b2c3d4-asg"
```

If the instance is still starting up you can watch the `cloud-init` output by running:

```bash
aws ec2 get-console-output --instance-id INSTANCE_ID --latest --output text --no-cli-pager | grep "cloud-init"
```

## SSH

Connect via EC2 Instance Connect/Endpoint, Session Manager, or SSH. If applicable, add a security group to the KNFSD proxy instance to allow SSH access from your IP address.

Check the `cloud-init` status and tail the output log.

```bash
cloud-init status
tail -f /var/log/cloud-init-output.log
```

## Common Startup Issues

There are three main reasons:

1. Invalid configuration (startup failed)
2. Security Group/NACL/Firewall blocking access (startup failed, network connectivity issue)
3. Startup takes longer than 10 minutes (startup never finishes)

### Invalid configuration

If the start up shows the message "cloud-init: ERROR: Failed to start proxy" then look at the last message(s) from "cloud-init" to see what the error was.

The most likely errors are:

* Source NFS server could not be contacted:

  * Check the `EXPORT_MAP` or `EXPORT_HOST_AUTO_DETECT` has the correct IPs or DNS names and syntax is correct.

  * If using DNS, check that the DNS names can be resolved by the KNFSD proxy instances.

  * Ensure any applicable security groups, NACLs or firewalls allow the KNFSD proxy instances to access the source server.

  * Check on-prem firewall rules allow the NFS traffic from the KNFSD proxy instances.

  * Check the AWS Site-to-Site VPN and/or AWS Direct Connect connection is working.

  * Check if traffic from the KNFSD proxy's subnet can be routed to the VPN or DX.

* Access denied by server while mounting share. This is either a permission issue, or the share does not exist. Check source export paths specified in `EXPORT_MAP`.

### Start up takes longer than 10 minutes

Normally 10 minutes is long enough for the KNFSD proxy to start. However if you are re-exporting a large number of exports (e.g. 1000+) this start up time may exceed 10 minutes.

In this case the best option is to split up the exports across multiple separate KNFSD proxy clusters to reduce the number of exports per KNFSD proxy cluster.

If the startup time cannot be reduced below 10 minutes, then measure how long a KNFSD proxy instance takes to start and configure `HEALTHCHECK_INITIAL_DELAY_SECONDS` to increase the initial grace period when starting the cluster.
