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

# ping host or curl generate_204
# net_track_method="ping" # ping or curl

# for ping
PING_TRACK_IP="10.7.11.254"
IP_FAMILY="ipv4"
INTERFACE="wan"
DEVICE="wan"

# for curl
NET_CHECK_CURL_URL="https://connect.rom.miui.com/generate_204"

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

# ported from mwan3track
WRAP() {
	# shellcheck disable=SC2048
	FAMILY=$IP_FAMILY DEVICE=$DEVICE $*
}
ping_test_host() {
	if [ "$IP_FAMILY" = "ipv6" ]; then
		echo "::1"
	else
		echo "127.0.0.1"
	fi
}
get_ping_command() {
	if [ -x "/usr/bin/ping" ] && /usr/bin/ping -${IP_FAMILY#ipv} -c1 -q "$(ping_test_host)" &>/dev/null; then
		# -4 option added in iputils c3e68ac6 so need to check if we can use it
		# or if we must use ping and ping6
		echo "/usr/bin/ping -${IP_FAMILY#ipv}"
	elif [ "$IP_FAMILY" = "ipv6" ] && [ -x "/usr/bin/ping6" ]; then
		echo "/usr/bin/ping6"
	elif [ "$IP_FAMILY" = "ipv4" ] && [ -x "/usr/bin/ping" ]; then
		echo "/usr/bin/ping"
	elif [ -x "/bin/ping" ]; then
		echo "/bin/ping -${IP_FAMILY#ipv}"
	else
		return 1
	fi
}
validate_track_method() {
	case "$1" in
		ping)
			if ! PING=$(get_ping_command); then
				LOG W "Missing ping. Please enable BUSYBOX_DEFAULT_PING and recompile busybox or install iputils-ping package."
				return 1
			fi
			;;
		curl)
			command -v curl 1>/dev/null 2>&1 || {
				LOG W "Missing curl. Please install curl package."
				return 1
			}
			;;
	esac
}

NET_AVAILABLE() {
    case "$net_track_method" in
        ping)
			WRAP "$PING" -n -c 1 -q $PING_TRACK_IP &> /dev/null &
            wait $!
            result=$?
            if [ $result -eq 0 ]; then
                RECONN_COUNT="0"
                return 0
            else
                return 1
            fi
			;;
        curl)
            if [ "$(curl -sI -w "%{http_code}" -o /dev/null $NET_CHECK_CURL_URL)" = "204" ]; then
                RECONN_COUNT="0"
                return 0
            else
                return 1
            fi
			;;
    esac
}

restart_auth() {
    RECONN_COUNT=$(( RECONN_COUNT + 1 ))
    if SHOULD_STOP; then
        LOG N "sleep ${SLEEP_TIME}s"
        sleep $SLEEP_TIME
    else
        SLEEP_TIME=$(( SLEEP_TIME * RECONN_COUNT ))
        LOG N "Wait ${SLEEP_TIME}s"
        sleep "$SLEEP_TIME"
        LOG N "Reconnecting: $RECONN_COUNT TIME"
    fi
    LOG I "continue"
    start_auth
}

start_auth() {
    LOG I "Start auth"
    local PWD_BASE64 JSON code
    PWD_BASE64="$(printf "%s" "$PWD" | base64)" # 不使用echo，因为会多个换行符
    appRootUrl="http://$byodserverip:$byodserverhttpport/byod/"
    LOG I "Send Login request"
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
            LOG I "Login Success $(date '+%Y-%m-%d %H:%M:%S')"
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
                if [ -n "$portServIncludeFailedCode" ]; then
                    for i in "${FATAL_CODES[@]}"; do
                        if [ "$portServIncludeFailedCode" = "$i" ]; then
                            LOG E "EXIT!"
                            exit 1
                        fi
                    done
                    restart_auth
                fi
            fi
        else
            LOG E "Unknow error. EXIT!"
            exit 1
        fi
    fi
}
validate_track_method "$net_track_method" || {
		net_track_method=curl
		if validate_track_method $net_track_method; then
			LOG W "Using curl to track interface $INTERFACE avaliability"
		else
			LOG E "No track method avaliable"
			exit 1
		fi
	}
start_auth

while true; do
    if ! (NET_AVAILABLE); then
        restart_auth
    fi
    sleep $SLEEP_TIME
done
