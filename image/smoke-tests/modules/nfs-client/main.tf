# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
#
# NFS client: a single Ubuntu EC2 instance that runs the compiled smoke-test
# "remote.test" binary against the KNFSD proxy. Reached keylessly by the Go
# driver over SSM (AWS-StartSSHSession) with an ephemeral EC2 Instance Connect
# key, so no ingress and no stored SSH key pair are required.

terraform {
  required_version = ">= 1.2.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.63.0"
    }
  }
  provider_meta "aws" {
    user_agent = [
      "knfsd-file-cache/image/smoke-tests/modules/nfs-client/1.1.0-beta.3"
    ]
  }
}

locals {
  source_host_tag = "knfsd-file-cache:source-host"
  proxy_host_tag  = "knfsd-file-cache:proxy-host"
  user_data       = templatefile("${path.module}/scripts/startup.sh", {})
}

data "aws_subnet" "selected" {
  id = var.SUBNET
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/${var.ARCH}/hvm/ebs-gp3/ami-id"
}

# Validate client AMI architecture matches INSTANCE_TYPE family.
# tflint-ignore: terraform_unused_declarations
data "aws_ami" "client_arch" {
  filter {
    name   = "image-id"
    values = [data.aws_ssm_parameter.ubuntu_ami.value]
  }

  lifecycle {
    postcondition {
      condition = (
        can(regex("^[a-z]+[0-9]g[a-z]*\\.", var.INSTANCE_TYPE))
        ? self.architecture == "arm64"
        : self.architecture == "x86_64"
      )
      error_message = "Client AMI architecture (${self.architecture}) does not match INSTANCE_TYPE (${var.INSTANCE_TYPE}) architecture."
    }
  }
}

# Validate INSTANCE_TYPE is offered in the selected subnet's availability zone.
# tflint-ignore: terraform_unused_declarations
data "aws_ec2_instance_type_offerings" "client_offered" {
  filter {
    name   = "instance-type"
    values = [var.INSTANCE_TYPE]
  }
  filter {
    name   = "location"
    values = [data.aws_subnet.selected.availability_zone]
  }
  location_type = "availability-zone"
  lifecycle {
    postcondition {
      condition     = contains(self.instance_types, var.INSTANCE_TYPE)
      error_message = "INSTANCE_TYPE \"${var.INSTANCE_TYPE}\" is not offered in the subnet's availability zone \"${data.aws_subnet.selected.availability_zone}\"."
    }
  }
}

resource "aws_instance" "client" {
  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = var.INSTANCE_TYPE
  subnet_id                   = var.SUBNET
  vpc_security_group_ids      = [var.SECURITY_GROUP_ID]
  associate_public_ip_address = var.ASSOCIATE_PUBLIC_IP_ADDRESS
  monitoring                  = true
  ebs_optimized               = true
  iam_instance_profile        = aws_iam_instance_profile.client.name
  depends_on                  = [var.CLUSTER_READY]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = local.user_data

  tags = {
    Name                         = "${var.PREFIX}-client"
    "knfsd-file-cache:run"       = var.PREFIX
    "knfsd-file-cache:component" = "nfs-client"
    "knfsd-file-cache:status"    = "starting"
    # The smoke-test Go driver reads these tags from IMDSv2 to discover where
    # to mount NFS from for source-vs-proxy comparison checks.
    (local.source_host_tag) = var.SOURCE_HOST
    (local.proxy_host_tag)  = var.PROXY_HOST
  }

  lifecycle {
    ignore_changes = [tags["knfsd-file-cache:status"]]
  }
}
