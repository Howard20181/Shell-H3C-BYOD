#!/bin/bash
trap 'jobs -p | xargs -r kill' EXIT
BasePath=$(
    cd "$(dirname "$0")" || exit 1
    pwd
)
# shellcheck disable=SC1091
. "$BasePath"/autoauth_common.sh || exit 1

if [ ! "$BASH_VERSION" ]; then
    LOG "$TAG" E "Please do not use sh to run this script, just execute it directly" 1>&2
    exit 1
fi

CONF="$BasePath"/user.conf
TAG=$(basename "$0")
MAX_SLEEP_TIME=600
greeting_sleep() {
    if [ "$1" -gt $MAX_SLEEP_TIME ]; then
        set -- $MAX_SLEEP_TIME
        LOG "$TAG" W "Limit maximum sleep time to $1 seconds"
    fi
    LOG "$TAG" D "Sleep $1 seconds"
    sleep "$1" &
    wait
}

if [ -f "$CONF" ]; then
    # shellcheck source=./user.conf
    # shellcheck disable=SC1091
    . "${CONF:?}" || exit 1
    if [ -z "$USERID" ] || [ -z "$PWD" ]; then
        LOG "$TAG" E "PWD or USERID NULL! EXIT!"
        exit
    else
        LOG "$TAG" D "USERID: $USERID"
    fi
else
    LOG "$TAG" E "user.conf not found! EXIT!"
    exit
fi

byodserverip="10.7.0.103"
byodserverhttpport="30004"

SLEEP_TIME="1"
RECONN_COUNT="0"

FATAL_CODES=(
    "63013"
    "63015"
    "63018"
    "63025"
    "63026"
    "63031"
    "63032"
    "63100"
    "63073"
)

get_json_value() {
    echo "$1" | jsonfilter -e "$.$2"
}

SHOULD_STOP() {
    local TIME_STOP1 TIME_STOP2 TIME_CUR
    TIME_STOP1=$(date -d "$(date '+%Y-%m-%d 23:40:00')" +%s)
    TIME_STOP2=$(date -d "$(date '+%Y-%m-%d 07:00:00')" +%s)
    TIME_CUR=$(date +%s)
    if [ "$portServIncludeFailedCode" = "63027" ]; then
        if [ "$TIME_CUR" -gt "$TIME_STOP1" ] || [ "$TIME_CUR" -lt "$TIME_STOP2" ]; then
            if [ $(( TIME_CUR - TIME_STOP1 )) -lt 0 ];then
                SLEEP_TIME=$(( TIME_STOP2 - TIME_CUR ))
            else
                SLEEP_TIME=$(( TIME_STOP2 + 86400 - TIME_CUR ))
            fi
            return 0
        else
            SLEEP_TIME="1"
            return 1
        fi
    else
        return 1
    fi
}

restart_auth() {
    SLEEP_TIME="1"
    RECONN_COUNT=$(( RECONN_COUNT + 1 ))
    if SHOULD_STOP; then
        greeting_sleep $SLEEP_TIME
    else
        SLEEP_TIME=$(( RECONN_COUNT * RECONN_COUNT ))
        greeting_sleep "$SLEEP_TIME"
        LOG "$TAG" N "Reconnecting: $RECONN_COUNT TIME"
    fi
    LOG "$TAG" I "continue"
    start_auth
}

start_auth() {
    LOG "$TAG" I "Start auth"
    local PWD_BASE64 JSON code result
    PWD_BASE64="$(printf "%s" "$PWD" | base64)" # 不使用echo，因为会多个换行符
    appRootUrl="http://$byodserverip:$byodserverhttpport/byod/"
    LOG "$TAG" I "Send Login request"
    JSON=$(curl -s -S ''$appRootUrl'byodrs/login/defaultLogin' \
        -H 'Accept: application/json, text/javascript, */*; q=0.01' \
        -H 'Accept-Language: zh-CN,zh;q=0.9' \
        -H 'Content-Type: application/json' \
        -H 'Origin: http://'$byodserverip':'$byodserverhttpport'' \
        -H 'Referer: '$appRootUrl'view/byod/template/templatePc.html?customId=-1' \
        --data-raw '{"userName":"'"$USERID"'","userPassword":"'"$PWD_BASE64"'","serviceSuffixId":"-1","dynamicPwdAuth":false,"userGroupId":-1,"validationType":2,"guestManagerId":-1}' \
        --insecure)
    wait $!
    LOG "$TAG" D "Login request JSON: $JSON"
    if [ -z "$JSON" ]; then #未收到回应，网络错误
        LOG "$TAG" E "Network error"
        restart_auth
    else #收到回应，可以连接上认证服务器
        code=$(get_json_value "$JSON" code)
        msg=$(get_json_value "$JSON" msg)
        LOG "$TAG" D "code=$code"
        if [ "$code" = "0" ]; then #认证成功
            LOG "$TAG" I "Login Success $(date '+%Y-%m-%d %H:%M:%S')"
            LOG "$TAG" I "$msg"
            mac=$(get_json_value "$JSON" data.byodMacRegistInfo.mac)
            LOG "$TAG" I "mac: $mac"
            unset portServIncludeFailedCode
            SLEEP_TIME=300
        elif [ "$code" = "-1" ]; then #认证失败
            LOG "$TAG" E "$msg"
            data=$(get_json_value "$JSON" data)
            if [ -n "$data" ]; then
                portServIncludeFailedCode=$(printf '%s' "$msg" | cut -c 2-6)
                if [ -n "$portServIncludeFailedCode" ]; then
                    for i in "${FATAL_CODES[@]}"; do
                        if [ "$portServIncludeFailedCode" = "$i" ]; then
                            LOG "$TAG" E "EXIT!"
                            exit 1
                        fi
                    done
                    restart_auth
                fi
            fi
        else
            LOG "$TAG" E "Unknow error. EXIT!"
            exit 1
        fi
    fi
}

start_auth

while true; do
    if ! (NET_AVAILABLE); then
        restart_auth
    else
        RECONN_COUNT="0"
    fi
    greeting_sleep $SLEEP_TIME
done
