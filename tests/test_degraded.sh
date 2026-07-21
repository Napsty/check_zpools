#!/bin/bash
set -euo pipefail


LOOP2=$(cat /tmp/zfs-test/loop2)


echo "Offlining disk"

zpool offline \
    testpool \
    "$LOOP2"


sleep 5


zpool status


OUTPUT=$(
    $CHECK_ZPOOLS \
    -p testpool
)

RET=$?


echo "$OUTPUT"


if [ "$RET" -ne 2 ]; then
    echo "Expected CRITICAL exit code 2"
    exit 1
fi


echo "PASS"
