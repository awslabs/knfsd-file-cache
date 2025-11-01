# NFS Client Setup

## Amazon Elastic Network Adapter (ENA) Driver

NFS performance is heavily network-bound. It is highly recommended to install the latest [ENA driver](https://github.com/amzn/amzn-drivers/tree/master/kernel/linux/ena) on NFS clients to achieve maximum network throughput and best performance during periods of network congestion. Ideally, the ENA driver should be installed as part of your client image (AMI) building process. This ENA driver is already installed in the AMI for the KNFSD proxy instances.

### Ubuntu

Tested with Ubuntu 24.04 LTS.

```bash
#!/usr/bin/env bash
#apt-get update # uncomment if you need to update the system
apt-get install -yq git make gcc linux-headers
cd /tmp
git clone https://github.com/amzn/amzn-drivers
cd amzn-drivers/kernel/linux/ena/
make
ENA_FILE=$(find /lib/modules/"$(uname -r)"/kernel/drivers/net/ethernet/amazon/ena/ -name 'ena.ko*' -print0 | xargs -0 basename | head -n1)
install -D -m 644 ena.ko /lib/modules/"$(uname -r)"/kernel/drivers/net/ethernet/amazon/ena/"${ENA_FILE}"
modprobe ena
update-initramfs -u
```

### Rocky/Alma Linux

Tested with Rocky Linux 8.9/9.6/10.0 and Alma Linux 8.10/9.6/10.0.

```bash
#!/usr/bin/env bash
#dnf update -y && reboot # uncomment if you need to update the system
dnf install -y make gcc git kernel-devel-$(uname -r) elfutils-libelf-devel
cd /tmp
git clone https://github.com/amzn/amzn-drivers
cd amzn-drivers/kernel/linux/ena/
make
ENA_FILE=$(find /lib/modules/"$(uname -r)"/kernel/drivers/net/ethernet/amazon/ena/ -name 'ena.ko*' -print0 | xargs -0 basename | head -n1)
install -D -m 644 ena.ko /lib/modules/"$(uname -r)"/kernel/drivers/net/ethernet/amazon/ena/"${ENA_FILE}"
modprobe ena
dracut -f
```

## Fixing KNFSD Server IP Address (DNS-RR Architecture)

When using the DNS Round-Robin (DNS-RR) architecture, each DNS lookup can return a different KNFSD server IP address. Without intervention, a single NFS client may connect to multiple different KNFSD servers over time as it mounts different exports, which prevents optimal load distribution across your KNFSD fleet.

For example, a compute client mounting multiple exports (e.g., `/export/project1`, `/export/project2`) might connect mount1 to KNFSD-server-A and mount2 to KNFSD-server-B. This pattern across many clients results in uneven load distribution and connection inefficiency.

By "fixing" the KNFSD hostname to a single IP address in `/etc/hosts` at client boot time, each client is consistently pinned to one KNFSD server instance for all its mounts. This ensures even distribution: for example, 100 clients across 5 KNFSD servers results in approximately 20 clients per server, with each client maintaining all its connections through a single proxy. This approach can be achieved by performing a one-time DNS lookup at boot time (via `user-data` script) and writing the result to `/etc/hosts`, which takes precedence over DNS lookups.

**Note**: In the DNS-RR architecture, each KNFSD node has a static IP address that is managed by the serverless Lambda function. If a KNFSD node fails health checks, the static IP is automatically detached from the failed instance and re-attached to a healthy replacement instance. This means clients with "fixed" IP addresses in `/etc/hosts` will transparently fail over to the replacement node without requiring any client-side reconfiguration. We assume all NFS clients are configured to use the `hard` mount option.

```bash
#!/usr/bin/env bash
PROXY_HOSTNAME="nfsproxy-a1b2c3d4.aws.internal" # "dns_name" output from Terraform deployment
# get first IP from DNS-RR using dig, add to /etc/hosts
PROXY_IP=$(dig +short "${PROXY_HOSTNAME}" | head -n1)
echo "${PROXY_IP} ${PROXY_HOSTNAME}" >> /etc/hosts
```

## NFS Mount Options

The following additional NFS mount options are suggested for optimal performance:

* `hard`: Use hard mount to ensure that the client will retry the connection if it fails. Critical if an unhealthy KNFSD node is replaced by the Auto Scaling Group.
* `fsc`: Use FS-Cache to serve the files from local disk. Just like how the KNFSD proxy uses the local NVMe instance store for FS-Cache, the client can use the local disk for FS-Cache and thus potentially reduce load on the KNFSD proxy, allowing your current KNFSD cluster size to support more compute clients.
* `nconnect=<number>`: Increasing the `nconnect` option to the KNFSD proxy can improve performance, but careful attention should be paid to the number of connections per client. If the total number of connections across all client(s) is too high, it may overwhelm an individual KNFSD proxy and cause performance degradation. Recommended to start with the client vCPU count, divided by 2. For example, if the client has 16 vCPUs, set `nconnect=8`. To dynamically adjust the `nconnect` option, you can use the `nproc` command to get the number of vCPUs and divide by 2. Ensure you observe the [Networking Activity](../deployment/metrics/README.md#networking-activity) metrics in the CloudWatch dashboard to ensure the EC2 instance is not overwhelmed.

```bash
nproc=$(("$(nproc)/2"))
[ $nproc -gt 16 ] && nproc=16 # nconnect limit is 16, so cap at 16 if the client has more than 32 vCPUs
mount -t nfs -o vers=3,nconnect=${nproc},rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc "<remote_ip>:<remote_export>" <local_mount_point>
```
