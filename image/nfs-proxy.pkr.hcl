// Copyright 2023 Google LLC
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

packer {
  required_version = ">= 1.14.0"
  required_plugins {
    amazon = {
      # https://github.com/hashicorp/packer-plugin-amazon
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.8.0"
    }
  }
}

locals {
  version       = "1.1.0-alpha.20"
  timestamp     = formatdate("YYYY-MM-DD-hhmmss", timestamp()) # UTC
  temp_vol_size = 20

  # Architecture-specific AMI names
  ami_name_amd64 = "knfsd-proxy-${local.version}-amd64-${local.timestamp}"
  ami_name_arm64 = "knfsd-proxy-${local.version}-arm64-${local.timestamp}"

  # Build names with architecture suffix
  build_name_amd64 = (
    var.BUILD_NAME == "" ?
    "packer-knfsd-proxy-${local.version}-amd64-${local.timestamp}" :
    "${var.BUILD_NAME}-amd64"
  )
  build_name_arm64 = (
    var.BUILD_NAME == "" ?
    "packer-knfsd-proxy-${local.version}-arm64-${local.timestamp}" :
    "${var.BUILD_NAME}-arm64"
  )

  # Image names with architecture suffix
  image_name_amd64 = (
    var.IMAGE_NAME == "" ?
    "knfsd-proxy-${local.version}-amd64" :
    "${var.IMAGE_NAME}-amd64"
  )
  image_name_arm64 = (
    var.IMAGE_NAME == "" ?
    "knfsd-proxy-${local.version}-arm64" :
    "${var.IMAGE_NAME}-arm64"
  )

  custom_pre_build_script = (
    var.CUSTOM_PRE_BUILD_SCRIPT != "" ?
    file(var.CUSTOM_PRE_BUILD_SCRIPT) :
    "echo 'No action taken'"
  )
  custom_post_build_script = (
    var.CUSTOM_POST_BUILD_SCRIPT != "" ?
    file(var.CUSTOM_POST_BUILD_SCRIPT) :
    "echo 'No action taken'"
  )
}

# https://documentation.ubuntu.com/aws/en/latest/aws-how-to/instances/find-ubuntu-images/
# aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id
# --query 'Parameters[].Value' --output text
data "amazon-parameterstore" "base-ami-amd64" {
  name   = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
  region = var.REGION
}

data "amazon-parameterstore" "base-ami-arm64" {
  name   = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
  region = var.REGION
}

# https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/builder/ebs
source "amazon-ebs" "nfs-proxy-amd64" {

  # increase timeout for AMI creation
  aws_polling {
    delay_seconds = 30
    max_attempts  = 60
  }

  # Networking
  region    = var.REGION
  subnet_id = var.SUBNET

  # Build machine
  source_ami           = data.amazon-parameterstore.base-ami-amd64.value
  instance_type        = "c6in.16xlarge"
  iam_instance_profile = var.IAM_INSTANCE_PROFILE != "" ? var.IAM_INSTANCE_PROFILE : null
  run_tags = {
    "Name"                            = local.build_name_amd64
    "knfsd-file-cache:version"        = local.version
    "knfsd-file-cache:packer:version" = "${packer.version}"
  }

  # SSH Connectivity
  # If using non-default VPC, whether to forcefully associate a public IP address (default: null)
  associate_public_ip_address = var.ASSOCIATE_PUBLIC_IP_ADDRESS

  # Security Group Configuration
  # Priority order (descending):
  # 1. security_group_id
  # 2. security_group_ids
  # 3. temporary_security_group_source_cidrs
  # 4. temporary_security_group_source_public_ip

  # Use existing, single security group ID (highest priority - default: "")
  security_group_id = var.SECURITY_GROUP_ID != "" ? var.SECURITY_GROUP_ID : null

  # Use existing security group IDs (second priority - default: [])
  security_group_ids = length(var.SECURITY_GROUP_IDS) > 0 ? var.SECURITY_GROUP_IDS : null

  # Use custom CIDR blocks for temporary security group (third priority - default: [])
  temporary_security_group_source_cidrs = length(var.TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS) > 0 ? var.TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS : null

  # Use public IP /32 for temporary security group (lowest priority - default: true)
  temporary_security_group_source_public_ip = (
    var.SECURITY_GROUP_ID == "" &&
    length(var.SECURITY_GROUP_IDS) == 0 &&
    length(var.TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS) == 0
  ) ? var.TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP : null

  # EBS root build volume configuration
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    encrypted             = true
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # EBS temp build volume configuration
  launch_block_device_mappings {
    device_name           = "/dev/sdf"
    encrypted             = true
    volume_size           = local.temp_vol_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Output image
  skip_create_ami = var.SKIP_CREATE_IMAGE
  ami_name        = local.ami_name_amd64
  ami_description = <<-EOF
    KNFSD-File-Cache: v${local.version}
    Packer: v${packer.version}
    Source AMI Name: {{ .SourceAMIName }}
    Source AMI ID: {{.SourceAMI }}
  EOF

  ami_virtualization_type = "hvm"

  # EBS root volume configuration
  ami_block_device_mappings {
    device_name           = "/dev/sda1"
    encrypted             = true
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Explicitly exclude ephemeral storage devices
  ami_block_device_mappings {
    device_name = "/dev/sdb"
    no_device   = true
  }

  ami_block_device_mappings {
    device_name = "/dev/sdc"
    no_device   = true
  }

  # Explicitly exclude the temporary EBS build volume from the AMI
  ami_block_device_mappings {
    device_name = "/dev/sdf"
    no_device   = true
  }

  # Metadata options
  imds_support = "v2.0"
  metadata_options {
    http_endpoint          = "enabled"
    http_tokens            = "required"
    instance_metadata_tags = "enabled"
  }
  tags = {
    "Name" = local.image_name_amd64
  }

  # Communicator
  communicator = "ssh"
  ssh_username = "ubuntu"
}

source "amazon-ebs" "nfs-proxy-arm64" {

  # increase timeout for AMI creation
  aws_polling {
    delay_seconds = 30
    max_attempts  = 60
  }

  # Networking
  region    = var.REGION
  subnet_id = var.SUBNET

  # Build machine
  source_ami           = data.amazon-parameterstore.base-ami-arm64.value
  instance_type        = "c7g.16xlarge"
  iam_instance_profile = var.IAM_INSTANCE_PROFILE != "" ? var.IAM_INSTANCE_PROFILE : null
  run_tags = {
    "Name"                            = local.build_name_arm64
    "knfsd-file-cache:version"        = local.version
    "knfsd-file-cache:packer:version" = "${packer.version}"
  }

  # SSH Connectivity
  # If using non-default VPC, whether to forcefully associate a public IP address (default: null)
  associate_public_ip_address = var.ASSOCIATE_PUBLIC_IP_ADDRESS

  # Security Group Configuration
  # Priority order (descending):
  # 1. security_group_id
  # 2. security_group_ids
  # 3. temporary_security_group_source_cidrs
  # 4. temporary_security_group_source_public_ip

  # Use existing, single security group ID (highest priority - default: "")
  security_group_id = var.SECURITY_GROUP_ID != "" ? var.SECURITY_GROUP_ID : null

  # Use existing security group IDs (second priority - default: [])
  security_group_ids = length(var.SECURITY_GROUP_IDS) > 0 ? var.SECURITY_GROUP_IDS : null

  # Use custom CIDR blocks for temporary security group (third priority - default: [])
  temporary_security_group_source_cidrs = length(var.TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS) > 0 ? var.TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS : null

  # Use public IP /32 for temporary security group (lowest priority - default: true)
  temporary_security_group_source_public_ip = (
    var.SECURITY_GROUP_ID == "" &&
    length(var.SECURITY_GROUP_IDS) == 0 &&
    length(var.TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS) == 0
  ) ? var.TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP : null

  # EBS root build volume configuration
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    encrypted             = true
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # EBS temp build volume configuration
  launch_block_device_mappings {
    device_name           = "/dev/sdf"
    encrypted             = true
    volume_size           = local.temp_vol_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Output image
  skip_create_ami = var.SKIP_CREATE_IMAGE
  ami_name        = local.ami_name_arm64
  ami_description = <<-EOF
    KNFSD-File-Cache: v${local.version}
    Packer: v${packer.version}
    Source AMI Name: {{ .SourceAMIName }}
    Source AMI ID: {{.SourceAMI }}
  EOF

  ami_virtualization_type = "hvm"

  # EBS root volume configuration
  ami_block_device_mappings {
    device_name           = "/dev/sda1"
    encrypted             = true
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }

  # Explicitly exclude ephemeral storage devices
  ami_block_device_mappings {
    device_name = "/dev/sdb"
    no_device   = true
  }

  ami_block_device_mappings {
    device_name = "/dev/sdc"
    no_device   = true
  }

  # Explicitly exclude the temporary EBS build volume from the AMI
  ami_block_device_mappings {
    device_name = "/dev/sdf"
    no_device   = true
  }

  # Metadata options
  imds_support = "v2.0"
  metadata_options {
    http_endpoint          = "enabled"
    http_tokens            = "required"
    instance_metadata_tags = "enabled"
  }
  tags = {
    "Name" = local.image_name_arm64
  }

  # Communicator
  communicator = "ssh"
  ssh_username = "ubuntu"
}

build {
  sources = concat(
    contains(var.ARCH, "amd64") ? ["source.amazon-ebs.nfs-proxy-amd64"] : [],
    contains(var.ARCH, "arm64") ? ["source.amazon-ebs.nfs-proxy-arm64"] : []
  )

  # https://developer.hashicorp.com/packer/docs/provisioners/shell
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo {{ .Path }}"
    inline = [
      "device=$(lsblk -o NAME,SIZE,TYPE | grep 'disk' | grep '${local.temp_vol_size}G' | awk '{print $1}' | head -n1)",
      "mkfs.ext4 /dev/$device",
      "mkdir -p /mnt/build",
      "mount /dev/$device /mnt/build",
      "chown ubuntu:ubuntu /mnt/build"
    ]
  }

  # https://developer.hashicorp.com/packer/docs/provisioners/file
  provisioner "file" {
    source      = "${path.root}/resources/"
    destination = "/mnt/build/"
    timeout     = "10m"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo {{ .Path }}"
    inline = [
      "echo '${base64gzip(local.custom_pre_build_script)}' | base64 -d | gzip -d > /mnt/build/scripts/custom-pre-build-script.sh",
      "chmod +x /mnt/build/scripts/custom-pre-build-script.sh",
      "/mnt/build/scripts/custom-pre-build-script.sh"
    ]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo {{ .Path }}"
    inline = [
      "chmod +x /mnt/build/scripts/*.sh",
      "/mnt/build/scripts/10_build.sh 2>&1",
      "reboot"
    ]
    expect_disconnect = true
    pause_after       = "30s"
    timeout           = "1h"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo {{ .Path }}"
    inline = [
      "device=$(lsblk -o NAME,SIZE,TYPE | grep 'disk' | grep '${local.temp_vol_size}G' | awk '{print $1}' | head -n1)",
      "mount /dev/$device /mnt/build",
      "/mnt/build/scripts/20_post_build.sh 2>&1"
    ]
    timeout = "5m"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo {{ .Path }}"
    inline = [
      "echo '${base64gzip(local.custom_post_build_script)}' | base64 -d | gzip -d > /mnt/build/scripts/custom-post-build-script.sh",
      "chmod +x /mnt/build/scripts/custom-post-build-script.sh",
      "/mnt/build/scripts/custom-post-build-script.sh"
    ]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo {{ .Path }}"
    inline = [
      "/mnt/build/scripts/30_finalize.sh 2>&1",
      "umount /mnt/build",
      "rm -rf /mnt/build"
    ]
    expect_disconnect = true
    timeout           = "5m"
  }

  # Output the last build to a manifest file in the current directory.
  # This can be useful for automated tooling, especially if packer generated
  # the image name with a timestamp.
  post-processor "manifest" {
    output = "image.manifest.json"
  }
}
