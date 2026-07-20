#!/usr/bin/env bash

#########################################################################
# Script:     check_zpools.sh
# Purpose:    Nagios plugin to monitor status of zfs pool
# Doc:        http://www.claudiokuenzler.com/monitoring-plugins/check_zpools.php
# Licence:    GNU General Public Licence (GPL) v2 http://www.gnu.org/
#########################################################################
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, see <https://www.gnu.org/licenses/>.
#########################################################################
# Copyright (c) 2006 Aldo Fabi - First version (2006-09-01)
# Copyright (c) 2013 Vitaliy Gladkevitch - Forked (2013-02-04)
# Copyright (c) 2013-2023 Claudio Kuenzler - Current maintainer
# Copyright (c) 2016 Per von Zweigbergk - Various fixes (2016-10-12)
# Copyright (c) 2022 @waoki - Trap zpool command errors (2022-03-01)
# Copyright (c) 2022 @mrdsam - Improvement (2022-05-24)
# Copyright (c) 2023 @kresike - Improvement (2023-02-22)
# Copyright (c) 2026 @joyfulrabbit - Improvement (2026-02-10)
# Copyright (c) 2026 @numericillustration - Improvement (2026-02-11)
# Copyright (c) 2026 @SnejPro - disk-level monitoring and performance data for errors (2026-07-20)
#########################################################################
# History/Changelog:
# 2006-09-01  Original first version
# 2006-10-04  Updated (no change history known)
# 2013-02-04  Forked and released
# 2013-05-08  Make plugin work on different OS, pepp up plugin
# 2013-05-09  Bugfix in exit code handling
# 2013-05-10  Removed old exit vars (not used anymore)
# 2013-05-21  Added performance data (percentage used)
# 2013-07-11  Bugfix in zpool health check
# 2014-02-10  Bugfix in threshold comparison
# 2014-03-11  Allow plugin to run without enforced thresholds
# 2016-10-12  Fixed incorrect shell quoting and typos
# 2022-03-01  Merge PR #10, manually solve conflicts
# 2022-05-24  Removed need for 'awk', using bash-functions instead
# 2023-02-15  Bugfix in single pool CRITICAL output (issue #13)
# 2023-02-22  Improve message consistency and display all issues found in pool
# 2023-09-28  Add license
# 2026-02-10  Added check for spare disks in use
# 2026-02-11  Fixed incongruous styles, enhanced exit checks, used vars, unified single and multiple pool checks
#             removed unreachable code, consolidated on [[ and (( tests shellcheck error free
# 2026-07-20  Added disk-level monitoring and performance data for errors
#########################################################################
### Begin vars
STATE_OK=0 # define the exit code if status is OK
STATE_WARNING=1 # define the exit code if status is Warning
STATE_CRITICAL=2 # define the exit code if status is Critical
STATE_UNKNOWN=3 # define the exit code if status is Unknown
declare -a POOLS
declare -a error
declare -a perfdata
# Set path
PATH="${PATH}:/usr/sbin:/sbin"
export PATH
### End vars

#########################################################################
help="check_zpools.sh (c) 2006-2026 multiple authors\n
Usage: $0 -p (poolname|ALL) [-w warnpercent] [-c critpercent]\n
Example: $0 -p ALL -w 80 -c 90"

#########################################################################
# Check necessary commands are available
if ! which zpool 1>/dev/null
then
    echo "UNKNOWN: zpool not found in path: $PATH, please check if command exists and PATH is correct"
    exit "$STATE_UNKNOWN"
fi

# Check if jq is available
if ! which jq 1>/dev/null
then
    JQ_AVAILABLE=0
else
    JQ_AVAILABLE=1
fi
#########################################################################
# Check for people who need help - we are nice ;-)
if [[ $1 == "--help" || "${#}" == "0" ]]
then
    echo -e "$help"
    exit "$STATE_UNKNOWN"
fi
#########################################################################
# Get user-given variables
while getopts "p:w:c:" Input;
do
    case "$Input" in
    p)      pool="$OPTARG" ;;
    w)      warn="$OPTARG" ;;
    c)      crit="$OPTARG" ;;
    *)      echo -e "$help"
            exit "$STATE_UNKNOWN"
            ;;
    esac
done
#########################################################################
# Did user obey to usage?
if [[ -z "$pool" ]]
then
    echo -e "$help"
    exit "$STATE_UNKNOWN"
fi

#########################################################################
# Verify thresholds were supplied
if [[ -z "$crit" || -z "$warn" ]]
then
    echo "Both warning and critical thresholds must be set"
    exit "$STATE_UNKNOWN"
fi

if (( warn > crit ))
then
    echo "Warning threshold cannot be greater than critical"
    exit "$STATE_UNKNOWN"
fi
#########################################################################
# What needs to be checked?
## Check all pools
if [[ $pool == "ALL" ]]
then
    mapfile -t POOLS <<<"$(zpool list -Ho name)"
    pool_list_ret="$?"
    if (( pool_list_ret > 0 ))
    then
        echo "UNKNOWN zpool list by name query failed"
        exit "$STATE_UNKNOWN"
    fi
else
    POOLS=( "$pool" )
fi

for (( p=0; p<${#POOLS[@]}; p++))
do
    CAPACITY="$(zpool list -Ho capacity "${POOLS[$p]}" )"
    cap_ret="$?"
    if (( cap_ret > 0 ))
    then
        echo "UNKNOWN zpool query for capacity of ${POOLS[$p]} failed with exit code $cap_ret"
        exit "$STATE_UNKNOWN"
    fi

    CAPACITY="${CAPACITY%\%}"

    HEALTH="$(zpool list -Ho health "${POOLS[$p]}")"
    health_ret="$?"
    if (( health_ret > 0 ))
    then
        echo "UNKNOWN zpool query for health of ${POOLS[$p]} failed with exit code $health_ret"
        exit "$STATE_UNKNOWN"
    fi

    # Check for spare disks in use (indicates a disk failure occurred sometime)
    POOL_STATUS=$(zpool status "${POOLS[$p]}" )
    status_ret="$?"
    if (( status_ret > 0 ))
    then
        echo "UNKNOWN zpool query for status of ${POOLS[$p]} failed with exit code $status_ret"
        exit "$STATE_UNKNOWN"
    else
        # grep the output now that the status command succeeded
        SPARES_INUSE=$(grep -c "INUSE" <<<"$POOL_STATUS")
    fi

    # check if pool is healthy
    if [[ $HEALTH != "ONLINE" ]]
    then
        error["$p"]="POOL ${POOLS[$p]} health is $HEALTH"
        fcrit=1
    fi

    # check if disks are healthy
    # don't break existing installations which don't have jq installed
    if [[ $JQ_AVAILABLE == 1 ]]
    then
        POOL_STATUS_JSON=$(zpool status "${POOLS[$p]}" -j --json-int)

        check_vdev () {
            VDEV_TYPE=$(echo "${POOL_STATUS_JSON}" | jq -r "${1}.vdev_type")
            if [[ $VDEV_TYPE != null ]]
            then
                if [[ $VDEV_TYPE == "disk" ]]
                then
                    DISK_HEALTH=$(echo "${POOL_STATUS_JSON}" | jq -r "${1}.state")
                    DISK_NAME=$(echo "${POOL_STATUS_JSON}" | jq -r "${1}.name")

                    DISK_READ_ERRORS=$(echo "${POOL_STATUS_JSON}" | jq -r "${1}.read_errors")
                    DISK_WRITE_ERRORS=$(echo "${POOL_STATUS_JSON}" | jq -r "${1}.write_errors")
                    DISK_CHECKSUM_ERRORS=$(echo "${POOL_STATUS_JSON}" | jq -r "${1}.checksum_errors")

                    perfdata+=("${POOLS[$p]}---disk---${DISK_NAME}---READ-ERRORS=${DISK_READ_ERRORS}")
                    perfdata+=("${POOLS[$p]}---disk---${DISK_NAME}---WRITE-ERRORS=${DISK_WRITE_ERRORS}")
                    perfdata+=("${POOLS[$p]}---disk---${DISK_NAME}---CHECKSUM-ERRORS=${DISK_CHECKSUM_ERRORS}")

                    if [[ $DISK_HEALTH != "ONLINE" ]]
                    then
                        error["$p"]+="POOL ${POOLS[$p]} has unhealthy disk ${DISK_NAME} with state $DISK_HEALTH"
                        fcrit=1
                    fi
                else
                    DISK_NAME=$(echo "${POOL_STATUS_JSON}" | jq -r "${1}.name")

                    DISK_READ_ERRORS=$(echo "${POOL_STATUS_JSON}" | jq -r "${1}.read_errors")
                    DISK_WRITE_ERRORS=$(echo "${POOL_STATUS_JSON}" | jq -r "${1}.write_errors")
                    DISK_CHECKSUM_ERRORS=$(echo "${POOL_STATUS_JSON}" | jq -r "${1}.checksum_errors")

                    perfdata+=("${POOLS[$p]}---${VDEV_TYPE}---${DISK_NAME}---READ-ERRORS=${DISK_READ_ERRORS}")
                    perfdata+=("${POOLS[$p]}---${VDEV_TYPE}---${DISK_NAME}---WRITE-ERRORS=${DISK_WRITE_ERRORS}")
                    perfdata+=("${POOLS[$p]}---${VDEV_TYPE}---${DISK_NAME}---CHECKSUM-ERRORS=${DISK_CHECKSUM_ERRORS}")
                fi
            fi

            if ! $(echo "${POOL_STATUS_JSON}" | jq "${1} | has(\"vdevs\")")
            then
                return 0
            fi

            VDEV_PATH="${1}.vdevs"
            VDEVS=$(echo "${POOL_STATUS_JSON}" | jq "${VDEV_PATH} | keys")

            while read -r VDEV; do
                check_vdev "${VDEV_PATH}.${VDEV}"
            done < <(jq -c '.[]' <<< "$VDEVS")
        }

        check_vdev ".pools.${POOLS[$p]}"
    fi

    # Check that capacity is with thresholds
    if (( CAPACITY > crit ))
    then
        error["$p"]+="POOL ${POOLS[$p]} usage is CRITICAL (${CAPACITY}%)"
        fcrit=1
    elif (( CAPACITY > warn )) && (( CAPACITY < crit ))
    then
        error["$p"]+="POOL ${POOLS[$p]} usage is WARNING (${CAPACITY}%)"
    fi

    # tell us whenever a spare is in use
    if (( SPARES_INUSE > 0 ))
    then
        error["$p"]+="POOL ${POOLS[$p]} has $SPARES_INUSE spare(s) in use"
    fi

    perfdata+=("${POOLS[$p]}=${CAPACITY}%")
done

if (( ${#error[*]} > 0 ))
then
    echo "ZFS POOL ALARM: ${error[*]}|${perfdata[*]}"
    if (( fcrit == 1 ))
    then
        exit "$STATE_CRITICAL"
    else
        exit "$STATE_WARNING"
    fi
else
    echo "ALL ZFS POOLS OK (${POOLS[*]})|${perfdata[*]}"
    exit "$STATE_OK"
fi
