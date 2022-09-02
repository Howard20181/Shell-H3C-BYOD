#!/bin/bash
if [ ! "$BASH_VERSION" ]; then
    LOG E "Please do not use sh to run this script, just execute it directly" 1>&2
    exit 1
fi
BasePath=$(
    cd "$(dirname "$0")" || exit 1
    pwd
)
# DEBUG=1
CONF="$BasePath"/user.conf
BaseName=$(basename "$0")
LOG() {
    if [ -n "$2" ]; then
        if [ "$1" == "E" ]; then
            logger -t "$BaseName" -p err "$2"
            echo "Error : $2"
        elif [ "$1" == "I" ]; then
            logger -t "$BaseName" -p info "$2"
            echo "Info  : $2"
        elif [ "$1" == "N" ]; then
            logger -t "$BaseName" -p notice "$2"
            echo "Notice: $2"
        elif [ "$1" == "W" ]; then
            logger -t "$BaseName" -p warn "$2"
            echo "Warn  : $2"
        elif [ -n "$DEBUG" ] && [ "$1" == "D" ]; then
            logger -t "$BaseName" -p debug "$2"
            echo "Debug : $2"
        fi
    else
        logger -t "$BaseName" -p info "$1"
        echo "Info: $1"
    fi
}
if [ -f "$CONF" ]; then
    # shellcheck source=./user.conf
    # shellcheck disable=SC1091
    source "${CONF:?}" || exit 1
    if [ -z "$USERID" ] || [ -z "$PWD" ]; then
        LOG E "PWD or USERID NULL! EXIT!"
        exit
    else
        LOG D "USERID: $USERID"
        LOG D "PWD: $PWD"
    fi
else
    LOG E "user.conf not found! EXIT!"
    exit
fi

byodserverip="10.7.0.103"
byodserverhttpport="30004"

SLEEP_TIME="1"
RECONN_COUNT="0"

get_json_value() {
    echo "$1" | jsonfilter -e "$.$2"
}

SHOULD_STOP() {
    local TIME_STOP1 TIME_STOP2 TIME_CUR
    TIME_STOP1=$(date -d "$(date '+%Y-%m-%d 23:59:59')" +%s)
    TIME_STOP2=$(date -d "$(date '+%Y-%m-%d 07:00:00')" +%s)
    TIME_CUR=$(date +%s)
    if [ "$portServIncludeFailedCode" = "63027" ]; then
        if [ "$TIME_CUR" -gt "$TIME_STOP1" ] || [ "$TIME_CUR" -lt "$TIME_STOP2" ]; then
            return 0
        else
            SLEEP_TIME="1"
            return 1
        fi
    else
        SLEEP_TIME="1"
        return 1
    fi
}

NET_AVAILABLE() {
    if [ "$(curl -sI -w "%{http_code}" -o /dev/null connect.rom.miui.com/generate_204)" = "204" ]; then
        RECONN_COUNT="0"
        return 0
    else
        return 1
    fi
}

restart_auth() {
    RECONN_COUNT=$((RECONN_COUNT + 1))
    SLEEP_TIME=$(( SLEEP_TIME * RECONN_COUNT))
    LOG N "Wait ${SLEEP_TIME}s"
    sleep "$SLEEP_TIME"
    LOG N "Reconnecting: $RECONN_COUNT TIME"
    start_auth
}
start_auth() {
    LOG I "Start auth"
    LOG I "Send Login request"
    local PWD_BASE64 JSON code TIME
    PWD_BASE64="$(printf "%s" "$PWD" | base64)" # 不使用echo，因为会多个换行符
    appRootUrl="http://$byodserverip:$byodserverhttpport/byod/"
    JSON=$(curl -s ''$appRootUrl'byodrs/login/defaultLogin' \
        -H 'Accept: application/json, text/javascript, */*; q=0.01' \
        -H 'Accept-Language: zh-CN,zh;q=0.9' \
        -H 'Content-Type: application/json' \
        -H 'Origin: http://'$byodserverip':'$byodserverhttpport'' \
        -H 'Referer: '$appRootUrl'view/byod/template/templatePc.html?customId=-1' \
        --data-raw '{"userName":"'"$USERID"'","userPassword":"'"$PWD_BASE64"'","serviceSuffixId":"-1","dynamicPwdAuth":false,"userGroupId":-1,"validationType":2,"guestManagerId":-1}' \
        --insecure)

    if [ -z "$JSON" ]; then #未收到回应，网络错误
        LOG E "Network error"
        restart_auth
    else #收到回应，可以连接上认证服务器
        LOG D "JSON: $JSON"
        code=$(get_json_value "$JSON" code)
        msg=$(get_json_value "$JSON" msg)
        LOG D "code=$code"
        if [ "$code" = "0" ]; then #认证成功
            TIME=$(date '+%Y-%m-%d %H:%M:%S')
            LOG I "Login Success $TIME"
            LOG I "$msg"
            mac=$(get_json_value "$JSON" data.byodMacRegistInfo.mac)
            LOG I "mac: $mac"
            unset portServIncludeFailedCode
            SLEEP_TIME=300
        elif [ "$code" = "-1" ]; then #认证失败
            LOG E "$msg"
            data=$(get_json_value "$JSON" data)
            if [ -n "$data" ]; then
                portServIncludeFailedCode=${msg:1:5}
            fi
            if [ -n "$portServIncludeFailedCode" ]; then
                if [ "$portServIncludeFailedCode" = "63013" ] || [ "$portServIncludeFailedCode" = "63015" ] || [ "$portServIncludeFailedCode" = "63018" ] || [ "$portServIncludeFailedCode" = "63025" ] || [ "$portServIncludeFailedCode" = "63026" ] || [ "$portServIncludeFailedCode" = "63031" ] || [ "$portServIncludeFailedCode" = "63032" ] || [ "$portServIncludeFailedCode" = "63100" ] || [ "$portServIncludeFailedCode" = "63073" ]; then
                    LOG E "EXIT!"
                    exit
                fi
                while SHOULD_STOP; do
                    LOG D "sleep ${SLEEP_TIME}s"
                    sleep $SLEEP_TIME
                done
                LOG I "continue"
                restart_auth
            fi
        else
            LOG E "Unknow error. EXIT!"
            exit 1
        fi
    fi
}
start_auth

while true; do
    if ! (NET_AVAILABLE); then
        while SHOULD_STOP; do
            LOG D "sleep ${SLEEP_TIME}s"
            sleep $SLEEP_TIME
        done
        LOG I "continue"
        restart_auth
    fi
    sleep $SLEEP_TIME
done
