// Copyright 2023 Google LLC
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

packer {
  # Minimum of packer 1.7 is required to support downloading newer plugin versions.
  # Packer 1.8.1 comes pre-bundled with a supported version of the googlecompute plugin.
  required_version = ">= 1.11.2"

  required_plugins {
    googlecompute = {
      # Need a minimum of 1.0.13 to support the rsa-ssh2-512 key algorithm.
      # The older ssh-rsa (rsa + sha1) algorithm has been removed from the newer
      # versions of OpenSSL as it is no longer secure.
      source  = "github.com/hashicorp/googlecompute"
      version = ">= 1.0.13"
    }
  }
}

locals {
  timestamp = formatdate("YYYY-MM-DD-hhmmss", timestamp())
  image_name = (
    var.IMAGE_NAME == "" ?
    "knfsd-client-${local.timestamp}" :
    var.IMAGE_NAME
  )
}

source "googlecompute" "client" {

  # run location
  project_id = var.PROJECT
  zone       = var.ZONE

  # machine details
  instance_name = var.BUILD_NAME
  # instance_type                   = var.INSTANCE_TYPE
  disk_size                       = 20
  disable_default_service_account = true

  # networking
  network_project_id = var.NETWORK_PROJECT
  subnetwork         = var.SUBNETWORK
  omit_external_ip   = var.OMIT_EXTERNAL_IP

  # source image
  source_image            = "ubuntu-2404-noble-amd64-v20250502a"
  source_image_project_id = ["ubuntu-os-cloud"]

  # target image
  image_name        = local.image_name
  image_description = "KNFSD testing client"

  # communications
  communicator    = "ssh"
  ssh_username    = "build"
  use_iap         = var.USE_IAP
  use_internal_ip = var.USE_INTERNAL_IP

  # lifecycle
  skip_create_image = var.SKIP_CREATE_IMAGE
}

build {
  sources = ["googlecompute.client"]

  provisioner "shell" {
    inline = ["sudo systemctl stop unattended-upgrades.service"]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{.Path}}; {{.Vars}} sudo -E '{{.Path}}'"
    env = {
      DEBIAN_FRONTEND = "noninteractive",
    }
    inline = [
      "apt-get update",
      "apt-get install -y nfs-common",
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*"
    ]
  }

  # Output the last build to a manifest file in the current directory.
  # This can be useful for automated tooling, especially if packer generated
  # the image name with a timestamp.
  post-processor "manifest" {
    output = "image.manifest.json"
  }
}
