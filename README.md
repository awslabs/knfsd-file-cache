# KNFSD File Cache

<div align="center">
  <a href="./LICENSE">
    <img alt="License" src="https://img.shields.io/github/license/awslabs/knfsd-file-cache?style=for-the-badge">
  </a>
  <a href="https://github.com/awslabs/knfsd-file-cache/releases">
    <img alt="Latest Release" src="https://img.shields.io/github/v/release/awslabs/knfsd-file-cache?include_prereleases&sort=semver&style=for-the-badge">
  </a>
  <a href="https://github.com/awslabs/knfsd-file-cache/actions/workflows/codeql.yml">
    <img alt="CodeQL" src="https://img.shields.io/github/actions/workflow/status/awslabs/knfsd-file-cache/codeql.yml?branch=main&label=codeql&style=for-the-badge">
  </a>
</div>

<div align="center">
  <img alt="Packer" src="https://img.shields.io/badge/Packer-1.16-02A8EF?style=for-the-badge&logo=packer&logoColor=white">
  <img alt="Terraform" src="https://img.shields.io/badge/Terraform-1.2-7B42BC?style=for-the-badge&logo=terraform&logoColor=white">
  <img alt="Go" src="https://img.shields.io/badge/Go-1.27-00ADD8?style=for-the-badge&logo=go&logoColor=white">
  <img alt="Python" src="https://img.shields.io/badge/Python-3.14-3776AB?style=for-the-badge&logo=python&logoColor=white">
</div>

https://github.com/user-attachments/assets/d54a5992-bd9a-4ded-be06-3d10111a57c1

Please log issues/feature requests in [GitHub](https://github.com/awslabs/knfsd-file-cache/issues). Contact: [knfsd-file-cache@amazon.com](mailto:knfsd-file-cache@amazon.com)

![Arch](docs/images/arch.png)

## Overview

This repository contains a set of utilities for building, deploying and operating a high performance NFS cache in Amazon Web Services (AWS). It is designed to be used for certain HPC and burst compute use-cases where there is a requirement for a high performance NFS cache between a NFS server and its downstream NFS clients.

This solution is based on existing Linux kernel modules, including `nfs-kernel-server` which supports NFS re-exporting and `cachefilesd` (FS-Cache) which provides a persistent cache of network file systems on disk.

The solution works by mounting NFS exports from a source NFS filer (typically located on-premise) and re-exporting the mount points to downstream NFS clients in AWS.

Performing this re-export provides two layers of caching:

* **Level 1:** The standard block cache of the operating system, residing in RAM.
* **Level 2:** FS-Cache. A Linux kernel module which caches data from network file systems locally on disk as pages. When the volume of data exceeds available RAM (L1), the data is cached on the disk by FS-Cache. In this deployment, we use local NVMe volumes for the L2 cache, although this could be configured in a number of ways, including using EBS volumes.

Using the deployment scripts in this repository, we further extend this architecture by creating multiple NFS proxies in an [Auto Scaling Group](https://docs.aws.amazon.com/autoscaling/ec2/userguide/auto-scaling-groups.html) and using either DNS round-robin or a [Network Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/introduction.html) to manage connections between the NFS clients and NFS cache.

The NFS caching solution is collectively referred to as `KNFSD` in this repository.

## Documentation

The [docs](./docs/index.md) directory provides comprehensive documentation for the solution.

<!-- grid-cards:start -->
* **Build &amp; Deploy**<br> <!-- icon: material-rocket-launch-outline -->
  Build the proxy AMI with Packer and deploy the caching cluster to AWS using Terraform modules. Covers VPC endpoints, load balancers, database, DNS round-robin, and metrics dashboards.
  * [Build (Packer)](image/README.md)
  * [VPC Endpoints](deployment/docs/vpc-endpoints.md)
  * [Deploy (Terraform)](deployment/README.md)
  * [Metrics Dashboard](deployment/metrics/README.md)
* **Reference**<br> <!-- icon: material-code-braces -->
  Detailed technical reference for all components: NFS auto re-export, autoscaling, fanout topologies, filter patterns, security groups, FSIDs, metrics, ports, traffic distribution, and VPC endpoints.
  * [Traffic Distribution](deployment/docs/traffic-distribution.md)
  * [Filesystem IDs](deployment/docs/fsids.md)
  * [Autoscaling](deployment/docs/autoscaling.md)
  * [Metrics Agent (OpenTelemetry)](image/resources/knfsd-metrics-agent/README.md)
* **User Guide**<br> <!-- icon: material-account-outline -->
  Day-to-day operational guidance: verify proxy startup, configure NFS clients, collect client metrics, troubleshoot known issues, and stay current with the changelog and FAQ.
  * [NFS Client Setup](docs/nfs-client-setup.md)
  * [FAQ](docs/faq.md)
  * [Known Issues](docs/known-issues.md)
* **Tutorial**<br> <!-- icon: material-book-open-variant-outline -->
  End-to-end walkthrough for deploying a kernel-space NFS caching proxy in AWS from scratch, including all required infrastructure, IAM permissions, and validation steps.
  * [Deploy a Kernel-space NFS Caching Proxy in AWS](tutorial/README.md)
* **Examples**<br> <!-- icon: material-folder-multiple-outline -->
  Ready-to-use Terraform configurations for common AWS managed file systems and deployment topologies, including fanout with DNS round-robin and network load balancer.
  * [FSx for NetApp ONTAP](examples/fsx-netapp/README.md)
  * [FSx for OpenZFS](examples/fsx-zfs/README.md)
  * [Weka NFS Gateway](examples/weka/README.md)
* **Developer**<br> <!-- icon: material-tools -->
  Advanced documentation for contributors and developers: local development setup, pre-commit hooks, GitLab CI pipelines, contributing guidelines, and code of conduct.
  * [Advanced / Developer Guide](docs/developer.md)
  * [Pre-Commit](docs/pre-commit.md)
  * [GitLab CI](docs/gitlab-ci.md)
<!-- grid-cards:end -->

## Metrics

KNFSD provides a number of metrics for monitoring and observability. These are collected by the [Amazon CloudWatch Agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent.html) and [KNFSD Metrics Agent](image/resources/knfsd-metrics-agent/README.md) and published to Amazon CloudWatch. See the [Metrics Dashboard](deployment/metrics/README.md) documentation for more details. Third party tools can also be used to collect and visualise the Open-Telemetry based metrics, such as [Prometheus](https://prometheus.io/) and [Grafana](https://grafana.com/). Client-side metrics can be collected by the [KNFSD Metrics Agent](image/resources/knfsd-metrics-agent/README.md) running on the NFS client instances. See the [Client Metrics](docs/client-metrics.md) documentation for more details.

![Metrics](docs/images/metrics.png)

## Dev Container

Two optional but recommended Dev Containers are provided:

1. `.devcontainer/prod`
2. `.devcontainer/dev`

For end users, the `.devcontainer/prod` container provides the minimum configuration for a production environment to build, deploy, and operate the KNFSD image.

For developers, the [`.devcontainer/dev`](./docs/developer.md) container provides a fully featured development environment for all parts of this project.

## License

This project is licensed under the Apache-2.0 License. See the [LICENSE](./LICENSE) file for details. See the [THIRD-PARTY-LICENSES](./THIRD-PARTY-LICENSES) file for licenses referenced by our dependencies.

Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
