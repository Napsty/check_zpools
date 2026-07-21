#!/bin/bash
set -euo pipefail


echo "Testing health of a single ZFS pool"

ls -la

./check_zpools.sh -p testpool

OUTPUT=$(./check_zpools.sh -p testpool)

RET=$?


echo "$OUTPUT"


if [ "$RET" -ne 0 ]; then
    echo "Expected OK"
    exit 1
fi


echo "Testing ALL ZFS pools"


OUTPUT=$(./check_zpools.sh -p ALL)

RET=$?


echo "$OUTPUT"


if [ "$RET" -ne 0 ]; then
    echo "Expected OK for ALL"
    exit 1
fi


echo "PASS"
