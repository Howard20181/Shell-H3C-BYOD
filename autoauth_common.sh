#!/bin/ash
# shellcheck shell=dash
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

TAG="autoauth"

LOG() {
    if [ -n "$3" ]; then
        case "$2" in
            "I")
                logger -t "$1" -p "info" "$3"
                ;;
            "N")
                logger -t "$1" -p "notice" "$3"
                ;;
            "W")
                logger -t "$1" -p "warn" "$3"
                ;;
            "E")
                logger -t "$1" -p "err" "$3"
                ;;
            "C")
                logger -t "$1" -p "crit" "$3"
                ;;
            "A")
                logger -t "$1" -p "alert" "$3"
                ;;
            "D")
                if [ "$DEBUG" = "1" ]; then
                    logger -t "$1" -p "debug" "$3"
                fi
                ;;
            *)
                logger -t "$1" -p "info" "$3"
                ;;
        esac
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
	if [ -x "/usr/bin/ping" ] && /usr/bin/ping -${IP_FAMILY#ipv} -c1 -q "$(ping_test_host)" > /dev/null 2>&1; then
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
				LOG "$TAG" W "Missing ping. Please enable BUSYBOX_DEFAULT_PING and recompile busybox or install iputils-ping package."
				return 1
			fi
			;;
		curl)
			command -v curl 1>/dev/null 2>&1 || {
				LOG "$TAG" W "Missing curl. Please install curl package."
				return 1
			}
			;;
        *)
            return 1
        ;;
	esac
}

NET_AVAILABLE() {
    case "$net_track_method" in
        ping)
            local result
			WRAP "$PING" -n -c 1 -q $PING_TRACK_IP > /dev/null 2>&1 &
            wait $!
            result=$?
            if [ $result -eq 0 ]; then
                return 0
            else
                return 1
            fi
			;;
        curl)
            if [ "$(curl -sI -w "%{http_code}" -o /dev/null $NET_CHECK_CURL_URL)" = "204" ]; then
                return 0
            else
                return 1
            fi
			;;
    esac
}

validate_track_method "$net_track_method" || {
		net_track_method=curl
		if validate_track_method $net_track_method; then
			LOG "$TAG" W "Using curl to track interface $INTERFACE avaliability"
		else
			LOG "$TAG" E "No track method avaliable"
			exit 1
		fi
}