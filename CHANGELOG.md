# KNFSD-File-Cache

## v1.1.0-alpha.21

> BREAKING CHANGES: Ensure AMI is rebuilt by Packer.

* Updated to Ubuntu 24.04.4 LTS.
* Updated to Linux kernel v6.19.3-knfsd.
* Updated to Golang 1.26.0.
* Updated to PostgreSQL v18.2.
* Updated to Packer v1.15.0.
* Updated to `nfs-utils` v2.8.5.
* Updated to Terraform AWS provider v6.32.0.
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
* Added `fio` and `stress-ng` packages to KNFSD AMI to enable NVMe performance testing.
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

* Switched to use compiled from source, Linux kernel v6.19.0-rc7 and NFS kernel patches for KNFSD AMI.
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
