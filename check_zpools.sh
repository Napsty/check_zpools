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
# Copyright (c) 2025 @amahr - Add soft fail option (2025-11-25)
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
# 2025-11-25  Add soft fail option
#########################################################################
### Begin vars
STATE_OK=0 # define the exit code if status is OK
STATE_WARNING=1 # define the exit code if status is Warning
STATE_CRITICAL=2 # define the exit code if status is Critical
STATE_UNKNOWN=3 # define the exit code if status is Unknown
SOFT_FAIL=0 # define the override of STATE_CRITICAL with STATE_WARNING
# Set path
PATH=$PATH:/usr/sbin:/sbin
export PATH
### End vars
#########################################################################
help="check_zpools.sh (c) 2006-2023 multiple authors\n
Usage: $0 -p (poolname|ALL) [-w warnpercent] [-c critpercent] [-s]\n
-s: Soft fail - report critical errors as warnings (exit code 1 instead of 2)\n
Example: $0 -p ALL -w 80 -c 90\n
Example: $0 -p ALL -w 80 -c 90 -s"
#########################################################################
# Check necessary commands are available
for cmd in zpool [
do
 if ! which "$cmd" 1>/dev/null
 then
 echo "UNKNOWN: ${cmd} does not exist, please check if command exists and PATH is correct"
 exit ${STATE_UNKNOWN}
 fi
done
#########################################################################
# Check for people who need help - we are nice ;-)
if [ "${1}" = "--help" ] || [ "${#}" = "0" ];
       then
       echo -e "${help}";
       exit ${STATE_UNKNOWN};
fi
#########################################################################
# Get user-given variables
while getopts "p:w:c:s" Input;
do
       case ${Input} in
       p)      pool=${OPTARG};;
       w)      warn=${OPTARG};;
       c)      crit=${OPTARG};;
       s)      soft_fail=1;;
       *)      echo -e "$help"
               exit $STATE_UNKNOWN
               ;;
       esac
done
#########################################################################
# Did user obey to usage?
if [ -z "$pool" ]; then echo -e "$help"; exit ${STATE_UNKNOWN}; fi
#########################################################################
# Verify threshold sense
if [[ -n $warn ]] && [[ -z $crit ]]; then echo "Both warning and critical thresholds must be set"; exit $STATE_UNKNOWN; fi
if [[ -z $warn ]] && [[ -n $crit ]]; then echo "Both warning and critical thresholds must be set"; exit $STATE_UNKNOWN; fi
if [[ $warn -gt $crit ]]; then echo "Warning threshold cannot be greater than critical"; exit $STATE_UNKNOWN; fi
#########################################################################
# Override critical exit code if soft fail is enabled
if [[ $soft_fail -eq 1 ]]; then
  STATE_CRITICAL=$STATE_WARNING
fi
#########################################################################
# What needs to be checked?
## Check all pools
if [ "$pool" = "ALL" ]
then
  POOLS=($(zpool list -Ho name))
  if [ $? -ne 0 ]; then
    echo "UNKNOWN zpool query failed"; exit $STATE_UNKNOWN
  fi
  p=0
  for POOL in ${POOLS[*]}
  do
    CAPACITY=$(zpool list -Ho capacity "$POOL")
    CAPACITY=${CAPACITY%\%}
    HEALTH=$(zpool list -Ho health "$POOL")
    if [ $? -ne 0 ]; then
      echo "UNKNOWN zpool query failed"; exit $STATE_UNKNOWN
    fi
    # Check with thresholds
    if [[ -n $warn ]] && [[ -n $crit ]]
    then
      fcrit=$STATE_WARNING
      if [ "$HEALTH" != "ONLINE" ]; then error[${p}]="$POOL health is $HEALTH // "; fcrit=$STATE_CRITICAL; fi
      if [[ $CAPACITY -ge $crit ]]; then error[${p}]+="POOL $POOL usage is CRITICAL (${CAPACITY}%) // "; fcrit=$STATE_CRITICAL; fi
      if [[ $CAPACITY -ge $warn && $CAPACITY -lt $crit ]]; then error[$p]+="POOL $POOL usage is WARNING (${CAPACITY}%)"; fi
    # Check without thresholds
    else
      if [ "$HEALTH" != "ONLINE" ]
      then error[${p}]="$POOL health is $HEALTH"; fcrit=$STATE_CRITICAL
      fi
    fi
    perfdata[$p]="$POOL=${CAPACITY}% "
    let p++
  done

  if [[ ${#error[*]} -gt 0 ]]
  then
    echo "ZFS POOL ALARM: ${error[*]}|${perfdata[*]}"; exit ${fcrit}
  else echo "ALL ZFS POOLS OK (${POOLS[*]})|${perfdata[*]}"; exit ${STATE_OK}
  fi

## Check single pool
else
  CAPACITY=$(zpool list -Ho capacity "$pool" 2>&1 )
  CAPACITY=${CAPACITY%\%}
  if [[ -n $(echo "${CAPACITY}" | egrep -q 'no such pool$') ]]; then
    echo "zpool $pool does not exist"; exit $STATE_CRITICAL
  fi
  HEALTH=$(zpool list -Ho health "$pool")
  if [ $? -ne 0 ]; then
    echo "UNKNOWN zpool query failed"; exit $STATE_UNKNOWN
  fi

  if [[ -n $warn ]] && [[ -n $crit ]]
  then
    warning=0
    critical=0
    # Check with thresholds
    if [ "$HEALTH" != "ONLINE" ]; then error="$pool health is $HEALTH // "; critical=1 ; fi
    if [[ $CAPACITY -ge $crit ]]; then error+="$pool usage is CRITICAL (${CAPACITY}%) // "; critical=1; fi
    if [[ $CAPACITY -ge $warn && $CAPACITY -lt $crit ]]; then error+="ZFS POOL ALARM: $pool usage is WARNING (${CAPACITY}%) // "; warning=1; fi
    if [[ $critical -gt 0 ]]; then echo "ZFS POOL ALARM: ${error[*]}|$pool=${CAPACITY}%"; exit ${STATE_CRITICAL}; fi
    if [[ $warning -gt 0 ]]; then echo "ZFS POOL ALARM: ${error[*]}|$pool=${CAPACITY}%"; exit ${STATE_WARNING}; fi
    echo "ALL ZFS POOLS OK ($pool)|$pool=${CAPACITY}%"; exit ${STATE_OK}
  else
    # Check without thresholds
    if [ "$HEALTH" != "ONLINE" ]
    then echo "ZFS POOL ALARM: $pool health is $HEALTH|$pool=${CAPACITY}%"; exit ${STATE_CRITICAL}
    else echo "ALL ZFS POOLS OK ($pool)|$pool=${CAPACITY}%"; exit ${STATE_OK}
    fi
  fi

fi

echo "UNKNOWN - Should never reach this part"
exit ${STATE_UNKNOWN}

