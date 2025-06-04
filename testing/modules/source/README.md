# Source NFS server

Creates a source NFS server for use with KNFSD proxy clusters.

This only create a single export `/files`.

## NFS export

The source server uses a separate attached disk for the NFS export.

### Creating a blank disk

To create a blank disk, set `NFS_IMAGE = ""`, and set `CAPACITY_GB` to the size
of disk you want for the NFS share.

### Using an existing disk image

The source server is often most useful when using an existing disk image, such
as `source-files`. This will start the source server pre-populated with the
files on the disk image.

Set `CAPACITY_GB = 0`, and set `NFS_IMAGE` to the name of the disk image to use
for the NFS export.

## Traffic shaping

The `LATENCY_MS` and `RATE_LIMIT_MBIT` variables will apply traffic shaping to
the source server using the Linux traffic control (tc) with the Network Emulator (netem).

This can be used as the source server for a proxy to test how the proxy behaves when the source server becomes overloaded, or when the source server has high latency.
