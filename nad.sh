#!/bin/env bash

set -e

# TODO prevent multiple instances (pid lock)

export NAD_LOG_FILE='access_log'
export NAD_LINES_TO_CHECK=200
export NAD_DENY_PAGE='# error_page 403 http://example.com/forbidden.html;'

# count requests from each IP
eval "declare -A nad_state=(
    $(  tail -n$NAD_LINES_TO_CHECK $NAD_LOG_FILE \
        | cut -d' ' -f1 \
        | sort \
        | uniq -c \
        | while read _number _ip; do echo "[$_ip]=$_number"; done )
)"

# for i in ${!nad_state[@]}
# do
#    echo "$i - ${nad_state[$i]}"
# done
# echo total ${#nad_state[@]}

# check rates

# list blocked

# 
