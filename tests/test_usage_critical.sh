#!/bin/bash
set -euo pipefail

echo "Creating critical usage"

sudo dd \
 if=/dev/urandom \
 of=/testpool/data/critical \
 bs=1M \
 count=250 \
 status=progress

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
