# Examples

Ready-to-use Terraform configurations for common AWS managed file systems and deployment topologies. Each example is self-contained: copy the directory, adjust the variables for your environment, then run `terraform apply`.

Start with [Build (Packer)](../image/README.md) to create the KNFSD AMI, and see [Deploy (Terraform)](../deployment/README.md) for the full module reference.

## Available Examples

<!-- grid-cards:start -->
* [Basic NFS Example](basic/README.md)<br> <!-- icon: material-folder-outline -->
  A very simple, minimal deployment of a KNFSD proxy.
* [FSx for NetApp ONTAP](fsx-netapp/README.md)<br> <!-- icon: simple-netapp -->
  A single proxy in front of a single-AZ FSx for NetApp ONTAP filer, enforcing NFS v4.1 with automated export discovery and a DynamoDB FSID database.
* [FSx for OpenZFS](fsx-zfs/README.md)<br> <!-- icon: simple-openzfs -->
  A single proxy in front of a single-AZ FSx for OpenZFS filer, using NFS v3 for performance with automatic export detection via `showmount`.
* [FSx for OpenZFS Fanout (DNS Round Robin)](fsx-zfs-fanout-dns-rr/README.md)<br> <!-- icon: material-dns-outline -->
  A multi-tier fanout topology where a tier-1 proxy feeds a tier-2 cluster, distributing traffic with DNS round-robin.
* [FSx for OpenZFS Fanout (Network Load Balancer)](fsx-zfs-fanout-loadbalancer/README.md)<br> <!-- icon: material-scale-balance -->
  The same multi-tier fanout topology, using a Network Load Balancer instead of DNS round-robin to distribute traffic.
* [Weka NFS Gateway](weka/README.md)<br> <!-- icon: fontawesome-solid-kiwi-bird -->
  Two independent clusters serving `/projects` and `/software`, each tuned for different metadata cache and instance requirements.
<!-- grid-cards:end -->
