#!/usr/bin/env bash
device=$(lsblk -o NAME,SIZE,TYPE | grep 'disk' | grep '50G' | awk '{print $1}' | head -n1)
mkfs.ext4 "/dev/$device"
mkdir -p /mnt/build
mount "/dev/$device" /mnt/build
chown ubuntu:ubuntu /mnt/build
