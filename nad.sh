#!/bin/env bash

set -e

export NAD_TESTING=true # dont restart nginx (default)
export NAD_WHITE_LIST='43.142.47.190'
export NAD_LOG_FILE='access_log'
export NAD_LOG_TAIL=1000
export NAD_MAX_REQUESTS=200
export NAD_REPORT_NAME='my_website'
export NAD_REPORT_MAX_REQUESTS=200
export NAD_COOLDOWN=57 # three seconds less
export NAD_LOG_GREP="grep -e '$(date '+%d/%b/%Y:%H:%M')' -e '$(date -d 'minute ago' '+%d/%b/%Y:%H:%M')'"

export NAD_DENY_FILE='nad_deny_ip.conf'
export NAD_DENY_PAGE='#error_page 403 http://example.com/forbidden.html;'

############################## define report function
nad_report(){ echo "$1"; }

_NAD_RUNDATE=$(date +%s)
_NAD_RUNDATE_H=$(date -d@$_NAD_RUNDATE '+%d/%b/%Y:%H:%M:%S')
_NAD_LOCK_FILE="/var/lock/nad"

[ -e /etc/nad.conf ] && source /etc/nad.conf
[ -e $_NAD_LOCK_FILE ] && { nad_report "locked $(cat $_NAD_LOCK_FILE)"; exit 1; }

echo $_NAD_RUNDATE > $_NAD_LOCK_FILE

############################## list blocked
[ -e $NAD_DENY_FILE ] || { touch $NAD_DENY_FILE; }
eval "declare -A nad_old=(
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
    eval "declare -A nad_new=(
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
                    [ "${nad_old[$_ip]+abc}" ] && continue

                    echo "[$_ip]=$_number"
                done
        } | sort )
    )"
fi

############################## update deny_ip file
{
    echo 'location / {'
    echo "# run $_NAD_RUNDATE_H"
    echo "# max $NAD_MAX_REQUESTS cooldown $NAD_COOLDOWN"
    echo "#"
    echo "$NAD_DENY_PAGE"
    echo "#"

    echo "# new $((${#nad_new[@]}/2))"
    for i in ${!nad_new[@]}; do

# comment whitelisted
        if [[ $NAD_WHITE_LIST =~ $i ]]; then
            echo "# whitelisted $i #$_NAD_RUNDATE ${nad_new[$i]}"
        else
            echo "deny $i #$_NAD_RUNDATE ${nad_new[$i]}"

# add ip to report
            _NAD_REPORT="${_NAD_REPORT:+"$_NAD_REPORT "}$i:${nad_new[$i]}"
        fi
    done

    echo "#"
    echo "# old $((${#nad_old[@]}/2))"
    for i in ${!nad_old[@]}; do
        if [[ ${i:0:1} == "_" ]]; then continue; fi
        echo "    deny $i #${nad_old[$i]} ${nad_old[_$i]}"
    done

    echo '}'
} > $NAD_DENY_FILE


############################## reload nginx, try first
[ ! $NAD_TESTING ] && {
    /usr/sbin/nginx -tq && {
        service nginx reload \
            || nad_report "cant reload nginx"
    } || {
        nad_report "cant check nginx conf"
    }
}

[ "x$_NAD_REPORT" == "x"  ] || { nad_report "$NAD_REPORT_NAME" "$_NAD_REPORT"; }

rm -rf $_NAD_LOCK_FILE
