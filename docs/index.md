# KNFSD File Cache

* [Prerequisites](../deployment/docs/prerequisites.md)
* [Security Considerations](security-considerations.md)
* [IAM Permissions](iam.md)

## Step 1: Build (Packer)

* [README](../image/README.md)

## Step 2: Deploy (Terraform)

* [VPC Endpoints](../deployment/docs/vpc-endpoints.md)
* [Main Module](../deployment/README.md)
* [Database](../deployment/database/README.md)
* [DNS Round Robin](../deployment/terraform-module-knfsd/modules/dns_round_robin/README.md)
* [Load Balancer](../deployment/terraform-module-knfsd/modules/loadbalancer/README.md)
* [Metrics Dashboard](../deployment/metrics/README.md)

## Image Reference

* [Smoke Tests](../image/smoke-tests/README.md)

## Deployment Reference

* [KNFSD HTTP Agent](../image/resources/knfsd-agent/README.md)
* [NFS Auto Re-Export](../deployment/docs/auto-re-export.md)
* [Autoscaling](../deployment/docs/autoscaling.md)
* [Fanout](../deployment/docs/fanout.md)
* [Filter-Patterns](../deployment/docs/filter-patterns.md)
* [Security Groups](../deployment/docs/security-groups.md)
* [FSIDs](../deployment/docs/fsids.md)
* [Metrics](../deployment/docs/metrics.md)
* [KNFSD Metrics Agent (OpenTelemetry)](../image/resources/knfsd-metrics-agent/README.md)
  * [Connections](../image/resources/knfsd-metrics-agent/internal/connections/documentation.md)
  * [Exports](../image/resources/knfsd-metrics-agent/internal/exports/documentation.md)
  * [FSCache](../image/resources/knfsd-metrics-agent/internal/fscache/documentation.md)
  * [Mounts](../image/resources/knfsd-metrics-agent/internal/mounts/documentation.md)
  * [NFSD](../image/resources/knfsd-metrics-agent/internal/nfsd/documentation.md)
  * [Oldest File](../image/resources/knfsd-metrics-agent/internal/oldestfile/documentation.md)
  * [Slab](../image/resources/knfsd-metrics-agent/internal/slab/documentation.md)
* [NetApp](../deployment/docs/netapp.md)
* [NetApp ShowMount Tool](../image/resources/netapp-exports/README.md)
* [Ports](../deployment/docs/ports.md)
* [Traffic Distribution](../deployment/docs/traffic-distribution.md)

## User Reference

* [CHANGELOG](../CHANGELOG.md)
* [Check Proxy Startup](check-startup.md)
* [NFS Client Setup](nfs-client-setup.md)
* [Client Metrics](client-metrics.md)
* [FAQ](faq.md)
* [Known Issues](known-issues.md)

## Tutorial

* [Deploy a kernel space NFS caching proxy in AWS](../tutorial/README.md)

## Examples

* [Overview](../examples/README.md)
* [Basic NFS Example](../examples/basic/README.md)
* [FSx for NetApp ONTAP](../examples/fsx-netapp/README.md)
* [FSx for OpenZFS](../examples/fsx-zfs/README.md)
* [FSx for OpenZFS Fanout (DNS Round Robin)](../examples/fsx-zfs-fanout-dns-rr/README.md)
* [FSx for OpenZFS Fanout (Network Load Balancer)](../examples/fsx-zfs-fanout-loadbalancer/README.md)
* [Weka NFS Gateway](../examples/weka/README.md)

## Test Plans

* [README](tests/README.md)
* [Directory Listing](tests/directory-listing.md)
* [Recovery Source](tests/recovery-source.md)
* [Recovery Proxy](tests/recovery-proxy.md)
* [Recovery Network Load Balancer](tests/recovery-load-balancer.md)

## Developer Reference

* [Advanced/Developer](developer.md)
* [Pre-commit](pre-commit.md)
* [GitLab CI](gitlab-ci.md)

## Testing

* [Smoke Tests](../image/smoke-tests/README.md)
* [NFS Client](../image/smoke-tests/modules/nfs-client/README.md)
* [Source NFS Server](../image/smoke-tests/modules/source-nfs/README.md)

## Resources

See [Resources](../docs/resources.md) for AWS articles, official guidance, and upstream Linux NFS documentation.

## Project Reference

* [LICENSE](../LICENSE)
* [THIRD-PARTY-LICENSES](../THIRD-PARTY-LICENSES)
* [ACKNOWLEDGEMENTS](../ACKNOWLEDGEMENTS.md)
* [Code of Conduct](CODE_OF_CONDUCT.md)
* [Contributing](CONTRIBUTING.md)
* [Security](SECURITY.md)
