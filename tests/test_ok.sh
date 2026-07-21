#!/bin/bash
set -euo pipefail


echo "Testing healthy pool"


OUTPUT=$($CHECK_ZPOOLS -p testpool)

RET=$?


echo "$OUTPUT"


if [ "$RET" -ne 0 ]; then
    echo "Expected OK"
    exit 1
fi


echo "Testing ALL pools"


OUTPUT=$($CHECK_ZPOOLS -p ALL)

RET=$?


echo "$OUTPUT"


if [ "$RET" -ne 0 ]; then
    echo "Expected OK for ALL"
    exit 1
fi


echo "PASS"
