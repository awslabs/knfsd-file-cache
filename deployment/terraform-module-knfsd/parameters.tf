/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

# local variable descriptions
# see .devcontainer/dev/parse-variable-descriptions.sh
# to update descriptions {} block from "variables.tf"
locals {
  descriptions = {
    # mounts
    EXPORT_MAP              = "(Optional) A list of NFS Exports to mount from source filers and re-export in the format \"<SOURCE_IP/DNS>;<SOURCE_EXPORT>;<TARGET_EXPORT>\". Default: \"\"."
    EXPORT_HOST_AUTO_DETECT = "(Optional) A list of IP addresses or hostnames of NFS filers that respond to the \"showmount\" command. KNFSD will automatically detect and re-export mounts from this filer. Exports paths on the cache will match the export path on the source filer. Default: \"\"."
    EXCLUDED_EXPORTS        = "(Optional) A list of filter patterns to be excluded from auto-discovery (see Filter Patterns). Auto-discovery will ignore any exports that match any of the exclude patterns. Does not apply to mounts specified in the \"EXPORT_MAP\". Paths filtered from auto-discovery can be explicitly exported using \"EXPORT_MAP\", this can be used to change the export path. Default: \"\"."
    INCLUDED_EXPORTS        = "(Optional) If set, auto-discovery will only include paths matching a filter pattern from the include list (see Filter Patterns). Does not apply to mounts specified in the \"EXPORT_MAP\". Paths filtered from auto-discovery can be explicitly exported using \"EXPORT_MAP\", this can be used to change the export path. Default: \"\"."
    EXPORT_CIDR             = "(Optional) The CIDR to use in \"/etc/exports\" of the KNFSD proxy for filesystem re-export (VPC CIDR of \"SUBNET\" is used if not specified). Default: \"\"."

    # NetApp auto-discovery
    ENABLE_NETAPP_AUTO_DETECT = "(Optional) Enables automatic discovery of exports using the NetApp REST API. Default: \"false\"."
    NETAPP_HOST               = "(Optional) DNS or IP of the NetApp server. This is the DNS or IP name clients use when mounting the NFS shares. Default: \"\"."
    NETAPP_URL                = "(Optional) URL of the NetApp REST API. This must include the API version and end with a slash, for example \"https://netapp.example/api/v1/\". Default: \"\"."
    NETAPP_USER               = "(Optional) The username used to authenticate with the NetApp REST API. Default: \"\"."
    NETAPP_SECRET             = "(Optional) The name of an AWS Secrets Manager 'Secret' containing the NetApp REST API password. Default: \"\"."
    NETAPP_SECRET_REGION      = "(Optional) The AWS Region where AWS Secrets Manager is storing the NetApp password. Default: \"\" (AWS region that knfsd is running in)."
    NETAPP_SECRET_VERSION     = "(Optional) The version of the AWS Secrets Manager 'Secret'. Default: \"AWSCURRENT\"."
    NETAPP_CA                 = "(Optional) PEM encoded certificate containing the root certificate for the NetApp REST API. This can also include intermediate certificates to provide the full certificate chain. To read this from a file use the Terraform file function. Default: \"\"."
    NETAPP_ALLOW_COMMON_NAME  = "(Optional) Allows using the Common Name (CN) field of the certificate as a DNS name when the certificate does not include a Subject Alternate Name (SAN) field. Default: \"false\"."

    # mount options
    NCONNECT          = "(Optional) The number of TCP connections to use when connecting to the source. Default: \"16\"."
    ACDIRMIN          = "(Optional) The minimum time (in seconds) that the NFS client caches attributes of a directory. Default: \"600\"."
    ACDIRMAX          = "(Optional) The maximum time (in seconds) that the NFS client caches attributes of a directory. This can be reduced to improve the cache coherency for \"readdir\" operations (e.g \"ls\") at the cost of increasing metadata requests to the source. Default: \"600\"."
    ACREGMIN          = "(Optional) The minimum time (in seconds) that the NFS client caches attributes of a regular file. Default: \"600\"."
    ACREGMAX          = "(Optional) The maximum time (in seconds) that the NFS client caches attributes of a regular file. Default: \"600\"."
    RSIZE             = "(Optional) The maximum number of bytes the proxy will read from the source in a single request. The actual value will be negotiated with the source server to determine the maximum value support by both machines. Default: \"1048576\"."
    WSIZE             = "(Optional) The maximum number of bytes the proxy will write to the source in a single request. The actual value will be negotiated with the source server to determine the maximum value support by both machines. Default: \"1048576\"."
    NOHIDE            = "(Optional) When \"true\", adds the \"nohide\" option to all the exports. Overridden by AUTO_REEXPORT. Default: \"true\"."
    MOUNT_OPTIONS     = "(Optional) Any additional NFS mount options not covered by existing variables. These options will be applied to all NFS mounts. Default: \"\"."
    EXPORT_OPTIONS    = "(Optional) Any custom NFS exports options. These options will be applied to all NFS exports. Default: \"\"."
    NFS_MOUNT_VERSION = "(Optional) The mount version to use for NFS client mounts (\"vers\" option). Acceptable values are \"3\", \"4\", \"4.0\", \"4.1\", \"4.2\". Default: \"3\"."

    # auto re-export nested mounts
    AUTO_REEXPORT        = "(Optional) When \"true\" enables the \"crossmnt\" option on all exports and automatically re-exports any nested mounts that were not explicitly exported. Default: \"false\"."
    FSID_MODE            = "(Optional) How to assign FSIDs (File System Identifiers) to each export. The options are \"static\", \"local\", or \"external\". Default: \"external\"."
    FSID_DATABASE_CONFIG = "(Optional) Allows overriding the default FSID database configuration when \"FSID_MODE\" is set to \"external\". Default: \"\"."

    # system
    NUM_NFS_THREADS       = "(Optional) The number of NFS Threads to use for KNFSD. Default: \"512\"."
    VFS_CACHE_PRESSURE    = "(Optional) The value to set for \"vfs_cache_pressure\" Rule. Default: \"100\"."
    DISABLED_NFS_VERSIONS = "(Optional) The versions of NFS that should be disabled in \"nfs-kernel-server\". Explicitly disabling unwanted NFS versions prevents clients from accidentally auto-negotiating an undesired NFS version. Specify multiple versions to disable with a comma separated list. Acceptable values are \"3\", \"4\", \"4.0\", \"4.1\", \"4.2\". NFS Version 2 is always disabled. Default: \"4.0,4.1,4.2\"."
    READ_AHEAD            = "(Optional) The number of bytes to read ahead. Must be a multiple of the kernel page size (8 KiB for 5.11). The kernel will round this down to the nearest page. Default: \"8388608\" (8 MiB)."

    # cachefilesd
    CACHEFILESD_DISK_TYPE = "(Optional) The disk type to use for the cachefiles directory. Can be either \"local-nvme\", \"ebs-gp3\" or \"ebs-io2\". Local ephemeral NVMe provides the highest performance, whilst EBS can provide data persistence. Default: \"local-nvme\"."

    # metrics / http agent
    ENABLE_METRICS       = "(Optional) Enable the KNFSD Metrics (Open-Telemetry) Agent. Default: \"true\"."
    METRICS_AGENT_CONFIG = "(Optional) Custom YAML configuration for the metrics agent. The configuration is not validated by Terraform when using a custom config, please check the proxy startup log. See the custom configuration section in the metrics documentation for more details. Default: \"\"."
    ENABLE_KNFSD_AGENT   = "(Optional) Enable the KNFSD HTTP Agent. Default: \"true\"."
  }
}

# create ssm parameters
resource "aws_ssm_parameter" "settings" {
  for_each = {
    # mounts
    EXPORT_MAP              = var.EXPORT_MAP
    EXPORT_HOST_AUTO_DETECT = var.EXPORT_HOST_AUTO_DETECT
    EXCLUDED_EXPORTS        = join("\n", var.EXCLUDED_EXPORTS)
    INCLUDED_EXPORTS        = join("\n", var.INCLUDED_EXPORTS)
    EXPORT_CIDR             = local.export_cidr

    # NetApp auto-discovery
    ENABLE_NETAPP_AUTO_DETECT = var.ENABLE_NETAPP_AUTO_DETECT
    NETAPP_HOST               = var.NETAPP_HOST
    NETAPP_URL                = var.NETAPP_URL
    NETAPP_USER               = var.NETAPP_USER
    NETAPP_SECRET             = var.NETAPP_SECRET
    NETAPP_SECRET_REGION      = var.NETAPP_SECRET_REGION
    NETAPP_SECRET_VERSION     = var.NETAPP_SECRET_VERSION
    NETAPP_CA                 = var.NETAPP_CA
    NETAPP_ALLOW_COMMON_NAME  = var.NETAPP_ALLOW_COMMON_NAME

    # mount options
    NCONNECT          = var.NCONNECT
    ACDIRMIN          = var.ACDIRMIN
    ACDIRMAX          = var.ACDIRMAX
    ACREGMIN          = var.ACREGMIN
    ACREGMAX          = var.ACREGMAX
    RSIZE             = var.RSIZE
    WSIZE             = var.WSIZE
    NOHIDE            = var.NOHIDE
    MOUNT_OPTIONS     = var.MOUNT_OPTIONS
    EXPORT_OPTIONS    = var.EXPORT_OPTIONS
    NFS_MOUNT_VERSION = var.NFS_MOUNT_VERSION

    # auto re-export nested mounts
    AUTO_REEXPORT        = var.AUTO_REEXPORT
    FSID_MODE            = var.FSID_MODE
    FSID_DATABASE_CONFIG = local.fsid_database_config

    # system
    NUM_NFS_THREADS       = var.NUM_NFS_THREADS
    VFS_CACHE_PRESSURE    = var.VFS_CACHE_PRESSURE
    DISABLED_NFS_VERSIONS = var.DISABLED_NFS_VERSIONS
    READ_AHEAD            = var.READ_AHEAD

    # cachefilesd
    CACHEFILESD_DISK_TYPE = var.CACHEFILESD_DISK_TYPE

    # metrics / http agent
    ENABLE_METRICS       = var.ENABLE_METRICS
    METRICS_AGENT_CONFIG = var.METRICS_AGENT_CONFIG
    ENABLE_KNFSD_AGENT   = var.ENABLE_KNFSD_AGENT
  }

  name        = "/knfsd/${local.name}/${each.key}"
  type        = "SecureString"
  value       = each.value != "" ? each.value : "\"\""
  description = local.descriptions[each.key]
  tags        = local.tags
}
