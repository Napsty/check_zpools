#!/bin/bash
set -euo pipefail


zpool destroy -f testpool || true

losetup -D || true

rm -rf /tmp/zfs-test
