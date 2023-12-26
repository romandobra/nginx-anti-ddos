#!/bin/env bash

set -e

export NAD_TESTING=true # dont restart nginx (default)
export NAD_WHITE_LIST='43.142.47.190'
export NAD_LOG_FILE='access_log'
export NAD_LOG_TAIL=1000
export NAD_MAX_REQUESTS=200
export NAD_COOLDOWN=59
export NAD_LOG_GREP="grep -e '$(date '+%d/%b/%Y:%H:%M')' -e '$(date -d 'minute ago' '+%d/%b/%Y:%H:%M')'"

export NAD_DENY_FILE='nad_deny_ip.conf'
export NAD_DENY_PAGE='#error_page 403 http://example.com/forbidden.html;'

############################## define report function
nad_report(){ echo "$1"; }

_NAD_RUNDATE=$(date +%s)
_NAD_LOCK_FILE="/var/lock/nad"

[ -e /etc/nad.conf ] && source /etc/nad.conf
[ -e $_NAD_LOCK_FILE ] && { nad_report "locked $(cat $_NAD_LOCK_FILE)"; exit 1; }

echo $_NAD_RUNDATE > $_NAD_LOCK_FILE

############################## list blocked
[ -e $NAD_DENY_FILE ] || { touch $NAD_DENY_FILE; }
eval "declare -A nad_blocked=(
    $(
        {
        cat $NAD_DENY_FILE \
        | grep -w deny \
        | while read _deny_word _ip _date _number
            do
                _date=(${_date//[^[:alnum:]]/})

# skip if cooldown is over
                if [ $(( $_NAD_RUNDATE - $_date )) -gt $NAD_COOLDOWN ]; then continue; fi

                echo "[${_ip%;}]=$_date"
                echo "[_${_ip%;}]=$_number"
            done
    } | sort
    )
)"

############################## list new requests
# count log lines
_NAD_LOG_COUNT=($(wc -l $NAD_LOG_FILE | cut -d' ' -f1))

if [ $_NAD_LOG_COUNT -gt $NAD_LOG_TAIL ]; then
    eval "declare -A nad_state=(
        $({
        tail -n$NAD_LOG_TAIL $NAD_LOG_FILE \
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

                    echo "[$_ip]=$_number"
                done
        } | sort )
    )"
fi

############################## update deny_ip file
{
    echo 'location / {'

    echo "$NAD_DENY_PAGE"

    echo "# new $((${#nad_state[@]}/2)) [+1] at $_NAD_RUNDATE"
    for i in ${!nad_state[@]}; do

# comment whitelisted
        if [[ $NAD_WHITE_LIST =~ $i ]]; then
            echo "# whitelisted $i #$_NAD_RUNDATE"
        else
            echo "    deny $i #$_NAD_RUNDATE ${nad_state[$i]}"
        fi
    done

    echo "# old $((${#nad_blocked[@]}/2)) [+1]"
    for i in ${!nad_blocked[@]}; do
        if [[ ${i:0:1} == "_" ]]; then continue; fi
        echo "    deny $i #${nad_blocked[$i]} ${nad_blocked[_$i]}"
    done

    echo '}'
} > $NAD_DENY_FILE


############################## reload nginx, try first
[ ! $NAD_TESTING ] && {
    /usr/sbin/nginx -tq && {
        service nginx reload \
            && rm -rf $_NAD_LOCK_FILE \
            || nad_report "nad cant reload nginx"
    } || {
        nad_report "nad cant check nginx conf"
    }
} || rm -rf $_NAD_LOCK_FILE
