#!/bin/sh

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) : ;;
    *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac

TEST_DIR=${SCRIPT_PATH%/*}
ROOT_DIR=${TEST_DIR%/*}
REPO_DIR=${ROOT_DIR%/*}

# shellcheck disable=SC1090
. "$ROOT_DIR/lib/test_helpers.sh"

TMP_DIR=$(mktemp -d)
SERVER_PID=""
REQ_DIR=""
PORT_FILE=""
PORT=""

cleanup() {
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

start_mock() {
    label="$1"
    env_cmd="$2"

    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""

    REQ_DIR="$TMP_DIR/requests_$label"
    PORT_FILE="$TMP_DIR/port_$label.txt"
    mkdir -p "$REQ_DIR"

    if [ -n "$env_cmd" ]; then
        sh -c "$env_cmd python3 \"$REPO_DIR/testing/fixtures/http/router_mock.py\" --output-dir \"$REQ_DIR\" --port-file \"$PORT_FILE\"" >/dev/null 2>&1 &
    else
        python3 "$REPO_DIR/testing/fixtures/http/router_mock.py" --output-dir "$REQ_DIR" --port-file "$PORT_FILE" >/dev/null 2>&1 &
    fi
    SERVER_PID=$!

    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -s "$PORT_FILE" ] && break
        sleep 1
    done

    assert_file_exists "$PORT_FILE" "router mock publishes a port ($label)"
    PORT="$(cat "$PORT_FILE")"

    cat > "$ROUTER_PAIRING_CACHE_FILE" <<EOF
{"paired":true,"router_ip":"127.0.0.1:$PORT","token":"fixture-token","router_id":"fixture-router"}
EOF
}

getprop() { printf '%s' ''; }
get_router_paired_flag() { printf '%s' '1'; }
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_debug() { :; }
getenforce() { printf '%s' 'Permissive'; }
setenforce() { return 0; }

MODDIR="$TMP_DIR/moddir"
KITSUNROUTER_ENABLE=1
ROUTER_PAIRING_CACHE_FILE="$TMP_DIR/pairing.json"
KITSUNPING_CHANNEL_CACHE_DIR="$TMP_DIR/channel_cache"
WIFI_IFACE=wlan0
WIFI_SCORE=40

mkdir -p "$MODDIR/cache" "$KITSUNPING_CHANNEL_CACHE_DIR"

# shellcheck disable=SC1090
. "$REPO_DIR/network/app/pairing_gate.sh"
# shellcheck disable=SC1090
. "$REPO_DIR/network/app/router_channel.sh"

start_mock "recommend_http_503" "ROUTER_MOCK_RECOMMEND_STATUS=503"
network__router__channel_recommend_request "2g" "1"
assert_rc 1 "$?" "recommendation fails on HTTP non-2xx"
assert_file_not_exists "$KITSUNPING_CHANNEL_CACHE_DIR/router_channel_response.json" "no response cache is written on HTTP failure"

start_mock "recommend_status_error" "ROUTER_MOCK_RECOMMEND_MODE=status_error"
network__router__channel_recommend_request "2g" "1"
assert_rc 1 "$?" "recommendation fails when router returns status=error"
assert_file_not_exists "$KITSUNPING_CHANNEL_CACHE_DIR/router_channel_response.json" "status=error does not persist recommendation cache"

start_mock "apply_status_error" "ROUTER_MOCK_APPLY_MODE=status_error"
network__router__channel_apply_request "2g" "6"
assert_rc 1 "$?" "channel apply fails on router status=error"
assert_file_contains "$KITSUNPING_CHANNEL_CACHE_DIR/router_channel_apply_response.json" '"reason":"router_error"' "apply error is normalized to router_error reason"

start_mock "apply_http_503" "ROUTER_MOCK_APPLY_STATUS=503"
network__router__channel_apply_request "2g" "6"
assert_rc 1 "$?" "channel apply fails on HTTP non-2xx"
assert_file_contains "$KITSUNPING_CHANNEL_CACHE_DIR/router_channel_apply_response.json" '"reason":"http_post_failed"' "apply HTTP failure is normalized to http_post_failed"

finish
