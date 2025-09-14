# KNFSD-File-Cache

## v1.1.0-alpha.9

* Updated to Terraform AWS provider v6.13.0.
* Updated to Packer v1.14.2.
* Updated to KICS v2.1.13.
* Updated to Golang 1.25.1.
* Minor Golang package updates.
* Fixed issue where the CloudWatch log group for the `static-ip` Lambda function can be re-created by an EC2 instance terminating slowly after its ASG is deleted during a Terraform destroy.
* Re-factored the handling of the secondary `static-ip` ENI when an EC2 instance is terminated for any reason other than a scale-in event.
* Exposed Terraform `KNFSD_NODES` and `INSTANCE_TYPE` variables to the `fsx-zfs` example.
* Re-factored `proxy-startup.sh` to be stateless.
* Added support for KNFSD machine reboot, `/var/cache/fscache` data persists between reboots.
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
* Re-factored `knfsd-fsidd` to always use a new `iam-auth` TOKEN for a new database connection.
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
* Re-factored `DNS_NAME` to allow users to specify their own private FQDN for the KNFSD proxy cluster.
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
