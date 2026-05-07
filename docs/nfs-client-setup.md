# NFS Client Setup

> CRITICAL: When using the DNS Round-Robin (DNS-RR) architecture, ensure all NFS clients mount the KNFSD proxy instance(s) using the `dns_name` output from the Terraform deployment (ideally) or the secondary ENI (Device Index: 1, `ens6`) private IP address of the proxy instance(s). Do NOT use the primary (Device Index: 0, `ens5`) private IP address of the proxy instance(s) for client mounts.

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

## Amazon ENA Express (ENA-X)

[ENA Express](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ena-express.html) (ENA-X) uses SRD to raise per-flow network throughput and cut tail latency between EC2 instances in the same Availability Zone when the instance type supports it. For Linux guests, AWS also documents OS tuning (MTU, ring buffers, TCP settings) in [ENA Express prerequisites for Linux](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ena-express.html#ena-express-prereq-linux).

After you configure a host, you can validate tuning with Amazon’s [check-ena-express-settings.sh](https://github.com/amzn/amzn-ec2-ena-utilities/blob/main/ena-express/check-ena-express-settings.sh) helper (pass your primary ENA interface name, for example `ens5`).

ENA Express must be enabled on **both** endpoints of the traffic (sender and receiver) for that path to use SRD. KNFSD proxy instances enable ENA-X automatically when the instance type supports it. Your NFS compute clients must enable ENA-X as well if you want SRD end-to-end. If either side does not support ENA-X or it is not enabled, traffic **falls back** to ordinary ENA/TCP behavior—there is no hard failure, but you do not get ENA-X performance benefits on that path.

When using EC2 Fleet, EC2 Spot Fleet, or AutoScaling Group, the launch template cannot safely specify `ena_srd_specification` for a single template shared across mixed EC2 instance types (unsupported types fail the launch). Instead, use **user data** (or an equivalent boot script) to call `modify-network-interface-attribute` on the **primary** network interface (device index **0** only; typically the interface whose MAC matches `meta-data` `mac` in cloud-init) after you confirm the instance type reports `EnaSrdSupported`.

### Prerequisites

The following `bash` example script requires the following tools:

* `cloud-init` — provides `cloud-init query` and `/run/cloud-init/instance-data.json`.
* `jq` — reads nested fields from `instance-data.json`.
* `aws` — `describe-instance-types` and `modify-network-interface-attribute`.
* `ip` — set link MTU.
* `ethtool` — Rx ring and interrupt moderation.
* `sysctl` — kernel tuning.

### IAM permissions

Attach an instance profile whose role allows the following. Tighten `Resource` and `Condition` in production (for example, limit `ModifyNetworkInterfaceAttribute` to ENIs owned by the instance or in your VPC).

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DescribeInstanceTypesForEnaExpress",
            "Effect": "Allow",
            "Action": "ec2:DescribeInstanceTypes",
            "Resource": "*"
        },
        {
            "Sid": "ModifyPrimaryEniEnaExpress",
            "Effect": "Allow",
            "Action": "ec2:ModifyNetworkInterfaceAttribute",
            "Resource": "arn:aws:ec2:*:*:network-interface/*"
        }
    ]
}
```

### User-data script

Run as **root** (for example as a MIME `text/x-shellscript` part in cloud-init, or a systemd oneshot). The script waits for cloud-init, enables ENA-X on the primary ENI only when `EnaSrdSupported` is true, then applies ENA-X-oriented Linux tuning on every ENA interface (commands are no-ops or best-effort on non-ENA or unsupported setups).

```bash
#!/usr/bin/env bash
# Enable ENA Express on the primary ENI (device index 0) when supported, and apply Linux tuning
set -o errexit
set -o pipefail

cloud-init status --wait > /dev/null

REGION=$(cloud-init query region)
INSTANCE_DATA="/run/cloud-init/instance-data.json"
INSTANCE_TYPE=$(jq -r '.ds.meta_data.instance_type // .ds.meta_data["instance-type"] // empty' "${INSTANCE_DATA}")
MAC=$(jq -r '.ds.meta_data.mac // empty' "${INSTANCE_DATA}")
ENI_ID=$(jq -r --arg mac "${MAC}" \
    '.ds.meta_data.network.interfaces.macs[$mac].interface_id // .ds.meta_data.network.interfaces.macs[$mac]["interface-id"] // empty' \
    "${INSTANCE_DATA}")

if [[ -z "${INSTANCE_TYPE}" ]] || [[ -z "${ENI_ID}" ]]; then
    echo "Could not read instance type or primary ENI from cloud-init instance data." >&2
    exit 1
fi

ENA_SRD_SUPPORTED=$(aws ec2 describe-instance-types \
    --region "${REGION}" \
    --instance-types "${INSTANCE_TYPE}" \
    --query 'InstanceTypes[0].NetworkInfo.EnaSrdSupported' \
    --output text)

if [[ "${ENA_SRD_SUPPORTED}" == "True" ]] || [[ "${ENA_SRD_SUPPORTED}" == "true" ]]; then
    aws ec2 modify-network-interface-attribute \
        --region "${REGION}" \
        --network-interface-id "${ENI_ID}" \
        --ena-srd-specification "EnaSrdEnabled=true,EnaSrdUdpSpecification={EnaSrdUdpEnabled=true}"
else
    echo "Instance type ${INSTANCE_TYPE} does not support ENA-X; skipping API enablement."
fi

sysctl -w net.core.rmem_max=16777216
sysctl -w net.core.wmem_max=16777216
sysctl -w net.core.netdev_max_backlog=16384
sysctl -w net.ipv4.tcp_rmem="4096 131072 16777216"
sysctl -w net.ipv4.tcp_wmem="4096 131072 16777216"
sysctl -w net.ipv4.tcp_limit_output_bytes=1048576
sysctl -w net.ipv4.tcp_autocorking=0
echo 0 > /sys/module/tcp_cubic/parameters/hystart_detect

for dev in /sys/class/net/en*; do
    iface=$(basename "${dev}")
    if [[ ! -d "${dev}/device/driver/module" ]] \
        || [[ "$(basename "$(readlink -f "${dev}/device/driver/module")")" != "ena" ]]; then
        echo "Skipping ${iface}: not an ENA device"
        continue
    fi
    ip link set dev "${iface}" mtu 8900 || true
    ethtool -G "${iface}" rx 8192 || true
    ethtool -C "${iface}" adaptive-rx on || true
done
```

## Fixing KNFSD Server IP Address (DNS-RR Architecture)

When using the DNS Round-Robin (DNS-RR) architecture, each DNS lookup can return a different KNFSD server IP address. Without intervention, a single NFS client may connect to multiple different KNFSD servers over time as it mounts different exports, which prevents optimal load distribution across your KNFSD fleet.

For example, a compute client mounting multiple exports (e.g., `/export/project1`, `/export/project2`) might connect mount1 to KNFSD-server-A and mount2 to KNFSD-server-B. This pattern across many clients results in uneven load distribution and connection inefficiency.

By "fixing" the KNFSD hostname to a single IP address in `/etc/hosts` at client boot time, each client is consistently pinned to one KNFSD server instance for all its mounts. This ensures even distribution: for example, 100 clients across 5 KNFSD servers results in approximately 20 clients per server, with each client maintaining all its connections through a single proxy. This approach can be achieved by performing a one-time DNS lookup at boot time (via `user-data` script) and writing the result to `/etc/hosts`, which takes precedence over DNS lookups.

**Note**: In the DNS-RR architecture, each KNFSD node has a static IP address that is managed by the serverless Lambda function. If a KNFSD node fails health checks, the static IP is automatically detached from the failed instance and re-attached to a healthy replacement instance. This means clients with "fixed" IP addresses in `/etc/hosts` will transparently fail over to the replacement node without requiring any client-side reconfiguration. We assume all NFS clients are configured to use the `hard` mount option.

```bash
#!/usr/bin/env bash
PROXY_HOSTNAME="knfsd-a1b2c3d4.aws.internal" # "dns_name" output from Terraform deployment
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
