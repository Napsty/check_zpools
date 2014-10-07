#!/bin/sh
#########################################################################
# Script:       check_zpools.sh
# Purpose:      Nagios plugin to monitor status of zfs pool
# Authors:      Aldo Fabi             First version (2006-09-01)
#               Vitaliy Gladkevitch   Forked (2013-02-04)
#               Claudio Kuenzler      Complete redo, perfdata, etc (2013-2014)
#               Alexander Skwar       Posix compliant
# Doc:          http://www.claudiokuenzler.com/nagios-plugins/check_zpools.php
# History:
# 2006-09-01    Original first version
# 2006-10-04    Updated (no change history known)
# 2013-02-04    Forked and released
# 2013-05-08    Make plugin work on different OS, pepp up plugin
# 2013-05-09    Bugfix in exit code handling
# 2013-05-10    Removed old exit vars (not used anymore)
# 2013-05-21    Added performance data (percentage used)
# 2013-07-11    Bugfix in zpool health check
# 2014-02-10    Bugfix in threshold comparison
# 2014-03-11    Allow plugin to run without enforced thresholds
# 2014-10-02    Made script Posix compliant - remove bash dependency
# 2014-10-07    Fixed various errors... Too bad, that there are no arrays
#########################################################################
### Begin vars
STATE_OK="0" # define the exit code if status is OK
STATE_WARNING="1" # define the exit code if status is Warning
STATE_CRITICAL="2" # define the exit code if status is Critical
STATE_UNKNOWN="3" # define the exit code if status is Unknown
# Set path
PATH="$PATH:/usr/sbin:/sbin"
export PATH
### End vars
#########################################################################
help="check_zpools.sh (c) 2006-2014 several authors\n
Usage: $0 -p (poolname|ALL) [-w warnpercent] [-c critpercent]\n
Example: $0 -p ALL -w 80 -c 90\n"
#########################################################################
# Check necessary commands are available
for cmd in zpool tr; do
    # http://stackoverflow.com/questions/592620/how-to-check-if-a-program-exists-from-a-bash-script
    type "$cmd" >/dev/null 2>&1 || { echo >&2 "UNKNOWN: ${cmd} does not exist, please check if command exists and PATH is correct"; exit $STATE_UNKNOWN; }
done
#########################################################################
# Check for people who need help - aren't we all nice ;-)
if [ "${1}" = "--help" -o "${#}" = "0" ]; then
    printf "${help}"
    exit "$STATE_UNKNOWN"
fi
#########################################################################
# Get user-given variables
while getopts "p:w:c:" Input; do
    case $Input in
    p)  pool="$OPTARG";;
    w)  warn="$OPTARG";;
    c)  crit="$OPTARG";;
    *)  printf "$help"
        exit "$STATE_UNKNOWN"
        ;;
    esac
done
#########################################################################
# Did user obey to usage?
if [ -z "$pool" ]; then printf "$help"; exit "$STATE_UNKNOWN"; fi
#########################################################################
# Verify threshold sense
if [ -n "$warn" ] && [ -z "$crit" ]; then echo "Both warning and critical thresholds must be set"; exit "$STATE_UNKNOWN"; fi
if [ -z "$warn" ] && [ -n "$crit" ]; then echo "Both warning and critical thresholds must be set"; exit "$STATE_UNKNOWN"; fi
if [ "$warn" -gt "$crit" ]; then echo "Warning threshold cannot be greater than critical"; exit "$STATE_UNKNOWN"; fi
#########################################################################
# What needs to be checked?
## Check all pools
error=""
errorCount=0
if [ $pool = "ALL" ]; then
    POOLS=` zpool list -Ho name `
    p=0
    for POOL in $POOLS; do
        # Initialize variables, which might be used later on
        CAPACITY=` zpool list -Ho capacity $POOL | tr -d '%' `
        HEALTH=` zpool list -Ho health $POOL `
        errorNum="error$p"
        perfdataNum="perfdata$p"
        fcrit="-1"

        # Check with thresholds
        if [ -n "$warn" ] && [ -n "$crit" ]; then
            if [ "$HEALTH" != "ONLINE" ]; then
                eval ` echo $errorNum=\"$POOL health is $HEALTH\" `
                fcrit=1
                errorCount=` expr $errorCount + 1 `
            elif [ "$CAPACITY" -ge "$crit" ]; then
                eval ` echo $errorNum=\"POOL $POOL usage is CRITICAL \($CAPACITY%\)\" `
                fcrit=1
                errorCount=` expr $errorCount + 1 `
            elif [ "$CAPACITY" -ge "$warn" ] && [ "$CAPACITY" -lt "$crit" ]; then
                eval ` echo $errorNum=\"POOL $POOL usage is WARNING \($CAPACITY%\)\" `
                errorCount=` expr $errorCount + 1 `
            fi
        # Check without thresholds
        else
            if [ "$HEALTH" != "ONLINE" ]; then
            eval ` echo $errorNum=\"$POOL health is $HEALTH\" `
            fcrit=1
            errorCount=` expr $errorCount + 1 `
            fi
        fi
        eval ` echo $perfdataNum="$POOL=${CAPACITY}% " `
        p=` expr "$p" + 1 `
    done

    if [ "$errorCount" != 0 ]; then
        if [ "$fcrit" -eq 1 ]; then exit_code="$STATE_CRITICAL"; else exit_code="$STATE_WARNING"; fi
        printf "ZFS POOL ALARM: "

        poolNum=0
        while [ "$poolNum" -le "$p" ]; do
            printf "%s " "` eval echo \\$error$poolNum `"
            poolNum=` expr $poolNum + 1 `
        done
        printf "|"

        poolNum=0
        while [ "$poolNum" -le "$p" ]; do
            printf "%s " "` eval echo \\$perfdata$poolNum `"
            poolNum=` expr $poolNum + 1 `
        done

        echo
        exit "$exit_code"
    else
        printf "ALL ZFS POOLS OK ("; printf "$POOLS" | tr '\n' ' '; printf ")|"

        poolNum=0
        while [ "$poolNum" -le "$p" ]; do
            perfdataNum="perfdata$poolNum"
            eval echo \$$perfdataNum
            poolNum=` expr $poolNum + 1 `
        done | tr '\n' ' '

        echo
        exit "$STATE_OK"
    fi

## Check single pool
else
    CAPACITY=` zpool list -Ho capacity $pool | tr -d '%' `
    HEALTH=` zpool list -Ho health $pool `

    if [ -n "$warn" ] && [ -n "$crit" ]; then
        # Check with thresholds
        if [ "$HEALTH" != "ONLINE" ]; then echo "ZFS POOL $pool health is $HEALTH|$pool=$CAPACITY%"; exit "$STATE_CRITICAL"
        elif [ "$CAPACITY" -gt "$crit" ]; then echo "ZFS POOL $pool usage is CRITICAL ($CAPACITY%|$pool=$CAPACITY%)"; exit "$STATE_CRITICAL"
        elif [ "$CAPACITY" -gt "$warn" ] && [ "$CAPACITY" -lt "$crit" ]; then echo "ZFS POOL $pool usage is WARNING ($CAPACITY%)|$pool=$CAPACITY%"; exit "$STATE_WARNING"
        else echo "ALL ZFS POOLS OK ($pool)|$pool=$CAPACITY%"; exit "$STATE_OK"
        fi
    else
        # Check without thresholds
        if [ "$HEALTH" != "ONLINE" ]; then echo "ZFS POOL $pool health is $HEALTH|$pool=$CAPACITY%"; exit "$STATE_CRITICAL"
        else echo "ALL ZFS POOLS OK ($pool)|$pool=$CAPACITY%"; exit "$STATE_OK"
        fi
    fi
fi

echo "UKNOWN - Should never reach this part"
exit "$STATE_UNKNOWN"
# EOF
