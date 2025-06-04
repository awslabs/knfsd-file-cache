# Fan Out Architecture

> INFO: This architecture requires the use of NFS v4.

## Overview

In the standard architecture, one layer of KNFSD proxies are deployed that sit between the downstream clients and the on-premise/source NFS server. This approach is shown in the below diagram:

![KNFSD Standard Deployment Diagram](images/standard-deployment.png "KNFSD Standard Deployment")

This approach is the simplest deployment architecture, and also the most performant when it comes to reading uncached files, and writing files back through to the on-premise/source NFS server.

However in this model, as the KNFSD nodes in a cluster do not share cached items with each other, having multiple KNFSD nodes means that often files are transferred across the network multiple times. This is because different downstream clients might be connected to different KNFSD nodes, meaning that even if 2 downstream clients are requesting the same file, that file may need to be pulled from on-premise/source twice.

One approach to mitigating this challenge is to deploy two KNFSD clusters in a "fanout" or "2-tier" architecture. This approach is shown in the below diagram:

![KNFSD Fanout Deployment Diagram](images/fanout-deployment.png "KNFSD Fanout Deployment")

In this architecture, a single KNFSD node is deployed that is responsible for all communication back to the on-premise filer (the fanout node). A second KNFSD cluster is then deployed that connects to this fanout node. Downstream clients all connect to this second cluster.

This architecture mitigates the challenges around duplicate file transfers from on-premise. The fanout node acts as the primary cache, and the second cluster is deployed to prevent overloading the fanout cache. This reduces the volume of data that needs to be transferred over the VPN/Direct Connect (DX) connection.

## Considerations

While this architecture can provide performance benefits for certain use-cases, there are some considerations that need to be made:

1. The KNFSD fanout node has the potential to act as a performance botleneck, but conversely it can dramatically reduce the bandwidth consumed over the VPN/DX connection by reducing the volume of duplicated file transfers.
2. First time reads, and writes back to on-premise/source will be less performant as there is an additional hop involved.
3. The cost of running the KNFSD infrastructure will increase due to additional nodes. However this may be offset by enabling a smaller VPN/DX link.
4. Adding an additional re-export layer adds up to an additional 25 bytes to the filehandle. This means that NFSv4 must be used for the re-exports as NFSv3 has a 64-byte filehandle size limit.

## Example Deployment of Fanout Architecture

There is no special logic in the KNFSD Terraform Module to handle the fanout architecture. Instead the module is defined twice to achieve the fanout deployment. The below code block shows an example deployment of the fanout architecture.

1. The module `nfs_proxy_fanout` defines the fanout cluster responsible for connecting to on-premise/source.
2. The module `nfs_proxy_cluster` defines the cluster that connects to the fanout node. Downstream compute clients all connect to this cluster.

```terraform
module "nfs_proxy_fanout" {
  source = "github.com/awslabs/knfsd-file-cache/deployment/terraform-module-knfsd?ref=v1.1.0-alpha.2"

  # AWS
  REGION = "us-east-1"
  SUBNET = "subnet-0123456789abcdefg"

  # Network
  TRAFFIC_MODE = "loadbalancer"

  # KNFSD
  PROXY_AMI = "ami-0123456789abcdefg"

  # Fanout Specific Configuration
  INSTANCE_TYPE         = "i3en.12xlarge"                        // Use a higher CPU and Memory machine type to increase fanout performance
  KNFSD_NODES           = 1                                      // Only deploy 1 node in the cluster because we want a single fanout node
  EXPORT_MAP            = "10.0.5.5;/remoteexport;/remoteexport" // Define the exports in the standard way
  PROXY_BASENAME        = "nfsproxy-fanout"                      // Give this proxy a unique base name
  DISABLED_NFS_VERSIONS = "3,4.0,4.2"                            // Only allow NFSv4.1 on exports due to additional filehandle size
}

module "nfs_proxy_cluster" {
  source = "github.com/awslabs/knfsd-file-cache/deployment/terraform-module-knfsd?ref=v1.1.0-alpha.2"

  # AWS
  REGION = "us-east-1"
  SUBNET = "subnet-0123456789abcdefg"

  # Network
  TRAFFIC_MODE = "loadbalancer"

  # KNFSD
  PROXY_AMI = "ami-0123456789abcdefg"

  # Cluster Specific Configuration
  INSTANCE_TYPE            = "i3en.3xlarge"                                          // Use a smaller CPU and memory machine type as we have multiple nodes in the cluster
  KNFSD_NODES              = 3                                                       // Deploy more than 1 knfsd node for the standard cluster
  EXPORT_HOST_AUTO_DETECT  = module.nfs_proxy_fanout.nfsproxy_loadbalancer_ipaddress // Automatically detect the exports from the fanout node
  PROXY_BASENAME           = "nfsproxy-cluster"                                      // Give this cluster a unique base name
  DISABLED_NFS_VERSIONS    = "3,4.0,4.2"                                             // Only allow NFSv4.1 on exports due to additional filehandle size
  NFS_MOUNT_VERSION        = "4.1"                                                   // Mount the fanout node as NFSv4.1 due to filehandle size limitations in NFSv3
}


// Print the IP address of the Load Balancer that the cluster clients will connect to
output "load_balancer_ip_address" {
  value = module.nfs_proxy_cluster.nfsproxy_loadbalancer_ipaddress
}

// Print the DNS address of the Load Balancer that the cluster clients will connect to
output "load_balancer_dns_address" {
  value = module.nfs_proxy_cluster.nfsproxy_loadbalancer_dnsaddress
}
```
