# Security Groups

## KNFSD proxy instances to source servers

By default, an AWS Security Group's egress rule allows all outbound traffic. However, you are most likely using a non-default Security Group which restricts egress traffic.

Many of the ports used by NFS v3 are dynamic, so you will need to check with the source NFS server to see which ports are required.

## Clients to KNFSD proxy instances

To allow traffic from NFS clients to KNFSD proxy instances we need to add ingress rules in AWS.

### Using the AWS Console

Create a [Security Group](https://docs.aws.amazon.com/vpc/latest/userguide/creating-security-groups.html) with the following information:

1. Open the Amazon VPC console at https://console.aws.amazon.com/vpc.

2. In the navigation pane, choose **Security groups**.

3. Choose **Create security group**.

4. Enter a name and description for the security group. You can't change the name and description of a security group after it is created.

5. For **VPC**, choose the VPC in which you'll create the compute resources to which you'll associate the security group.

6. Add **inbound rules**, choose **Add rule** and specify:

   * Protocol: `TCP`, `UDP`
   * Port: `111, 2049, 20048, 20050, 20051, 20053, 20055`
   * Source: `<VPC_CIDR_BLOCK or PROXY_SECURITY_GROUP_ID>` where `<PROXY_SECURITY_GROUP_ID>` is the ID of the KNFSD proxy security group, provided by the `output.nfsproxy_security_group_id` in the Terraform output.

7. Add **outbound rule**, choose **Add rule** and specify:

   * Protocol: `-1`
   * Destination: `<VPC_CIDR_BLOCK or PROXY_SECURITY_GROUP_ID>` where `<PROXY_SECURITY_GROUP_ID>` is the ID of the KNFSD proxy security group, provided by the `output.nfsproxy_security_group_id` in the Terraform output.

8. (Optional) To add a tag, choose **Add new tag** and enter the tag key and value.

9. Choose **Create security group**.

### Using Terraform

```terraform
# Security group for NFS client instances

locals {
  nfs_ports = [111, 2049, 20048, 20050, 20051, 20053, 20055]
  vpc_id    = "vpc-fad86193"
  ## use either vpc_cidr or proxy_sg_id
  vpc_cidr = "172.31.0.0/16"
  ## provided by the `output.nfsproxy_security_group_id` in the Terraform root module output
  # proxy_sg_id = "sg-1e680277"
}

# NFS client security group
resource "aws_security_group" "allow_nfs" {
  name        = "allow-nfs"
  description = "knfsd security group for NFS client instances"
  vpc_id      = local.vpc_id

  tags = {
    Name = "allow-nfs-sg"
  }
}

# TCP ingress rules for NFS ports
resource "aws_vpc_security_group_ingress_rule" "allow_tcp" {
  for_each = toset([for port in local.nfs_ports : tostring(port)])

  security_group_id = aws_security_group.allow_nfs.id
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"
  ## choose either cidr_ipv4 or referenced_security_group_id
  cidr_ipv4 = local.vpc_cidr
  # referenced_security_group_id = local.proxy_sg_id
  description = "Allow TCP port: ${each.value}"
}

# UDP ingress rules for NFS ports
resource "aws_vpc_security_group_ingress_rule" "allow_udp" {
  for_each = toset([for port in local.nfs_ports : tostring(port)])

  security_group_id = aws_security_group.allow_nfs.id
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "udp"
  ## choose either cidr_ipv4 or referenced_security_group_id
  cidr_ipv4 = local.vpc_cidr
  # referenced_security_group_id = local.proxy_sg_id
  description = "Allow UDP port: ${each.value}"
}

# Egress rule
resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.allow_nfs.id
  ip_protocol       = "-1"
  ## choose either cidr_ipv4 or referenced_security_group_id
  cidr_ipv4 = local.vpc_cidr
  # referenced_security_group_id = local.proxy_sg_id
  description = "Allow all outbound traffic to VPC"
}
```
