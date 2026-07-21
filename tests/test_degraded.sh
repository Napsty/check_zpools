#!/bin/bash
set -euo pipefail


LOOP2=$(cat /tmp/zfs-test/loop2)


echo "Offlining disk"

sudo zpool offline testpool "$LOOP2"


sleep 5


zpool status

set +e
OUTPUT=$(./check_zpools.sh -p testpool -w 50 -c 70)
RET=$?
set -e

echo "$OUTPUT"


if [ "$RET" -ne 2 ]; then
    echo "Expected CRITICAL exit code 2"
    exit 1
fi


echo "PASS"
