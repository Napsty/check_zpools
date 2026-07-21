#!/bin/bash
set -euo pipefail


echo "Creating warning usage"


dd \
 if=/dev/zero \
 of=/testpool/data/warning \
 bs=1M \
 count=2800 \
 status=progress


OUTPUT=$(./check_zpools.sh -p testpool -w 50 -c 90)
RET=$?

echo "$OUTPUT"

if [ "$RET" -ne 1 ]; then
    echo "Expected WARNING exit code 1"
    exit 1
fi

echo "PASS"
