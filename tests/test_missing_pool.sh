#!/bin/bash
set -euo pipefail

POOL="does-not-exist"

echo "Testing missing ZFS pool detection"

set +e
OUTPUT=$(./check_zpools.sh -p "$POOL" -w 50 -c 80)
RET=$?
set -e

echo "$OUTPUT"

if [ "$RET" -ne 3 ]; then
    echo "Expected UNKNOWN exit code 3, got $RET"
    exit 1
fi

# Make sure the plugin reports something useful
if echo "$OUTPUT" | grep -qiE "not found|does not exist|unknown|cannot|error"; then
    echo "PASS"
else
    echo "Plugin returned CRITICAL but message was unexpected"
    exit 1
fi
