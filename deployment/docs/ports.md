# Ports

KNFSD uses static ports for `nfs-kernel-server`. These ports are listed below.

You should allow inbound traffic to KNFSD from your NFS clients on the below ports.

For outbound connectivity from KNFSD to your source NFS server different ports may be used. Please consult the docs for your source NFS server for more information.

## General

* 80    - HTTP (knfsd-agent)

## NFS v3

* 111   - RPC portmapper
* 2049  - NFS
* 20048 - mountd
* 20050 - lockd-nlm
* 20051 - statd
* 20052 - statd (outbound)
* 20053 - lockd
* 20054 - sm-notify (outbound)

## NFS v4

* 2049  - NFS
* 20055 - NFS v4 callback
