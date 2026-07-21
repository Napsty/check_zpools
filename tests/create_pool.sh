#!/bin/bash
set -euo pipefail

POOL=testpool
TESTDIR=/tmp/zfs-test

mkdir -p "$TESTDIR"

truncate -s 2G "$TESTDIR/disk1.img"
truncate -s 2G "$TESTDIR/disk2.img"


LOOP1=$(losetup --find --show "$TESTDIR/disk1.img")
LOOP2=$(losetup --find --show "$TESTDIR/disk2.img")


echo "$LOOP1" > "$TESTDIR/loop1"
echo "$LOOP2" > "$TESTDIR/loop2"


zpool create \
    -f \
    "$POOL" \
    mirror \
    "$LOOP1" \
    "$LOOP2"


zfs create "$POOL/data"
zfs set compression=off "$POOL/data"
chmod 777 /"$POOL"/data


echo "Created pool:"
zpool status
