# KNFSD-File-Cache

## v1.1.0-alpha.26

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Packer: Updated to Linux kernel v7.0.6-knfsd.
* Added support for customer-managed KMS keys for AMI encryption, AMI cross-region distribution, and EBS volume encryption.
* Packer: Added new Packer variables for AMI encryption and cross-region distribution: `KMS_KEY_ID`, `AMI_ENCRYPTED`, `DISTRIBUTION_REGIONS`, and `REGION_KMS_KEY_IDS`. See [image/README.md](image/README.md) for usage and the three supported encryption modes (default `aws/ebs`, customer-managed key, unencrypted). Customer-managed KMS keys and key policies are the customer's responsibility and not created or managed by this project.
* Packer: Added `ec2:CopyImage`, `ec2:CopySnapshot`, and `ec2:DeregisterImage` to [docs/iam/packer.json](docs/iam/packer.json) (`KnfsdPackerBuild` Sid) to support cross-region AMI distribution.
* Added new Terraform variable `EBS_KMS_KEY_ID` to `terraform-module-knfsd` for customer-managed encryption of launch-template EBS volumes. Volumes remain encrypted by default; when empty, AWS uses the account's default `aws/ebs` key. See [deployment/README.md](deployment/README.md).
* Added no-op `Helper()` method to `testRunner` in `testing/examples/testing/runner.go` to satisfy the `Helper()` method now required by `terratest.TestingT` (added upstream in Terratest v1.0.0).
* Updated `opentelemetry-collector` to v0.152.0.
* Updated `opentelemetry-collector-contrib` to v0.152.0.
* Renamed `metricstransform` processor to `metrics_transform` as per Open Telemetry Collector Contrib issue [#45339](https://github.com/open-telemetry/opentelemetry-collector-contrib/issues/45339).
* Updated to Golang v1.26.3.
* Updated to Python v3.14.5.
* Minor Golang package updates.

## v1.1.0-alpha.25

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

> BREAKING CHANGES: Project-wide naming alignment from `nfsproxy` and `nfs-proxy` to `knfsd`.

* Packer: Updated to Linux kernel v7.0.4-knfsd.
* Renamed `nfs-proxy.pkr.hcl` to `knfsd.pkr.hcl` in `packer/image` directory.
* Changed `PROXY_BASENAME` default from `nfsproxy` to `knfsd` in `terraform-module-knfsd` and all `examples/*/variables.tf`.
* Changed database module `NAME_PREFIX` default from `fsids` to `knfsd-fsids`.
* Renamed user-facing module outputs: `nfsproxy_loadbalancer_ipaddress` → `loadbalancer_ipaddress` and `nfsproxy_security_group_id` → `knfsd_security_group_id`.
* Removed `nfsproxy_loadbalancer_dnsaddress` output from `*/outputs.tf` as duplication of `dns_name` output.
* Renamed internal Terraform resource addresses (`aws_security_group.nfsproxy_*` → `knfsd_*`, `aws_launch_template.nfsproxy_template` → `knfsd_launch_template`, `aws_lb.nfsproxy_lb` → `knfsd_lb`, `aws_lb_target_group.nfsproxy_lb_tg` → `knfsd_lb_tg`, `aws_route53_zone.nfsproxy` → `knfsd`, etc).
* Added new project-wide IAM reference at `docs/iam.md` and the canonical IAM policy files under `docs/iam/`: `packer.json` (Packer AMI build), `tf-required.json` (always-required deploy Sids), and `tf-optional.json` (feature-gated deploy Sids).
* Updated `deployment/docs/vpc-endpoints.md` with runtime-only scope, added missing `ec2messages` interface endpoint, and added cross-region interface endpoints for IAM (`com.amazonaws.iam`) and Route 53 (`com.amazonaws.route53`) in `us-east-1` per the November 2025 [AWS PrivateLink cross-region](https://aws.amazon.com/blogs/networking-and-content-delivery/aws-privatelink-extends-cross-region-connectivity-to-aws-services/) announcement.
* Replaced the inline IAM policy example in `image/README.md` with a pointer to `docs/iam.md` and `docs/iam/packer.json`.
* Fixed regression introduced in `v1.1.0-alpha.24` where the `terraform-module-knfsd` module rejected `FSID_DB_SUBNET_GROUP_NAME` / `FSID_DB_SUBNET_IDS` in multi-AZ deployments where sibling modules consume an existing FSID database via `FSID_DATABASE_CONFIG`.
* Added `iamlive` tool to `.devcontainer/dev` environment for creating IAM policies.
* Exposed `TRAFFIC_MODE` Terraform variable to the `fsx-zfs` example.
* Set default value for `TRAFFIC_MODE` Terraform variable to `dns_round_robin`.
* Packer: Added `snap_refresh` function to `10_build.sh` script to retry `snap refresh` commands up to 5 times with a 10-50s delay between attempts to guard against transient "unable to contact snap store" errors from `api.snapcraft.io`.
* Updated KNFSD Monitoring Dashboard to `v13`.
* Packer: Updated to `amzn/amzn-drivers` ENA driver v2.17.0.
* Packer: Updated to `amazon-efs-utils` v3.1.1.
* Updated to Packer v1.15.3.
* Updated to Terraform `aws` provider v6.44.0.
* Minor Golang package updates.

## v1.1.0-alpha.24

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

> BREAKING CHANGES: Ensure `.devcontainer/dev` environment is rebuilt if used for local development.

> EXPERIMENTAL: Amazon S3 Files (`s3files`) support is experimental and subject to change.

* Packer: Updated to Linux kernel v6.19.14-knfsd.
* Updated `opentelemetry-collector-contrib` to v0.150.0 to fix bugs in `exporter/awsemf`: Fix data races in `getPusher` and `logPusher` that cause nil pointer panics and out-of-order log events ([#47126](https://github.com/open-telemetry/opentelemetry-collector-contrib/issues/47126))
* Added support for EC2 [Instance Bandwidth Configuration](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configure-bandwidth-weighting.html) (bandwidth weighting). Only certain EC2 instance types support this feature; when the instance type is detected as supported, the configuration is applied automatically. This can increase network bandwidth available to the instance by up to 25% (at the cost of reduced baseline EBS bandwidth for the same instance).
* Added support for [ENA Express](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ena-express.html) (ENA-X), which is automatically enabled when the selected EC2 instance type for the KNFSD instance supports it. ENA Express can raise maximum single-flow bandwidth from 5 Gbps to 25 Gbps for NFS traffic between instances in the same Availability Zone, up to the instance’s aggregate network limit. Both TCP and UDP will use ENA-X. The sending and receiving instances (KNFSD instance and NFS client instances) must both support ENA-X for it to be enabled. If any requirement is unmet, traffic falls back gracefully to standard TCP/UDP without ENA-X.
* Added ENA-X support to secondary ENI attachment via Lambda `static_ip` function in `dns_round_robin` module.
* Added `configure_network()` function to `proxy-startup.sh` that tunes the Linux network stack and ENA driver on every boot for high-throughput NFS proxy traffic. Kernel-level changes include raising socket buffer ceilings (`rmem_max`/`wmem_max`) to 16 MB, increasing `netdev_max_backlog` to 16384, widening TCP auto-tuning ranges to 16 MB, and raising `tcp_limit_output_bytes` to 1 MB for ENA-X. Per-ENA-interface tuning sets MTU to 8900, Rx ring buffers to 8192, enables adaptive Rx interrupt coalescing, and configures Receive Packet Steering (RPS) across all vCPUs to distribute softirq processing evenly.
* Replaced manual sysfs-based `configure_read_ahead()` function in `proxy-startup.sh` with declarative `[nfsrahead]` configuration in `/etc/nfs.conf.d/knfsd.conf`. Readahead is now applied automatically via the `nfsrahead` udev tool to all NFS mounts, including `autofs`-triggered nested mounts. Amazon Elastic File System (EFS) mounts are unaffected as `efs-utils` overwrites `read_ahead_kb` after mount.
* [EXPERIMENTAL] Added Amazon S3 Files (`s3files`) filesystem type support in `proxy-startup.sh`. The `s3files` mount helper (`mount.s3files`) is now handled identically to `mount.efs`: `nconnect` is stripped and the mount helper's own retry logic is used (single attempt).
* Fixed CloudWatch metrics `server` dimension showing `127.0.0.1` for Amazon EFS and S3 Files mounts. The `knfsd-metrics-agent` now reads `efs-utils` state files from `/var/run/efs/` at scrape time to resolve the proxy loopback address to the real DNS name (e.g. `<fs-id>.efs.<region>.amazonaws.com` or `<az-id>.<fs-id>.s3files.<region>.on.aws`).
* [EXPERIMENTAL] Added `examples/s3-files` Terraform example demonstrating [Amazon S3 Files](https://aws.amazon.com/blogs/aws/launching-s3-files-making-s3-buckets-accessible-as-file-systems/) fronted by KNFSD proxy. Provisions S3 bucket with versioning, S3 Files filesystem, mount target, synchronization configuration, and required IAM roles/policies.
* Added `FSID_DB_SUBNET_IDS` variable to the `database` and `terraform-module-knfsd` modules. Callers using a non-default VPC can now pass a list of 2+ subnet IDs and the module will create the `aws_db_subnet_group` automatically. Mutually exclusive with `FSID_DB_SUBNET_GROUP_NAME`. Pre-apply validation enforces at least 2 unique subnets, inclusion of `var.SUBNET`, which must be in the same VPC as `var.SUBNET`, and coverage of at least 2 availability zones within the AWS region. See [FSID Database Options](deployment/README.md#fsid-database-options). Default VPC is still supported when both variables are `null` (default).
* Hardened `knfsd-fsidd` against transient RDS IAM authentication failures caused by IAM policy propagation races on fresh deployments. Added SQLSTATE `28000` ("PAM authentication failed") to the retryable error set in `retry.go`, and bounded the boot-time `CreateTable` retry window to 90 secs via a new `withRetryDeadline` helper (socket-handler retries remain at the default 5 min). Added `Restart=on-failure`, `RestartSec=10s`, `StartLimitBurst=3`, `StartLimitIntervalSec=600` to `knfsd-fsidd.service`; worst-case cumulative retry time before systemd marks the unit failed is ~5 mins.
* Added `iam_role_name` output to KNFSD proxy Terraform module (`deployment/terraform-module-knfsd/outputs.tf`) to allow external IAM policy attachments.
* Pre-create the `knfsd/metrics` CloudWatch log group in `proxy-startup.sh` before starting `knfsd-metrics-agent` to avoid `OperationAbortedException` when multiple scrapers concurrently call `CreateLogGroup` on first boot of first KNFSD instance.
* Updated KNFSD Monitoring Dashboard to `v12`.
* Added `ENA-X` (SRD) metrics to `amazon-cloudwatch-agent.json` file.
* Added `net_packets_recv` and `net_packets_sent` metrics to `amazon-cloudwatch-agent.json` file.
* Added `ENA-X` (SRD) metric widgets to CloudWatch `metrics` dashboard.
* Added support to CloudWatch `metrics` dashboard to filter by different `udev` network interface names for different generation EC2 instance types.
* Added Terraform validation to ensure selected `INSTANCE_TYPE` is offered in the selected subnet's availability zone.
* Rename references to `fsidd.sock` to `knfsd-fsidd.sock` to be consistent (naming convention now matches: `/run/knfsd-metrics.sock`).
* Added `ExecStopPost=` to `knfsd-metrics-agent` systemd service via AMI build file: `proxy.service` to remove the metrics socket file after the service stops.
* Added `GOMEMLIMIT` environment variable to `knfsd-metrics-agent` systemd service files: `proxy.service` and `client.service` to limit the amount of memory available to the agent.
* Updated `memory_limiter` configuration in `knfsd-metrics-agent` configuration `common.yaml` file to limit the amount of memory available to the agent to 512 MiB with a spike limit of 128 MiB.
* Increased collection interval of `fscache` and `netfs` metrics from `30s` to `1m` in `knfsd-metrics-agent` configuration `common.yaml` file.
* Added `rpc.mountd[]: can't stat exported dir /acme/home/<username>: Success` syslog message to [known-issues](docs/known-issues.md) documentation.
* Swapped `pip` for `uv` in `.devcontainer/dev`, `.devcontainer/prod`, and `setup-remote-vm.sh` script for more performant Python package management.
* Centralized `set -eux` in the Dockerfile `SHELL [...]` directive and removed per-command usage.
* Refactored `setup-remote-vm.sh` script to run as `root` and `ubuntu` user, with the latter running user-level tools in a virtual environment.
* Added `modernize` linter to `golangci-lint` configuration.
* Fixed `modernize` linter warnings in multiple golang projects.
* Added missing `${CI_DEPENDENCY_PROXY_DIRECT_GROUP_IMAGE_PREFIX}` variable to GitLab CI configuration for PostgreSQL image in `go-knfsd-fsidd 4/5` job.
* Packer: Updated minimum required IAM permissions for Packer build process in [README.md](/image/README.md#iam-permissions) documentation.
* Packer: Removed redundant `apt-get install` call for `make` and `gcc` in `20_post_build.sh` script.
* Packer: Added `retry` and `retry-delay` to all `curl` commands in `10_build.sh` and `20_post_build.sh` scripts.
* Packer: Wrapped all `git clone` commands in `10_build.sh` and `20_post_build.sh` with a `git_clone` function to add retry logic.
* Packer: Updated to `mdadm` v4.6.
* Packer: Updated to `rust` v1.94.1.
* Packer: Updated to `amazon-efs-utils` v3.1.0.
* Refactored `.devcontainer/dev/Dockerfile` to improve caching of Docker build layers and BuildKit cache mount performance.
* Updated to Packer v1.15.1.
* Updated to Terraform `aws` provider v6.42.0.
* Updated to Golang v1.26.2.
* Updated to Python v3.14.4.
* Minor Golang package updates.

## v1.1.0-alpha.23

> BREAKING CHANGES: `proxy-startup.sh` script is now installed into the AMI via Packer and only executed via EC2 user data on every boot.

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Packer: Updated to Linux kernel v6.19.7-knfsd.
* Packer: Add `perf` analysis tool (excluding `man` pages) to AMI to enable performance benchmarking and tuning.
* Packer: Updated to use EC2 Spot instance types for build process to lower build cost (up to ~87% reduction) and dramatically increase capacity availability. AWS does not charge for an EC2 Spot instance if [interrupted](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/billing-for-interrupted-spot-instances.html) in the first hour.
* Packer: `proxy-startup.sh` script is now installed into the AMI via Packer and only executed via EC2 user data on every boot.
* Packer: Updated to use `tmpfs` for `/mnt/build` and `/tmp` to improve build performance and remove the need for a persistent EBS `gp3` volume.
* Packer: Applied `intel_idle.max_cstate=1 processor.max_cstate=1` to GRUB boot parameters to limit CPU idle C-states to C1 to reduce interrupt/wake-up latency on supported `x86_64` EC2 [instance types](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/processor_state_control.html).
* Packer: Switch to using `cdn.kernel.org` endpoint for kernel source downloads to improve download reliability.
* `lazytime` mount option added to `fscache` mount in `proxy-startup.sh` script to only update times (atime, mtime, ctime) on the in-memory version of the file inode (reduces write load).
* Updated to Golang 1.26.1.
* Updated to PostgreSQL v18.3.
* Updated to Terraform `aws` provider v6.36.0.
* Improvements to CloudWatch `metrics` dashboard layout and widget styling.
* Updated KNFSD Monitoring Dashboard to `v11`.
* Packer: Pinned `amzn/amzn-drivers` ENA driver to `ena_linux_2.16.1`.
* Minor Golang package updates.

## v1.1.0-alpha.22

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Packer: Updated to Linux kernel v6.19.4-knfsd.
* Removed `0001-nfsd-never-defer-requests-during-idmap-lookup.patch` kernel patch that is now included in the v6.19.4 release.
* Updated to Terraform `aws` provider v6.34.0.
* Updated to Terraform `random` provider v3.8.1.
* Refactored `nfs.threads` metric to use `pgrep -c -x nfsd` instead of `prometheus/procfs/nfs` to count the currently running number of NFS threads in preparation for Linux v7.0 kernel release.
* Enhanced `proxy-startup.sh` with dynamic memory management: added `calculate_min_free_kbytes` function to set `vm.min_free_kbytes` based on total RAM, adjusted `VFS_CACHE_PRESSURE`, and refined kernel parameters for improved NFS performance.
* Fixed bug in CloudWatch `metrics` dashboard where the disk filesystem type was incorrectly set to `xfs` instead of `ext4`.
* Updated KNFSD Monitoring Dashboard to `v10`.
* Added explicit `EC2 Instance Connect Endpoint` (EICE) support to `run-fio-nfs.sh` and `remote.sh` scripts to support private subnets (no public IP).
* Added ability to provide custom EC2 keypair to `run-fio-nfs.sh` script.
* Enhanced `BATS` unit tests for `proxy-startup.sh` script to test all `sysctl` settings.
* Minor Golang package updates.

## v1.1.0-alpha.21

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Updated to Ubuntu 24.04.4 LTS.
* Packer: Updated to Linux kernel v6.19.3-knfsd.
* Updated to Golang 1.26.0.
* Updated to PostgreSQL v18.2.
* Updated to Packer v1.15.0.
* Updated to `nfs-utils` v2.8.5.
* Updated to Terraform AWS provider v6.33.0.
* Switched FS-Cache filesystem from `EXT4` to `XFS` with tuned `mkfs`/`mount` options, added block-device tuning (`nomerges`, `read_ahead_kb`) and VM sysctls (`min_free_kbytes`, `compaction_proactiveness`, `dirty_ratio`, `swappiness`) to reduce deadlock risk and improve NVMe cache performance.
* Added KNFSD Test Plans for:
  * [Directory Listing](docs/tests/directory-listing.md)
  * [Recovery Proxy](docs/tests/recovery-proxy.md)
  * [Recovery Source](docs/tests/recovery-source.md)
  * [Recovery Load Balancer](docs/tests/recovery-load-balancer.md)
* Added `gosecure` to `Makefile` to run Go vulnerability scanning on all Go projects.
* Added `gosecure` GitLab CI jobs for `smoke-tests` and `testing/examples` Golang projects.
* Switched to using `golang` Docker image for Go vulnerability scanning in GitLab CI `gosec` jobs.
* Added `wait_for_capacity_timeout = "0"` to `aws_autoscaling_group.knfsd_asg` in `terraform-module-knfsd` to avoid rare ASG waiter false-negative failures.
* Added `REMOVE_EMPTY` function to CloudWatch `SEARCH` expressions for FS-Cache Read & Write Throughput metrics in dashboard to remove any `NaN` values.
* Fixed bug in metric math expressions for `Cluster Network Bandwidth` and `Proxy Network Bandwidth` widgets in CW dashboard.
* Added `diskio_read_time` and `diskio_write_time` metrics to `amazon-cloudwatch-agent.json` file.
* Added `I/O Requests: Waiting on Disk` widget to CloudWatch dashboard.
* Added `Output NFS Filer` to CloudWatch metrics dashboard to filter by Output NFS Filer(s), which might be different from the Source NFS Filer(s).
* Removed `period` parameter from high-resolution CW dashboard widgets to use the automatically aggregated period.
* Added `id` parameter to all metric math expressions in CW dashboard to ensure deterministic label ordering within each widget. Label ordering is ignored when `stacked` is `true` in a CW metric widget.
* Improved some of the CW dashboard text descriptions.
* Aligned CW dashboard widget colours to be consistent.
* Updated KNFSD Monitoring Dashboard to `v9`.
* Added `fio` and `stress-ng` packages to KNFSD AMI to enable NVMe/NFS/FS-Cache performance testing.
* Added `run-benchmark-nvme.sh` script to `.devcontainer/dev` for NVMe `instance-store` performance testing using FIO.
* Added `run-fio-nfs.sh` script to `.devcontainer/dev` for NFS/FS-Cache performance testing using FIO.
* Added `create-source-files.fio` file to `.devcontainer/dev/fio` for creating source files for NFS/FS-Cache performance testing using FIO.
* Added `nfs-fscache-deadlock.fio` file to `.devcontainer/dev/fio` for NFS/FS-Cache performance testing using FIO.
* Exposed `FSX_STORAGE_CAPACITY`, `FSX_THROUGHPUT_CAPACITY`, and `NUM_NFS_THREADS` Terraform variables to the `fsx-zfs` example.
* Packer: Updated [README](image/README.md) to clarify `var.SUBNET` is required only if using a non-default VPC.
* Packer: compile/install `mdadm` from source into AMI to remove `md: async del_gendisk mode will be removed in future, please upgrade to mdadm-4.5+` warning from `dmesg` output.
* Minor Golang package updates.

## v1.1.0-alpha.20

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Packer: Switched to use compiled from source, Linux kernel v6.19.0-rc7 and NFS kernel patches for KNFSD AMI.
* Introduced `fscache` Open Telemetry `receiver/component` to track the performance of the FS-Cache and Netfslib. See [FS-Cache Metrics](deployment/metrics/README.md#fs-cache-metrics) and [Netfs Metrics](deployment/metrics/README.md#netfs-metrics) for more information.
* Added 37 x `NetfsLib` and 24 x `FS-Cache` metrics to CloudWatch `metrics` dashboard.
* Added `REMOVE_EMPTY` function to CloudWatch `SEARCH` expressions in metrics dashboard to remove any `NaN` values.
* Added `Total BW` widget to CloudWatch metrics dashboard to track the total bandwidth used by clients to all proxies in the ASG.
* Added `Cluster Network Bandwidth` widget to CloudWatch metrics dashboard to track the network throughput of the entire cluster.
* Consolidated the NFS v3 and NFS v4 CloudWatch metrics widgets.
* Updated KNFSD Monitoring Dashboard to `v8`.
* Fixed some dead/404 links in the documentation.
* Packer: Updated `hashicorp/packer-plugin-amazon` to v1.8.0.
* Packer: Created `/etc/amazon/ssm` directory in build process to silence SSM agent log noise.
* Updated to Golang 1.25.6.
* Updated to Terraform DNS provider v3.5.0.
* Updated to Terraform AWS provider v6.30.0.
* Minor Golang package updates.

## v1.1.0-alpha.19

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Downgraded default database instance type from `db.t4g.small` to `db.t4g.micro`, reducing RDS database infrastructure cost by 50%.
* CloudWatch metrics dashboard improvements, improved burst CPU credit balance/usage/unlimited-mode tracking on RDS DB instance.
* CloudWatch metrics: remove `swap_percent` (unused), replace `mem_used_percent` with `mem_available_percent` (memory available for use) in `knfsd/ec2` namespace.
* Added `knfsd/nfs_clients` metric to count the number of unique NFS client IP addresses connected to a KNFSD proxy.
* Added new CW widget to track the number of EC2 instances (NFS clients) mounted to each KNFSD proxy.
* Introduced `nfsd` Open Telemetry `receiver/component` to track the performance of the KNFSD server. See [KNFSD Server Metrics](deployment/metrics/README.md#nfs-server-metrics) and [Kernel NFS Server Statistics](https://www.kernel.org/doc/html/latest/filesystems/nfs/knfsd-stats.html) for more information.
* Added `knfsd/nfs_packets_arrived`, `knfsd/nfs_packets_deferred`, `knfsd/nfs_sockets_enqueued`, `knfsd/nfs_threads`, `knfsd/nfs_threads_timedout`, and `knfsd/nfs_threads_woken` metrics.
* Added `fscdevice` dimension to `diskio` metrics in `knfsd/ec2` namespace in `amazon-cloudwatch-agent.json` file.
* Refactored CloudWatch custom `metrics` dashboard to use `fscdevice` dimension for certain `diskio` metric filtering.
* Increased collection interval of `diskio` metrics from 30s to 10s in `knfsd/ec2` namespace in `amazon-cloudwatch-agent.json` file.
* Updated KNFSD Monitoring Dashboard to `v7`.
* Fixed Windows host machine being able to deploy the RDS DB in the `database` module.
* Updated `prerequisites` documentation to declare `bash` and `jq` as being required which are already vendored in the `.devcontainer/dev` and `.devcontainer/prod` environments.
* Fixed issue where the AWS IAM role `AutoScalingServiceLinkedRole` needs to be created once in a brand new AWS account when using `TRAFFIC_MODE="loadbalancer"` in the `terraform-module-knfsd` module.
* Updated to Terraform AWS provider v6.28.0.
* Added `provider_meta` to all Terraform AWS provider blocks with `USER_AGENT` string.
* Minor Golang package updates.

## v1.1.0-alpha.18

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Added `SVC_RPC_PER_CONNECTION_LIMIT` variable to `terraform-module-knfsd` module. This allows users to specify the number of RPC requests that the server will process in parallel from a single connection. Default: `0` (no limit).
* Re-introduced `EXPORT_CIDR` variable to `terraform-module-knfsd` module. This allows users to specify custom CIDR blocks to use in the NFSD `/etc/exports.d/knfsd.exports` file. By default, the primary VPC CIDR block is used. For secondary VPC CIDRs, users must explicitly provide the full list via: `EXPORT_CIDR`.
* Packer: Removed `multipath-tools` package from AMI to reduce syslog noise from `multipathd` service, which is irrelevant to KNFSD instances on AWS.
* Packer: Added log rotation with `size` limit for `/var/log/*.log`, `/var/log/syslog`, and `/var/log/journal/` files. See [rsyslog](image/resources/etc/logrotate.d/rsyslog) and [99-size-limit.conf](image/resources/etc/systemd/journald.conf.d/99-size-limit.conf) for exact configuration.
* Updated KNFSD Monitoring Dashboard to `v6`. Lots of minor improvements.
* Updated to Golang 1.25.5.
* Updated to Terraform AWS provider v6.26.0.
* Minor Golang package updates.
* Updated to Python v3.14.2.
* Updated to Psycopg3 v3.3.1.

## v1.1.0-alpha.17

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

> BREAKING CHANGES: `var.EXPORT_CIDR` has been renamed to `var.VPC_CIDR` and is now `type = list(string)` with `default = []`. Users who currently set `EXPORT_CIDR = "172.31.0.0/16"` must update to `VPC_CIDR = ["172.31.0.0/16"]`. When empty, the primary VPC CIDR block is used for security group rules and NFS exports. For secondary VPC CIDRs, you must explicitly provide the full list. For example: `VPC_CIDR = ["172.31.0.0/16", "172.32.0.0/16"]`.

> BREAKING CHANGES: `var.ASG_EGRESS_CIDR_BLOCK` has been renamed to `var.ASG_EGRESS_CIDR`.

* Major overhaul of CIDR handling across all modules. Multiple CIDR blocks can now be specified for security group rules and NFS exports. By default, the primary VPC CIDR block is used. For secondary VPC CIDRs, users must explicitly provide the full list via: `VPC_CIDR`.
* Terraform `database` module now supports cross-VPC access with VPC peering.
* Pinned Linux HWE kernel to v6.14.0-36-generic.
* Substantial improvements to CloudWatch `metrics` dashboard. KNFSD Monitoring Dashboard updated to `v5`.
* Reduced default value for `NUM_NFS_THREADS` from `256` to `128` in `terraform-module-knfsd` module.
* Added the `otelcol.Factories.Telemetry` field which is now required by OpenTelemetry v0.140.0 in `knfsd-metrics-agent`.
* Removed unused VS Code extensions from `.devcontainer/dev`.
* Added `uv` to `.devcontainer/dev` for Python package management.
* Updated to Terraform AWS provider v6.23.0.
* Minor Golang package updates.

## v1.1.0-alpha.16

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Added `TCP_SLOT_TABLE_ENTRIES` and `TCP_MAX_SLOT_TABLE_ENTRIES` variables to `terraform-module-knfsd` module. These kernel tunables control the number of simultaneous RPC requests, per TCP connection, the proxy can send to the source filer. Default: `128`.
* Reduced default value for `NUM_NFS_THREADS` from `512` to `256` in `terraform-module-knfsd` module.
* Reduced default value for `VFS_CACHE_PRESSURE` from `100` to `1` in `terraform-module-knfsd` module.
* Added `PROXY_AMI_OWNERS` variable to `terraform-module-knfsd` module. This allows you to specify the AMI owners to limit the AMI search. Default: `["self"]`. If your AMI is created by Packer in a different AWS account, you can specify the AWS account ID here.
* Removed `owners = ["self"]` from `./examples` to simplify the examples.
* Converted incorrect Terraform data type (string -> number) for `VFS_CACHE_PRESSURE` and `NCONNECT` variables in `terraform-module-knfsd` module.
* Added Terraform validation checks to ensure `VFS_CACHE_PRESSURE` is between `0` and `100`, and `NCONNECT` is between `1` and `16`.
* Refactored how metadata (IMDSv2) is retrieved during instance startup, improving reliability and reducing startup time.
* Ensure all services are stopped silently before configuration, preventing any potential conflicts with the startup process.
* Fixed a bug where the RAID array was not being reassembled correctly during KNFSD instance reboot.
* Refactored `proxy-startup.sh` to improve error logging and function stack tracing during KNFSD instance startup failures.
* Added total execution time to `proxy-startup.sh` script for benchmarking/debugging purposes.
* Downgraded default database instance type from `db.t4g.medium` to `db.t4g.small`.
* Packer: run `cloud-init clean --logs --seed` during image build to ensure a clean state/logs in the AMI.
* Ensure consistent shebang across all shell scripts in the project.
* Updated to Python v3.14.0.
* Updated to PostgreSQL v18.1.
* Updated to Terraform AWS provider v6.22.0.
* Minor Golang package updates.
* Removed pinned OpenShift API Golang dependency in `knfsd-metrics-agent`.
* Added parallelism (where feasible) to all Golang unit tests, reduced GitLab CI Golang jobs runtime by >50%.

## v1.1.0-alpha.15

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Added ARM support. Graviton EC2 instances can now be used to build & run KNFSD-File-Cache.
* Packer: Enabled parallel builds for both AMD64 and ARM64 architectures.
* Packer: `ARCH` variable can be set to `["amd64"]`, `["arm64"]`, or `["amd64", "arm64"]` to build only the specified architectures. Default: `["amd64", "arm64"]`.
* Added `PROXY_AMI` checks in `terraform-module-knfsd` root module to validate the proxy AMI exists and uses the correct `amd64/arm64` architecture for the given instance type.
* Added `PROXY_AMI` checks in `./examples` to validate the proxy AMI exists and uses the correct `amd64/arm64` architecture for the instance type.
* Fail earlier if the `db_setup.py` Lambda function fails to execute successfully.
* Updated to Terraform AWS provider v6.20.0.
* Updated to `nfs-utils` v2.8.4.
* Minor Golang package updates.

## v1.1.0-alpha.14

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Packer: Refactored pre-build & post-build scripts to be Packer variables, similar to the Terraform module.
* Packer: Added `CUSTOM_PRE_BUILD_SCRIPT` and `CUSTOM_POST_BUILD_SCRIPT` variables to allow for custom build steps.
* Packer: Added `IAM_INSTANCE_PROFILE` variable to allow for custom IAM instance role to be used during image build.
* Updated to Golang 1.25.4.
* Minor Golang package updates.
* Fixed Open-Telemetry upstream golang dependency package issue in `knfsd-metrics-agent`.
* Added `proxy.golang.org` to GitLab CI jobs.
* Enhanced `Makefile` to support `pre-commit autoupdate`.
* Added AWS SSM agent to `remote-ssh` and `remote-docker` install scripts.

## v1.1.0-alpha.13

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Packer: Fixed bug in `20_post_build.sh` script where `/etc/machine-id` file must exist for systemd dependencies at boot.
* Packer: Added `proxy.golang.org` to `GOPROXY` environment variable to handle situations where a VCS based git repo is unavailable, causing the image build process to fail (continue to use `direct` only in the devcontainer/build environment to ensure golang dependencies/versions are working correctly).
* Packer: Updated `hashicorp/packer-plugin-amazon` to v1.6.0.
* Updated to Terraform AWS provider v6.19.0.
* Minor Golang package updates.
* Improved documentation in various places, including [nfs-client-setup.md](docs/nfs-client-setup.md).

## v1.1.0-alpha.12 (broken)

* Updated `metrics` documentation.
* Added `docs/nfs-client-setup.md` documentation to explain recommended client setup for KNFSD.
* Updated `THIRD-PARTY-LICENSES` file.
* Improved `update-version.sh` script to update all version strings in the repository.
* Minor Golang package updates.
* Updated to KICS v2.1.15.
* Updated to Python v3.13.9.
* Removed unused terminals in `.devcontainer` for improved performance.
* Silenced false-positive in `semgrep` check.

## v1.1.0-alpha.11 (broken)

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Pinned Linux HWE kernel to v6.14.0-29-generic due to [bug](https://bugs.launchpad.net/ubuntu/+source/linux-hwe-6.14/+bug/2125678).
* Updated default `INSTANCE_TYPE` to `i3en.6xlarge` in `terraform-module-knfsd` module and all examples.
* Updated default `INSTANCE_TYPE` to `i3en.12xlarge` in `fanout` examples.
* Updated to Terraform AWS provider v6.18.0.
* Updated to Golang 1.25.3.
* Minor Golang package updates.
* Added missing NFSv4 file operations widgets to CloudWatch `metrics` dashboard.
* Added a tutorial: "Deploy a kernel space NFS caching proxy on AWS". See [README](tutorial/README.md) for more information.
* Cleaned up log messaging in `proxy-startup.sh` script for custom pre/post startup scripts.
* Fixed bug in custom pre/post `proxy-startup.sh` script handling where double-quotations were not being handled correctly inside inline bash commands or referenced shell script files.
* Packer: Added `missingok` and `notifempty` to `knfsd-logrotate.conf`.
* Packer: Purge `/etc/machine-id` file to ensure unique machine-id is generated during first-boot.
* Added network throughput metric to CloudWatch `metrics` dashboard.

## v1.1.0-alpha.10

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Added Terraform `metrics` module to deploy a custom Amazon CloudWatch dashboard. See [README](deployment/metrics/README.md), [metrics](deployment/docs/metrics.md), and [client-metrics](docs/client-metrics.md) documentation.
* Flattened and minimised the dimensions of all custom metrics.
* Fixed bug in Golang `knfsd-metrics-agent` preventing `nfsiostat` and `mount` metrics from being published.
* Refactored Open-Telemetry dimension configuration across `common.yaml`, `proxy.yaml`, and `client.yaml`.
* Enhanced `proxy-startup.sh` to handle different Nitro block device names depending on NVMe, EBS, RAID0 configuration at initial KNFSD instance startup only.
* Updated to Terraform AWS provider v6.15.0.
* Updated to Golang 1.25.2.
* Updated KICS to 2.1.14 (and silenced false-positive).
* Minor Golang package updates.
* Updated to Python 3.13.8 (awaiting Python 3.14 support in AWS Lambda runtime).
* Fix initial error with `proxy-startup.sh` startup order with KNFSD metrics agent and `nfsd`.
* Tweak `golangci-lint` yaml config to ignore `misspell` false-positive on `testcert.go` in CI pipeline.
* Fixed `semgrep` bug via updating to 1.137.0.
* Updated Amazon EBS `gp3` settings in `terraform-module-knfsd` that increase the maximum size and provisioned performance as per [announcement](https://aws.amazon.com/about-aws/whats-new/2025/09/amazon-ebs-size-provisioned-performance-gp3-volumes/).
* Reduce TF variable: `ROOT_DISK_SIZE` from 100GB to 20GB for KNFSD instance boot volume (5x cost saving on EBS `gp3` used).
* Added **WARNING** to `fanout` documentation: *Ensure the **fanout** EC2 `INSTANCE_TYPE` is at least 2x-8x more powerful than the **cluster** EC2 `INSTANCE_TYPE` (use a larger size).*

## v1.1.0-alpha.9

* Updated to Terraform AWS provider v6.13.0.
* Updated to Packer v1.14.2.
* Updated to KICS v2.1.13.
* Updated to Golang 1.25.1.
* Minor Golang package updates.
* Fixed issue where the CloudWatch log group for the `static-ip` Lambda function can be re-created by an EC2 instance terminating slowly after its ASG is deleted during a Terraform destroy.
* Refactored the handling of the secondary `static-ip` ENI when an EC2 instance is terminated for any reason other than a scale-in event.
* Exposed Terraform `KNFSD_NODES` and `INSTANCE_TYPE` variables to the `fsx-zfs` example.
* Refactored `proxy-startup.sh` to be stateless.
* Added support for KNFSD machine reboot, `/var/cache/fscache` data persists between reboots (shutdown not supported).
* KNFSD specific NFS exports are now stored in `/etc/exports.d/knfsd.exports`, leaving default `/etc/exports` untouched.
* Ensure `resources` directory is writable by all users in `../deployment/database/resources/docker-build.sh`.

## v1.1.0-alpha.8

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Packer: due to an emerging bug in `hashicorp/packer-plugin-amazon` v1.4.0, pin the plugin version via pessimistic constraint operator to v1.3.10.
* Revert Docker Lambda DB function to exclusively use amd64 (x86_64) architecture to work across all platforms by default.
* Refactored CloudWatch JSON configuration file for CW log storage and CW appended dimensions.
* Minor Golang package updates.
* Updated Terraform provider.
* Added Packer plugin caching to dev/prod .devcontainer environment.
* Added ability to use specific AMI-id when provisioning a remote-ssh EC2 instance.
* Added `KNFSD_REMOTE_SSH_IAM_PROFILE_NAME` support to `dev` .devcontainer for remote-ssh into EC2.
* Added helper script to generate AWS region names for metrics dashboard.json file.
* Exclude pretty-format-json formatting of `dashboard.json` file from pre-commit hook.
* Added `make image` & `make image-debug` support to build Packer AMI via Makefile alias.
* Exposed `FSID_MODE` as a variable to the `fsx-zfs` example.
* Removed unused OTEL packages from `knfsd-metrics-agent` Golang module.

## v1.1.0-alpha.7

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Updated to PostgreSQL v17.6.
* Minor Golang package updates.
* Updated to Golang v1.25.0.
* Updated to Python v3.13.7.
* Updated Terraform providers.
* Add Docker "buildx" CLI argument for cross-platform builds.
* Enhance Docker image inspect command to support multi-platform images.

## v1.1.0-alpha.6

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Added support for Linux v6.14 kernel, including NFS server, client and `FS-Cache` improvements.
* Minor Golang package updates.
* Packer: pinned version of `rust` and `efs-utils`.
* Packer: increased EBS root volume size from 8 GB to 10 GB.
* Packer: decreased EBS temp volume size from 50 GB to 20 GB.
* Packer: fixed bug preventing the `go` build cache from being global within the build script.
* Packer: updated Packer min version to v1.13.1.
* Packer: updated `amazon-ebs` plugin min version to v1.3.9.

## v1.1.0-alpha.5

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Minor Golang package updates.
* Minor Terraform provider version updates.
* Refactored `knfsd-fsidd` to always use a new `iam-auth` TOKEN for a new database connection.
* Added debug logging to `knfsd-fsidd` to validate the local database cache is working as expected.
* Added initial metrics changes to OTEL `*.yaml` config files.

## v1.1.0-alpha.4

> BREAKING CHANGES: `var.ASSOCIATE_PUBLIC_IP_ADDRESS` is now `null` by default in `image.pkrvars.hcl`. See [Packer: Security Group Usage Scenarios](image/README.md#security-group-usage-scenarios) for more information.

* Fixed a typo in OTEL `common.yaml` config file.
* Fixed a bug when `var.ASSUME_ROLE_ARN` is `null` (default) during deployment.
* Packer: added `var.SECURITY_GROUP_ID` in `image.pkrvars.hcl` to use an existing security group during image build. Default: `""`.
* Packer: added `var.SECURITY_GROUP_IDS` in `image.pkrvars.hcl` to use multiple existing security groups during image build. Default: `[]`.
* Packer: added `var.TEMPORARY_SECURITY_GROUP_SOURCE_CIDRS` in `image.pkrvars.hcl` to allow access from a list of CIDR blocks during image build. Default: `[]`.
* Packer: added `var.TEMPORARY_SECURITY_GROUP_SOURCE_PUBLIC_IP` in `image.pkrvars.hcl` to allow access from the public IP address of the machine running Packer during image build. Default: `true`.

## v1.1.0-alpha.3

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Added `var.ASSUME_ROLE_ARN` to allow for role assumption in CI/CD pipelines for `local-exec` provisioners.
* Enabled Auto-Scaling (scale-up only) for the `loadbalancer` module.
* Enabled OpenTelemetry metrics for the KNFSD proxy.
* Amazon CloudWatch metrics & logs are grouped by `knfsd/` prefix.
* Added `fsx-zfs-fanout-dns-rr` example to demonstrate how to use the `terraform-module-knfsd` module with an Amazon FSx for OpenZFS file system in a `fanout/dns-round-robin` architecture.
* Renamed `fsx-zfs-fanout` example to `fsx-zfs-fanout-loadbalancer`.
* Extended `delete` timeout during Terraform `destroy` for `AutoScalingGroup` from 10m to 20m.
* Fixed a bug in Eventbridge rules for `dns_round_robin` module where the rules were not being created with unique names per cluster, causing a conflict in the `fanout` architecture.
* Fixed a bug in `dns_round_robin` module where secondary ENI TAG `knfsd-file-cache:instance-id` could be misrepresented in an `ec2.describe_network_interfaces` filter.
* Split the default FQDN for `dns_round_robin` module into two parts for Amazon Route 53: `name=knfsd` and `zone=<PROXY_BASENAME>.aws.internal.`, ensuring unique zone names per cluster deployment.
* Refactored `DNS_NAME` to allow users to specify their own private FQDN for the KNFSD proxy cluster.
  * If `var.DNS_NAME` is `""` (default), a private DNS zone (`aws.internal.`) is created, and A or CNAME record(s) (`knfsd.<PROXY_BASENAME>.aws.internal.`) are created via the Amazon R53 service.
  * If `var.DNS_NAME` is a FQDN, including trailing dot `.` (R53 private zone already exists), then A or CNAME record(s) (`<CUSTOM_NAME>.<CUSTOM_DOMAIN>.`) are created in the existing Amazon R53 zone.
* Removed `var.PRIVATE_HOSTED_ZONE` from all modules.
* Added 60m timeout to `status.tf` check to prevent infinite loops during deployment.
* Minor Golang package updates.
* Fixed `proxy-startup.sh` conflict between `fsidd` and `knfsd-fsidd` service, causing RDS database to not be used, when `FSID_MODE="external"`.
* Enhanced the `fsx-zfs` example to deploy additional ZFS volumes and demonstrate the use of `EXPORT_HOST_AUTO_DETECT` feature (`showmount`), together with NFS v3 for performance.
* Increased GitLab CI job `Trivy` timeout to 10 minutes.
* Added explicit support for `--region` in the `aws` calls via IMDS retrieval on the EC2 instance within the `proxy-startup.sh` script.
* Added `fsx-netapp` example to demonstrate how to use the `terraform-module-knfsd` module with an Amazon FSx for NetApp ONTAP file system in a `dns-round-robin` architecture. This example uses the NetApp REST API to automatically discover, filter and configure exports.
* Added documentation for [GitLab-CI](docs/gitlab-ci.md) and [Pre-Commit](docs/pre-commit.md).
* Improved `proxy-startup.sh` 'cold' startup time from 281 seconds to 38 seconds (i3en.3xl), ~86% quicker.
* Added timestamp to each stage of the Packer image build process.
* Consolidated log/metrics group names for CloudWatch & OpenTelemetry.
* Added Terraform AWS provider configuration to all `./examples` modules.
* Added new `./examples` to be cached in GitLab-CI pipeline.
* Reduced default instance type from `i3en.6xlarge` to `i3en.3xlarge` in the `terraform-module-knfsd` module.
* Updated `hashicorp/aws` provider to v6.0.0. Ensure you `terraform init -upgrade` to ensure you are using the correct version of the provider.
* Added timestamp to each section of the `proxy-startup.sh` script to measure startup timings.
* Added `fsx-zfs` example to demonstrate how to use the `terraform-module-knfsd` module with an Amazon FSx for OpenZFS file system in a `dns-round-robin` architecture.
* Added `fsx-zfs-fanout` example to demonstrate how to use the `terraform-module-knfsd` module with an Amazon FSx for OpenZFS file system in a `fanout/load-balancer` architecture.
* Added note to the `efs` example that Amazon EFS does not support being re-exported more than once, so does not support the `fanout` feature.
* Removal of `var.REGION` from all modules. AWS Region is now derived from the provided `var.SUBNET`. Can be overridden with AWS provider configuration in the root module.
* Remove AWS provider configuration from Terraform root module (no longer a legacy module).
* Removal of VPC Endpoints from Terraform module. See [VPC Endpoints](deployment/docs/vpc-endpoints.md) for detailed setup instructions if required.
* Renamed `gitlab-ci.yml` to `gitlab-ci-aws.yml` to avoid conflicting with a customer's `gitlab-ci.yml` file.
* Minor software version updates.
* Updated `THIRD-PARTY-LICENSES` file for reference.
* Updated to Packer v1.13.1.
* `var.EXPORT_CIDR` now defaults to `""` (VPC CIDR of `var.SUBNET` is used if not specified).
* `var.ENABLE_STATUS_CHECK` added to enable the status check that waits for all EC2 instances to be KNFSD status: `ready` during Terraform deployment. Must be `true` for `fanout` deployments.
* `var.FSID_DATABASE_CONFIG` is now a JSON `map` of key/value pairs that can be used to override the default FSID database configuration (used in `fanout` deployments and when you want to reuse the database from a previous deployment).
* `output.database_config` has been added to the `terraform-module-knfsd` module. It is a `map` of key/value pairs that can be used to override the default FSID database configuration (used in `fanout` deployments).
* `output.database_iam_policy` has been added to the `terraform-module-knfsd` module. It is an ARN `string` that can be used to attach the IAM policy to the KNFSD proxy instances.
* `output.cluster_ready` has been added to the `terraform-module-knfsd` module. It is a `boolean` that can be used with `var.ENABLE_STATUS_CHECK` to wait for the KNFSD cluster and EC2 instances to be ready before deploying downstream resources.
* `output.autoscaling_group_security_group_id` has been added to the `terraform-module-knfsd` module.
* `null_resource.trigger_lambda_after_rds` now explicitly targets the AWS `--region` of the RDS instance.
* Fanout documentation updated to reflect the new settings.
* Prerequisites documentation updated to reflect removal of VPC Endpoints.
* Fixed bug where Network Load Balancer target groups were not being created when `var.TRAFFIC_MODE` was set to `loadbalancer`.
* Added additional IAM policy for EC2 instance "status" tagging.
* Fixed bug where `var.NFS_PORTS` was not being passed to the `loadbalancer` module from the `terraform-module-knfsd` module.
* Added `knfsd-file-cache:status` tag to deployed EC2 instances for real-time status checking during deployment of a KNFSD cluster.
* Updated `validations.tf` to account for `var.FSID_DATABASE_CONFIG` being a JSON `map` of key/value pairs.
* Secondary ENIs created for `dns_round_robin` deployments now have a `knfsd-file-cache:version` tag.
* `proxy-startup.sh` now updates the `knfsd-file-cache:status` tag to track the status of the proxy after it has started. `ready` is set after the proxy has successfully completed the startup process and `error: failed to start proxy` is set if the proxy fails to start.
* `proxy-startup.sh` only attempts to mount Amazon EFS source server once, instead of three attempts (EFS helper utility already hard-wired to attempt to mount the EFS source server three times).
* `check-startup.md` documentation updated to reflect the new `knfsd-file-cache:status` tagging system for real-time status viewing in the AWS Console during deployment.
* `known-issues.md` documentation added entry to explain why `showmount` fails with `clnt_create: RPC: Program not registered` when using `EXPORT_HOST_AUTO_DETECT`.
* Packer: added `var.ASSOCIATE_PUBLIC_IP_ADDRESS` in `image.pkrvars.hcl` to force public IP address association during image build. Default: `true`.
* Packer: added new CloudWatch EBS metrics to `amazon-cloudwatch-agent.json` to monitor EBS volume performance.

## v1.1.0-alpha.2

* Initial alpha release of KNFSD-File-Cache
