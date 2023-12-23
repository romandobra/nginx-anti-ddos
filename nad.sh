#!/bin/env bash

set -e

# TODO prevent multiple instances (pid lock)

export NAD_LOG_FILE='access_log'
export NAD_LINES_TO_CHECK=200
#export NAD_MIN_IP_COUNT=5
export NAD_MAX_REQUESTS=3
export NAD_COOLDOWN=500 # seconds

export NAD_DENY_FILE='nad_deny_ip.conf'
#export NAD_DENY_PAGE='# error_page 403 http://example.com/forbidden.html;'

# redefine this function if you need reports
nad_report_attack(){ true; }

[ -e .settings ] && source .settings

_NAD_RUNDATE=$(date +%s)

# count log lines
_NAD_LOG_COUNT=($(wc -l access_log | cut -d' ' -f1))

if [ $_NAD_LOG_COUNT -gt $NAD_LINES_TO_CHECK ]; then
# count requests from each IP
    eval "declare -A nad_state=(
        $(  tail -n$NAD_LINES_TO_CHECK $NAD_LOG_FILE \
            | cut -d' ' -f1 \
            | sort \
            | uniq -c \
            | while read _number _ip
                do

# skip if lower than NAD_MAX_REQUESTS
                    if [ $_number -gt $NAD_MAX_REQUESTS ]; then
                        echo "[$_ip]=$_number"
                    fi
                done
        )
    )"
fi

# list blocked
eval "declare -A nad_blocked=(
    $(  cat $NAD_DENY_FILE \
        | grep -w deny \
        | while read _ _ip _date
            do
                _date=(${_date//[^[:alnum:]]/})

# remove denied if cooldown is over
                if [ $(($_NAD_RUNDATE - $_date )) -lt $NAD_COOLDOWN ]; then
                    echo "[${_ip%;}]=$_date"
                fi
            done
    )
)"

echo state ${#nad_state[@]}
echo blocked ${#nad_blocked[@]}

# for i in ${!nad_state[@]}
# do
#    echo "$i - ${nad_state[$i]}"
# done
# echo total ${#nad_state[@]}

# update deny_ip file
# reload nginx
# try first
