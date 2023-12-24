#!/bin/env bash

set -e

export NAD_WHITE_LIST='43.142.47.190'
export NAD_LOG_FILE='access_log'
export NAD_LINES_TO_CHECK=100
export NAD_MAX_REQUESTS=2
export NAD_COOLDOWN=5 # seconds
#export NAD_LOG_GREP="cat" # for testing
export NAD_LOG_GREP="grep -e '$(date '+%d/%b/%Y:%H:%M')' -e '$(date -d 'minute ago' '+%d/%b/%Y:%H:%M')'"

export NAD_DENY_FILE='nad_deny_ip.conf'
#export NAD_DENY_PAGE='# error_page 403 http://example.com/forbidden.html;'

# redefine this function if you need reports other than sdtout
nad_report(){ echo "$1"; }

_NAD_RUNDATE=$(date +%s)
_NAD_LOCK_FILE="/var/lock/nad"

[ -e .settings ] && source .settings
[ -e $_NAD_LOCK_FILE ] && { nad_report "locked $(cat $_NAD_LOCK_FILE)"; exit 1; }

echo $_NAD_RUNDATE > $_NAD_LOCK_FILE

# list blocked
eval "declare -A nad_blocked=(
    $(
        {
        cat $NAD_DENY_FILE \
        | grep -w deny \
        | while read _deny_word _ip _date
            do
                _date=(${_date//[^[:alnum:]]/})

# skip if cooldown is over
                if [ $(( $_NAD_RUNDATE - $_date )) -gt $NAD_COOLDOWN ]; then continue; fi

                echo "[${_ip%;}]=$_date"
            done
    } | sort
    )
)"

# count log lines
_NAD_LOG_COUNT=($(wc -l $NAD_LOG_FILE | cut -d' ' -f1))

if [ $_NAD_LOG_COUNT -gt $NAD_LINES_TO_CHECK ]; then
# count requests from each IP
    eval "declare -A nad_state=(
        $({
        tail -n$NAD_LINES_TO_CHECK $NAD_LOG_FILE \
            | eval "$NAD_LOG_GREP" \
            | cut -d' ' -f1 \
            | sort \
            | uniq -c \
            | while read _number _ip
                do

# skip if lower than NAD_MAX_REQUESTS
                    if [ $_number -lt $NAD_MAX_REQUESTS ]; then continue; fi

# skip if aready blocked
                    [ "${nad_blocked[$_ip]+abc}" ] && continue
#                    if [[ -v nad_blocked[$_ip] ]];then continue; fi

                    echo "[$_ip]=$_number"
                done
        } | sort )
    )"
fi

# echo "# new ${#nad_state[@]}"
# echo "# old ${#nad_blocked[@]}"

# update deny_ip file
{
    echo 'location / {'

    echo "# new ${#nad_state[@]} at $_NAD_RUNDATE"
    for i in ${!nad_state[@]}; do

# whitelisted
        if [[ $NAD_WHITE_LIST =~ $i ]]; then
            echo "# whitelisted $i #$_NAD_RUNDATE"
        else
            echo "deny $i #$_NAD_RUNDATE"
        fi
    done

    echo "# old ${#nad_blocked[@]}"
    for i in ${!nad_blocked[@]}; do
    echo "deny $i #${nad_blocked[$i]}"; done

    echo '}'
} > $NAD_DENY_FILE


# reload nginx, try first
/usr/sbin/nginx -tq && {
    service nginx reload \
        && rm -rf $_NAD_LOCK_FILE \
        || nad_report "nad cant reload nginx"
} || {
    nad_report "nad cant check nginx conf"
}
