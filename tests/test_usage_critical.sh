#!/bin/bash
set -euo pipefail


echo "Creating critical usage"


dd \
 if=/dev/zero \
 of=/testpool/data/critical \
 bs=1M \
 count=600 \
 status=progress


OUTPUT=$(
    $CHECK_ZPOOLS \
    -p testpool \
    -w 50 \
    -c 70
)

RET=$?


echo "$OUTPUT"


if [ "$RET" -ne 2 ]; then
    echo "Expected CRITICAL exit code 2"
    exit 1
fi


echo "PASS"
