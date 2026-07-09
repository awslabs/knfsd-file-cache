# Copyright 2020 Google Inc.
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "VERSION" {
  description = "(Required) The version of the KNFSD File Cache."
  type        = string
  nullable    = false
  default     = "1.1.0-alpha.29"
  validation {
    condition     = can(regex("^(?P<major>0|[1-9]\\d*)\\.(?P<minor>0|[1-9]\\d*)\\.(?P<patch>0|[1-9]\\d*)(?:-(?P<prerelease>(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?$", var.VERSION))
    error_message = "VERSION must be a valid semantic version 2.0.0 format. Example: \"1.1.0-alpha.29\"."
  }
}

variable "SUBNET" {
  description = "(Required) The single AWS Subnet ID to use for deployment of the KNFSD solution. No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", var.SUBNET))
    error_message = "SUBNET must be a valid AWS Subnet ID format. Example: \"subnet-038e337f0ff4cd53f\"."
  }
}

variable "TRAFFIC_MODE" {
  description = "(Required) The client traffic distribution mode used to distribute traffic between proxy instances in the KNFSD proxy cluster. Can be either \"dns_round_robin\", \"loadbalancer\", or \"none\". The recommended option is \"dns_round_robin\". If using \"none\" you will need to provide your own solution to handle traffic distribution. No default."
  type        = string
  nullable    = false
  default     = "dns_round_robin"
  validation {
    condition     = contains(["dns_round_robin", "loadbalancer", "none"], var.TRAFFIC_MODE)
    error_message = "Valid values for TRAFFIC_MODE are 'dns_round_robin', 'loadbalancer', and 'none'."
  }
}

variable "LOADBALANCER_IP" {
  description = "(Optional) The static private IPv4 address to use for the Network Load Balancer when \"TRAFFIC_MODE = 'loadbalancer'\". If not specified, a random IP address will be assigned from the VPC Subnet. Default: \"null\"."
  type        = string
  nullable    = true
  default     = null
  validation {
    condition     = var.LOADBALANCER_IP == null || can(regex("^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", var.LOADBALANCER_IP))
    error_message = "When provided, LOADBALANCER_IP must be a valid IPv4 address in dotted decimal notation."
  }
}

variable "DNS_NAME" {
  description = "(Optional) The fully qualified DNS name (FQDN) to use for the KNFSD proxy cluster. Defaults to: \"{PROXY_BASENAME}.aws.internal.\" or \"nlb.{PROXY_BASENAME}.aws.internal.\" [Note: the trailing period is required]. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition     = var.DNS_NAME == "" || can(regex("^(([a-z0-9][a-z0-9\\-]*[a-z0-9])|[a-z0-9]+\\.)*([a-z]+|xn\\-\\-[a-z0-9]+)\\.$", var.DNS_NAME))
    error_message = "When provided, DNS_NAME must be a valid fully qualified domain name (FQDN) ending with a period. It should consist of valid domain name characters: alphanumeric, hyphen, and period(s)."
  }
}

variable "ASG_EGRESS_CIDR" {
  description = "(Optional) The IPv4 CIDR block to use for the Auto Scaling Group (ASG) EGRESS rule for KNFSD proxy instances. Default: \"0.0.0.0/0\"."
  type        = string
  nullable    = false
  default     = "0.0.0.0/0"
  validation {
    condition     = can(cidrnetmask(var.ASG_EGRESS_CIDR))
    error_message = "ASG_EGRESS_CIDR must be a valid IPv4 CIDR block. Example: \"0.0.0.0/0\"."
  }
}

variable "NFS_PORTS" {
  description = "(Optional) The list of NFS ports (TCP & UDP) to create security group INGRESS rules for the KNFSD proxy instances in the Auto Scaling Group (ASG)/Network Load Balancer (NLB). Default: see \"map(object({port = number, check_port = number, name = string}))\"."
  # mountd default: tcp/udp:20048 as per IANA, RFC8267
  # 'showmount' udp:111 rpcbind/portmapper
  # tcp/udp:20049 (NFS over RDMA) skipped, tcp:20052 & tcp:20054 are outgoing ports, so not required. Outbound=0.0.0.0/0
  type = map(object({
    port       = number
    check_port = number
    name       = string
  }))
  nullable = false
  default = {
    "rpcbind-portmapper" = {
      port       = 111
      check_port = 111
      name       = "rpc-portmap"
    },
    "nfsd" = {
      port       = 2049
      check_port = 2049
      name       = "nfsd"
    },
    "mountd" = {
      port       = 20048
      check_port = 2049
      name       = "mountd"
    },
    "lockd-nlm" = {
      port       = 20050
      check_port = 2049
      name       = "lockd-nlm"
    },
    "statd" = {
      port       = 20051
      check_port = 2049
      name       = "statd"
    },
    "lockd" = {
      port       = 20053
      check_port = 2049
      name       = "lockd"
    },
    "nfs-callback" = {
      port       = 20055
      check_port = 2049
      name       = "nfs-callback"
    }
  }
}

variable "HEALTHCHECK_INITIAL_DELAY_SECONDS" {
  description = "(Optional) Initial delay before a failing health check will replace an proxy instance. This allows the proxy time to start up. Note, this only applies to the initial boot. If you reboot a proxy instance this initial interval does not apply. Default: \"600\"."
  type        = number
  nullable    = false
  default     = 600
}

variable "HEALTHCHECK_INTERVAL_SECONDS" {
  description = "(Optional) How frequently (in seconds) to probe if a proxy instance is healthy. This is measured from the start of one probe, to the start of the next probe. Default: \"60\"."
  type        = number
  nullable    = false
  default     = 60
  validation {
    condition     = var.HEALTHCHECK_INTERVAL_SECONDS >= 5 && var.HEALTHCHECK_INTERVAL_SECONDS <= 300
    error_message = "HEALTHCHECK_INTERVAL_SECONDS must be between 5 and 300 seconds."
  }
}

variable "HEALTHCHECK_TIMEOUT_SECONDS" {
  description = "(Optional) How long (in seconds) to wait for a response from a probe. Must be less than or equal to \"HEALTHCHECK_INTERVAL_SECONDS\". Default: \"5\"."
  type        = number
  nullable    = false
  default     = 5
  validation {
    condition     = var.HEALTHCHECK_TIMEOUT_SECONDS >= 2 && var.HEALTHCHECK_TIMEOUT_SECONDS <= 120
    error_message = "HEALTHCHECK_TIMEOUT_SECONDS must be between 2 and 120 seconds."
  }
}

variable "HEALTHCHECK_HEALTHY_THRESHOLD" {
  description = "(Optional) Number of sequential successful probe results for a proxy instance to be considered healthy. Default: \"3\"."
  type        = number
  nullable    = false
  default     = 3
  validation {
    condition     = var.HEALTHCHECK_HEALTHY_THRESHOLD >= 2 && var.HEALTHCHECK_HEALTHY_THRESHOLD <= 10
    error_message = "HEALTHCHECK_HEALTHY_THRESHOLD must be between 2 and 10."
  }
}

variable "HEALTHCHECK_UNHEALTHY_THRESHOLD" {
  description = "(Optional) Number of sequential failed probe results for a proxy instance to be considered unhealthy. Default: \"3\"."
  type        = number
  nullable    = false
  default     = 3
  validation {
    condition     = var.HEALTHCHECK_UNHEALTHY_THRESHOLD >= 2 && var.HEALTHCHECK_UNHEALTHY_THRESHOLD <= 10
    error_message = "HEALTHCHECK_UNHEALTHY_THRESHOLD must be between 2 and 10."
  }
}

variable "EXPORT_MAP" {
  description = "(Optional) A list of NFS Exports to mount from source filers and re-export in the format \"<SOURCE_IP/DNS>;<SOURCE_EXPORT>;<TARGET_EXPORT>\". Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "EXPORT_HOST_AUTO_DETECT" {
  description = "(Optional) A list of IP addresses or hostnames of NFS filers that respond to the \"showmount\" command. KNFSD will automatically detect and re-export mounts from this filer. Exports paths on the cache will match the export path on the source filer. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "EXCLUDED_EXPORTS" {
  description = "(Optional) A list of filter patterns to be excluded from auto-discovery (see Filter Patterns). Auto-discovery will ignore any exports that match any of the exclude patterns. Does not apply to mounts specified in the \"EXPORT_MAP\". Paths filtered from auto-discovery can be explicitly exported using \"EXPORT_MAP\", this can be used to change the export path. Default: \"\"."
  type        = list(string)
  nullable    = false
  default     = []
}

variable "INCLUDED_EXPORTS" {
  description = "(Optional) If set, auto-discovery will only include paths matching a filter pattern from the include list (see Filter Patterns). Does not apply to mounts specified in the \"EXPORT_MAP\". Paths filtered from auto-discovery can be explicitly exported using \"EXPORT_MAP\", this can be used to change the export path. Default: \"\"."
  type        = list(string)
  nullable    = false
  default     = []
}

variable "ENABLE_NETAPP_AUTO_DETECT" {
  description = "(Optional) Enables automatic discovery of exports using the NetApp REST API. Default: \"false\"."
  type        = bool
  nullable    = false
  default     = false
}

variable "NETAPP_HOST" {
  description = "(Optional) DNS or IP of the NetApp server. This is the DNS or IP name clients use when mounting the NFS shares. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "NETAPP_URL" {
  description = "(Optional) URL of the NetApp REST API. This must include the API version and end with a slash, for example \"https://netapp.example/api/v1/\". Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "NETAPP_USER" {
  description = "(Optional) The username used to authenticate with the NetApp REST API. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "NETAPP_SECRET" {
  description = "(Optional) The name of an AWS Secrets Manager 'Secret' containing the NetApp REST API password. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "NETAPP_SECRET_REGION" {
  description = "(Optional) The AWS Region where AWS Secrets Manager is storing the NetApp password. Default: \"\" (AWS region that knfsd is running in)."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition     = var.NETAPP_SECRET_REGION == "" || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.NETAPP_SECRET_REGION))
    error_message = "When provided, NETAPP_SECRET_REGION must be a valid AWS Region format. Example: \"us-east-1\"."
  }
}

variable "NETAPP_SECRET_VERSION" {
  description = "(Optional) The version of the AWS Secrets Manager 'Secret'. Default: \"AWSCURRENT\"."
  type        = string
  nullable    = false
  default     = "AWSCURRENT"
}

variable "NETAPP_CA" {
  description = "(Optional) PEM encoded certificate containing the root certificate for the NetApp REST API. This can also include intermediate certificates to provide the full certificate chain. To read this from a file use the Terraform file function. Example: file(\"path/to/netapp-ca.pem\"). Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "NETAPP_ALLOW_COMMON_NAME" {
  description = "(Optional) Allows using the Common Name (CN) field of the certificate as a DNS name when the certificate does not include a Subject Alternate Name (SAN) field. Default: \"false\"."
  type        = bool
  nullable    = false
  default     = false
}

variable "PROXY_BASENAME" {
  description = "(Optional) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). Default: \"knfsd\"."
  type        = string
  nullable    = false
  default     = "knfsd"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,27}[a-zA-Z0-9]$", var.PROXY_BASENAME))
    error_message = "PROXY_BASENAME must be 2-29 characters long, contain only alphanumeric characters or hyphens, and cannot begin or end with a hyphen."
  }
}

variable "VPC_CIDR" {
  description = "(Optional) List of CIDR blocks to use in security group rules. If empty, the primary VPC CIDR block is used. For secondary VPC CIDRs, you must explicitly provide the full list. Default: []."
  type        = list(string)
  nullable    = false
  default     = []
  validation {
    condition     = alltrue([for c in var.VPC_CIDR : can(cidrnetmask(c))])
    error_message = "VPC_CIDR must all be valid IPv4 CIDR blocks. Example: \"10.0.0.0/16\"."
  }
}

variable "EXPORT_CIDR" {
  description = "(Optional) List of CIDR blocks to use in NFSD \"/etc/exports.d/knfsd.exports\" file. If empty, the primary VPC CIDR block is used. For secondary VPC CIDRs, you must explicitly provide the full list. Default: []."
  type        = list(string)
  nullable    = false
  default     = []
  validation {
    condition     = alltrue([for c in var.EXPORT_CIDR : can(cidrnetmask(c))])
    error_message = "EXPORT_CIDR must all be valid IPv4 CIDR blocks. Example: \"10.0.0.0/16\"."
  }
}

variable "PROXY_AMI" {
  description = "(Required) The AMI ID of the KNFSD image, built by Packer. Must match the architecture of INSTANCE_TYPE. No default."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^ami-[0-9a-f]{8}$|^ami-[0-9a-f]{17}$", var.PROXY_AMI))
    error_message = "PROXY_AMI must be a valid AMI ID."
  }
}

variable "PROXY_AMI_OWNERS" {
  description = "(Optional) List of AMI owners to limit AMI search. Valid values: an AWS \"account ID\", \"self\" (the current account), or an AWS owner alias (\"amazon\", \"aws-marketplace\"). Default: [\"self\"]."
  type        = list(string)
  nullable    = false
  default     = ["self"]
}

variable "KEY_NAME" {
  description = "(Optional) The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "ASSOCIATE_PUBLIC_IP_ADDRESS" {
  description = "(Optional) Whether to associate a public IPv4 address with the KNFSD proxy EC2 instances. When \"null\", the instance inherits the subnet's \"MapPublicIpOnLaunch\" attribute. Set to \"true\" to force a public IP (e.g. for IGW-only subnets without a NAT or VPC endpoints), or \"false\" to never assign one regardless of the subnet setting. Default: \"null\"."
  type        = bool
  nullable    = true
  default     = null
}

variable "KNFSD_NODES" {
  description = "(Optional) The number of KNFSD instances to deploy as part of the cluster. Default: \"1\"."
  type        = number
  nullable    = false
  default     = 1
}

variable "RESERVE_KNFSD_CAPACITY" {
  description = "(Optional) Create an EC2 Capacity Reservation for the cluster. The KNFSD nodes are often large instances with lots of local NVMe storage. This means they can sometimes be difficult to schedule which can cause delays when replacing unhealthy instances. A reservation ensures that the capacity for the KNFSD cluster is always available in AWS, regardless of the state of the instances. A reservation is not a commitment, and can be deleted at any time. Default: \"false\"."
  type        = bool
  default     = false
}

variable "INSTANCE_TAGS" {
  description = "(Optional) AWS TAGS to apply to all KNFSD proxy EC2 instances. Default: {}."
  type        = map(string)
  default     = {}
}

variable "VFS_CACHE_PRESSURE" {
  description = "(Optional) The value to set for \"vfs_cache_pressure\" Rule. Default: \"1\"."
  type        = number
  nullable    = false
  default     = 1
  validation {
    condition     = var.VFS_CACHE_PRESSURE >= 0 && var.VFS_CACHE_PRESSURE <= 100
    error_message = "VFS_CACHE_PRESSURE must be between 0 and 100."
  }
}

variable "READ_AHEAD" {
  description = "(Optional) The NFS readahead value in bytes, applied via nfsrahead udev rule in \"/etc/nfs.conf.d/knfsd.conf\". Applies to all NFS mounts. Default: \"8388608\" (8 * 1024 * 1024 bytes = 8 MiB)."
  type        = number
  nullable    = false
  default     = 8388608
  validation {
    condition     = var.READ_AHEAD >= 1048576 && var.READ_AHEAD <= 15728640
    error_message = "READ_AHEAD must be between 1048576 (1 MiB) and 15728640 (15 MiB)."
  }
}

variable "ENABLE_METRICS" {
  description = "(Optional) Enable the KNFSD Metrics (Open-Telemetry) Agent. Default: \"true\"."
  type        = bool
  nullable    = false
  default     = true
}

variable "METRICS_AGENT_CONFIG" {
  description = "(Optional) Custom YAML configuration for the metrics agent. The configuration is not validated by Terraform when using a custom config, please check the proxy startup log. See the custom configuration section in the metrics documentation for more details. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "CUSTOM_PRE_STARTUP_SCRIPT" {
  description = "(Optional) bash script to run BEFORE the \"proxy-startup.sh\" script. For example \"file('/home/$USER/myscript.sh')\". Default: \"echo 'No action taken'\"."
  type        = string
  nullable    = false
  default     = "echo 'No action taken'"
}

variable "CUSTOM_POST_STARTUP_SCRIPT" {
  description = "(Optional) bash script to run AFTER the \"proxy-startup.sh\" script. For example \"file('/home/$USER/myscript.sh')\". Default: \"echo 'No action taken'\"."
  type        = string
  nullable    = false
  default     = "echo 'No action taken'"
}

variable "INSTANCE_TYPE" {
  description = "(Optional) The AWS EC2 instance type to use for the KNFSD cache. Must match PROXY_AMI architecture. Default: \"i3en.6xlarge\"."
  type        = string
  default     = "i3en.6xlarge"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.(metal(-[0-9]+xl)?|[a-z0-9]+)$", var.INSTANCE_TYPE))
    error_message = "INSTANCE_TYPE must be a valid AWS EC2 instance type."
  }
}

variable "ROOT_DISK_SIZE" {
  description = "(Optional) The size of the root disk in GB. Default: \"20\"."
  type        = number
  nullable    = false
  default     = 20
  validation {
    condition     = var.ROOT_DISK_SIZE >= 10 && var.ROOT_DISK_SIZE <= 65536
    error_message = "ROOT_DISK_SIZE must be between 10 and 65536 GB."
  }
}

variable "EBS_KMS_KEY_ID" {
  description = "(Optional) Customer-managed KMS key identifier (key ID, alias, key ARN, or alias ARN) used to encrypt EBS volumes. When empty, AWS uses the account's default \"aws/ebs\" key. Volumes are always encrypted. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition = (
      var.EBS_KMS_KEY_ID == ""
      || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.EBS_KMS_KEY_ID))
      || can(regex("^mrk-[0-9a-f]{32}$", var.EBS_KMS_KEY_ID))
      || can(regex("^alias/[a-zA-Z0-9/_-]+$", var.EBS_KMS_KEY_ID))
      || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:(key|alias)/", var.EBS_KMS_KEY_ID))
    )
    error_message = "EBS_KMS_KEY_ID must be empty or a valid KMS key ID, alias, key ARN, or alias ARN."
  }
}

variable "ENABLE_KNFSD_AGENT" {
  description = "(Optional) Enable the KNFSD HTTP Agent. Default: \"true\"."
  type        = bool
  nullable    = false
  default     = true
}

variable "ENABLE_STATUS_CHECK" {
  description = "(Optional) Whether to enable the status check that waits for all EC2 instances to be KNFSD status: \"ready\" during Terraform deployment. Must be \"true\" for \"fanout\" deployments. Default: \"false\"."
  type        = bool
  nullable    = false
  default     = false
}

variable "CACHEFILESD_DISK_TYPE" {
  description = "(Optional) The disk type to use for the cachefiles directory. Can be either \"local-nvme\", \"ebs-gp3\" or \"ebs-io2\". Local ephemeral NVMe provides the highest performance, whilst EBS can provide data persistence. Default: \"local-nvme\"."
  type        = string
  nullable    = false
  default     = "local-nvme"

  validation {
    condition     = contains(["local-nvme", "ebs-gp3", "ebs-io2"], var.CACHEFILESD_DISK_TYPE)
    error_message = "Valid values for CACHEFILESD_DISK_TYPE are 'local-nvme', 'ebs-gp3' or 'ebs-io2'."
  }
}

variable "CACHEFILESD_EBS_COUNT" {
  description = "(Optional) (Only used if \"CACHEFILESD_DISK_TYPE\" = \"ebs-gp3\" or \"ebs-io2\"), the number of EBS volumes to create for cachefilesd (1-8). If >1, then RAID 0 array is created. Default: \"1\"."
  type        = number
  nullable    = false
  default     = 1
  validation {
    condition     = var.CACHEFILESD_EBS_COUNT >= 1 && var.CACHEFILESD_EBS_COUNT <= 8
    error_message = "CACHEFILESD_EBS_COUNT must be between 1 and 8."
  }
}

variable "CACHEFILESD_EBS_SIZE" {
  description = "(Optional) (Only used if \"CACHEFILESD_DISK_TYPE\" = \"ebs-gp3\" or \"ebs-io2\"), the size of the EBS volume in GB. \"ebs-gp3\" supports 1 GiB - 65536 GiB (64 TiB), \"ebs-io2\" supports 4 GiB - 65536 GiB (64 TiB). Default: \"1024\"."
  type        = number
  nullable    = false
  default     = 1024
}

variable "CACHEFILESD_EBS_IOPS" {
  description = "(Optional) (Only used if \"CACHEFILESD_DISK_TYPE\" = \"ebs-gp3\" or \"ebs-io2\"), the number of I/O operations per second (IOPS) for the EBS volume. \"ebs-gp3\" supports 3000 - 80000 IOPS, \"ebs-io2\" supports 100 - 256000 IOPS. Default: \"3000\"."
  type        = number
  nullable    = false
  default     = 3000
}

variable "CACHEFILESD_EBS_THROUGHPUT" {
  description = "(Optional) (Only used if \"CACHEFILESD_DISK_TYPE\" = \"ebs-gp3\"), the throughput (MB/s) for the EBS volume. \"ebs-gp3\" supports 125 - 2000 MiB/s. Default: \"125\"."
  type        = number
  nullable    = false
  default     = 125
}

variable "NCONNECT" {
  description = "(Optional) The number of TCP connections to use when connecting to the source. Default: \"16\"."
  type        = number
  nullable    = false
  default     = 16
  validation {
    condition     = var.NCONNECT >= 1 && var.NCONNECT <= 16
    error_message = "NCONNECT must be between 1 and 16."
  }
}

variable "ACREGMIN" {
  description = "(Optional) The minimum time (in seconds) that the NFS client caches attributes of a regular file. Default: \"600\"."
  type        = number
  nullable    = false
  default     = 600
}

variable "ACREGMAX" {
  description = "(Optional) The maximum time (in seconds) that the NFS client caches attributes of a regular file. Default: \"600\"."
  type        = number
  nullable    = false
  default     = 600
}

variable "ACDIRMIN" {
  description = "(Optional) The minimum time (in seconds) that the NFS client caches attributes of a directory. Default: \"600\"."
  type        = number
  nullable    = false
  default     = 600
}

variable "ACDIRMAX" {
  description = "(Optional) The maximum time (in seconds) that the NFS client caches attributes of a directory. This can be reduced to improve the cache coherency for \"readdir\" operations (e.g \"ls\") at the cost of increasing metadata requests to the source. Default: \"600\"."
  type        = number
  nullable    = false
  default     = 600
}

variable "RSIZE" {
  description = "(Optional) The maximum number of bytes the proxy will read from the source in a single request. The actual value will be negotiated with the source server to determine the maximum value support by both machines. Default: \"1048576\" (1 MiB)."
  type        = number
  nullable    = false
  default     = 1048576
  validation {
    condition     = var.RSIZE >= 131072 && var.RSIZE <= 1048576
    error_message = "RSIZE must be between 131072 (128 KiB) and 1048576 (1 MiB)."
  }
}

variable "WSIZE" {
  description = "(Optional) The maximum number of bytes the proxy will write to the source in a single request. The actual value will be negotiated with the source server to determine the maximum value support by both machines. Default: \"1048576\" (1 MiB)."
  type        = number
  nullable    = false
  default     = 1048576
  validation {
    condition     = var.WSIZE >= 131072 && var.WSIZE <= 1048576
    error_message = "WSIZE must be between 131072 (128 KiB) and 1048576 (1 MiB)."
  }
}

variable "MOUNT_OPTIONS" {
  description = "(Optional) Any additional NFS mount options not covered by existing variables. These options will be applied to all NFS mounts. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "NFS_MOUNT_VERSION" {
  description = "(Optional) The mount version to use for NFS client mounts (\"vers\" option). Acceptable values are \"3\", \"4\", \"4.0\", \"4.1\", \"4.2\". Default: \"3\"."
  type        = string
  nullable    = false
  default     = "3"
  validation {
    condition     = contains(["3", "4", "4.0", "4.1", "4.2"], var.NFS_MOUNT_VERSION)
    error_message = "Valid values for NFS_MOUNT_VERSION are '3', '4', '4.0', '4.1', '4.2'."
  }
}

variable "TCP_SLOT_TABLE_ENTRIES" {
  description = "(Optional) The initial number of RPC slot table entries for TCP connections to the source NFS server. Controls how many simultaneous RPC requests the proxy can send to the source filer. Default: \"128\"."
  type        = number
  nullable    = false
  default     = 128
  validation {
    condition     = var.TCP_SLOT_TABLE_ENTRIES >= 2 && var.TCP_SLOT_TABLE_ENTRIES <= 65536
    error_message = "TCP_SLOT_TABLE_ENTRIES must be between 2 and 65536."
  }
}

variable "TCP_MAX_SLOT_TABLE_ENTRIES" {
  description = "(Optional) The maximum number of RPC slot table entries for TCP connections to the source NFS server. Sets the upper limit on concurrent RPC requests the proxy can send to the source filer. Default: \"128\"."
  type        = number
  nullable    = false
  default     = 128
  validation {
    condition     = var.TCP_MAX_SLOT_TABLE_ENTRIES >= 2 && var.TCP_MAX_SLOT_TABLE_ENTRIES <= 65536
    error_message = "TCP_MAX_SLOT_TABLE_ENTRIES must be between 2 and 65536."
  }
}

variable "DISABLED_NFS_VERSIONS" {
  description = "(Optional) The versions of NFS that should be disabled in \"nfs-kernel-server\". Explicitly disabling unwanted NFS versions prevents clients from accidentally auto-negotiating an undesired NFS version. Specify multiple versions to disable with a comma separated list. Acceptable values are \"3\", \"4\", \"4.0\", \"4.1\", \"4.2\". NFS Version 2 is always disabled. Default: \"4.0,4.1,4.2\"."
  type        = string
  nullable    = false
  default     = "4.0,4.1,4.2"
}

variable "NUM_NFS_THREADS" {
  description = "(Optional) The number of NFS threads to use for KNFSD. Default: \"128\"."
  type        = number
  nullable    = false
  default     = 128
  validation {
    condition     = var.NUM_NFS_THREADS >= 16 && var.NUM_NFS_THREADS <= 512
    error_message = "NUM_NFS_THREADS must be between 16 and 512."
  }
}

variable "SVC_RPC_PER_CONNECTION_LIMIT" {
  description = "(Optional) The number of RPC requests that the server will process in parallel from a single connection. The default value is 0 (no limit). Default: \"0\"."
  type        = number
  nullable    = false
  default     = 0
}

variable "NOHIDE" {
  description = "(Optional) When \"true\", adds the \"nohide\" option to all the exports. Overridden by AUTO_REEXPORT. Default: \"true\"."
  type        = bool
  nullable    = false
  default     = true
}

variable "AUTO_REEXPORT" {
  description = "(Optional) When \"true\" enables the \"crossmnt\" option on all exports and automatically re-exports any nested mounts that were not explicitly exported. Default: \"false\"."
  type        = bool
  nullable    = false
  default     = false
}

variable "EXPORT_OPTIONS" {
  description = "(Optional) Any custom NFS exports options. These options will be applied to all NFS exports. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
}

variable "FSID_MODE" {
  description = "(Optional) How to assign FSIDs (File System Identifiers) to each export. The options are \"static\", \"local\", or \"external\". Default: \"external\"."
  type        = string
  nullable    = false
  default     = "external"
  validation {
    condition     = contains(["static", "local", "external"], var.FSID_MODE)
    error_message = "Valid values for FSID_MODE are 'static', 'local', or 'external'."
  }
}

variable "FSID_DATABASE_DEPLOY" {
  description = "(Optional) Set to \"false\" to prevent automatically creating an Amazon RDS PostgreSQL instance when \"FSID_MODE\" is set to \"external\". Default: \"true\"."
  type        = bool
  nullable    = false
  default     = true
}

variable "FSID_DATABASE_CONFIG" {
  description = "(Optional) Allows overriding the default FSID database configuration when \"FSID_MODE\" is set to \"external\". Default: \"{}\"."
  type        = map(any)
  nullable    = false
  default     = {}
  validation {
    condition = (
      length(var.FSID_DATABASE_CONFIG) == 0 ||
      (
        contains(keys(var.FSID_DATABASE_CONFIG), "db_address") &&
        contains(keys(var.FSID_DATABASE_CONFIG), "db_port") &&
        contains(keys(var.FSID_DATABASE_CONFIG), "db_user") &&
        contains(keys(var.FSID_DATABASE_CONFIG), "db_name") &&
        contains(keys(var.FSID_DATABASE_CONFIG), "enable_metrics")
      )
    )
    error_message = "When FSID_DATABASE_CONFIG is provided, all fields (db_address, db_port, db_user, db_name, enable_metrics) must be specified."
  }
}

variable "FSID_DB_SUBNET_GROUP_NAME" {
  description = "(Optional) The name of the Amazon RDS DB subnet group to use for the FSID database. Required when using a non-default VPC. Default: \"null\"."
  type        = string
  nullable    = true
  default     = null
}

variable "FSID_DB_SUBNET_IDS" {
  description = "(Optional) List of 2+ subnet IDs in different availability zones used to automatically create an aws_db_subnet_group. Must include the subnet referenced by var.SUBNET. Mutually exclusive with FSID_DB_SUBNET_GROUP_NAME. Default: \"null\"."
  type        = list(string)
  nullable    = true
  default     = null

  validation {
    condition = (
      var.FSID_DB_SUBNET_IDS == null
      ? true
      : (
        length(var.FSID_DB_SUBNET_IDS) >= 2 &&
        length(var.FSID_DB_SUBNET_IDS) == length(distinct(var.FSID_DB_SUBNET_IDS)) &&
        alltrue([for s in var.FSID_DB_SUBNET_IDS : can(regex("^subnet-[0-9a-f]{8}([0-9a-f]{9})?$", s))])
      )
    )
    error_message = "FSID_DB_SUBNET_IDS must be a list of at least 2 unique, valid subnet IDs. Example: [\"subnet-038e337f0ff4cd53f\", \"subnet-0a1b2c3d4e5f67890\"]."
  }
}

variable "FSID_DATABASE_IAM_POLICY" {
  description = "(Optional) Allows overriding the default FSID database IAM policy when \"FSID_MODE\" is set to \"external\" with custom IAM policy ARN. Default: \"\"."
  type        = string
  nullable    = false
  default     = ""
  validation {
    condition     = var.FSID_DATABASE_IAM_POLICY == "" || can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/.+$", var.FSID_DATABASE_IAM_POLICY))
    error_message = "When provided, FSID_DATABASE_IAM_POLICY must be a valid IAM policy ARN."
  }
}

variable "ENABLE_KNFSD_AUTOSCALING" {
  description = "(Optional) Should autoscaling be enabled for KNFSD? You MUST set the \"ENABLE_METRICS\" variable to \"true\" if enabling autoscaling. Default: \"false\"."
  type        = bool
  nullable    = false
  default     = false
}

variable "KNFSD_AUTOSCALING_NFS_CONNECTIONS_THRESHOLD" {
  description = "(Optional) The number of NFS client connections to KNFSD that should be targeted for each instance (exceeding will trigger a scale-up). Default: \"250\"."
  type        = number
  nullable    = false
  default     = 250
}

variable "KNFSD_AUTOSCALING_MIN_INSTANCES" {
  description = "(Optional) The minimum number of KNFSD instances to set regardless of the traffic volumes. Default: \"1\"."
  type        = number
  nullable    = false
  default     = 1
}

variable "KNFSD_AUTOSCALING_MAX_INSTANCES" {
  description = "(Optional) The maximum number of KNFSD instances to set regardless of the traffic volumes. Default: \"10\"."
  type        = number
  nullable    = false
  default     = 10
}

variable "ASSUME_ROLE_ARN" {
  description = "(Optional) The ARN of the IAM role to assume for AWS CLI commands in local-exec provisioners for CI/CD pipelines. If not provided, no role assumption will be performed and the local-exec provisioner will use the existing AWS credentials from the environment. Example: \"arn:*:iam::123456789012:role/DeploymentRole\". Default: \"null\"."
  type        = string
  nullable    = true
  default     = null
  validation {
    condition = var.ASSUME_ROLE_ARN == null || (
      var.ASSUME_ROLE_ARN != "" && can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/[a-zA-Z0-9+=,.@_-]+$", var.ASSUME_ROLE_ARN))
    )
    error_message = "When provided, ASSUME_ROLE_ARN must be a valid IAM role ARN format. Example: \"arn:*:iam::123456789012:role/DeploymentRole\"."
  }
}
