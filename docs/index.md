# KNFSD File Cache

* [Prerequisites](../deployment/docs/prerequisites.md)

## Step 1: Build (Packer)

* [README](../image/README.md)

## Step 2: Deploy (Terraform)

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
  * [Mounts](../image/resources/knfsd-metrics-agent/internal/mounts/documentation.md)
  * [Oldest File](../image/resources/knfsd-metrics-agent/internal/oldestfile/documentation.md)
  * [Slab](../image/resources/knfsd-metrics-agent/internal/slab/documentation.md)
* [NetApp](../deployment/docs/netapp.md)
* [NetApp ShowMount Tool](../image/resources/netapp-exports/README.md)
* [Ports](../deployment/docs/ports.md)
* [Traffic Distribution](../deployment/docs/traffic-distribution.md)

## User Reference

* [Check Proxy Startup](check-startup.md)
* [Client Metrics](client-metrics.md)
* [Culling](culling.md)
* [FAQ](faq.md)
* [Known Issues](known-issues.md)
* [Advanced/Developer](developer.md)
* [CHANGELOG](../CHANGELOG.md)

## Tutorial

* [Deploy a kernel space NFS caching proxy in AWS](../tutorial/README.md)

## Examples

* [Basic](../examples/basic/README.md)
* [Standard](../examples/standard/README.md)
* [Weka NFS Gateway](../examples/weka/README.md)

## Testing

* [Terratest](../testing/examples/README.md)
* [CloudBuild](../testing/modules/cloudbuild/README.md)
* [Source NFS Server](../testing/modules/source/README.md)

## Project Reference

* [Code of Conduct](CODE_OF_CONDUCT.md)
* [Contributing](CONTRIBUTING.md)
* [Security](SECURITY.md)

## External Documentation

* [Reexporting NFS filesystems](https://www.kernel.org/doc/html/latest/filesystems/nfs/reexport.html)
* [NFS wiki](https://linux-nfs.org/wiki/index.php/NFS_re-export)
