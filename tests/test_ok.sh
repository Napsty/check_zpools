#!/bin/bash
set -euo pipefail


echo "Testing health of a single ZFS pool"

OUTPUT=$(./check_zpools.sh -p testpool -w 80 -c 90)

RET=$?


echo "$OUTPUT"


if [ "$RET" -ne 0 ]; then
    echo "Expected OK"
    exit 1
fi


echo "Testing ALL ZFS pools"


OUTPUT=$(./check_zpools.sh -p ALL -w 80 -c 90)

RET=$?


echo "$OUTPUT"


if [ "$RET" -ne 0 ]; then
    echo "Expected OK for ALL"
    exit 1
fi


echo "PASS"
