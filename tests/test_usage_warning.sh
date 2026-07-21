#!/bin/bash
set -euo pipefail


echo "Creating warning usage"


sudo dd \
 if=/dev/urandom \
 of=/testpool/data/warning \
 bs=1M \
 count=1400 \
 status=progress

set +e
OUTPUT=$(./check_zpools.sh -p testpool -w 50 -c 90)
RET=$?
set -e

echo "$OUTPUT"

if [ "$RET" -ne 1 ]; then
    echo "Expected WARNING exit code 1"
    exit 1
fi

echo "PASS"
