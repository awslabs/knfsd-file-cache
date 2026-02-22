#!/usr/bin/env bash
device=$(lsblk -o NAME,SIZE,TYPE | grep 'disk' | grep '50G' | awk '{print $1}' | head -n1)
mkfs.xfs "/dev/$device"
mkdir -p /mnt/build
mount "/dev/$device" /mnt/build
chown ubuntu:ubuntu /mnt/build
