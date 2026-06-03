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
trap 'rm -rf "$TMP_DIR"; [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null || true' EXIT HUP INT TERM

REQ_DIR="$TMP_DIR/requests"
PORT_FILE="$TMP_DIR/port.txt"
mkdir -p "$REQ_DIR"

python3 "$REPO_DIR/testing/fixtures/http/router_mock.py" --output-dir "$REQ_DIR" --port-file "$PORT_FILE" &
SERVER_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$PORT_FILE" ] && break
    sleep 1
done

assert_file_exists "$PORT_FILE" "router mock publishes a local port"
PORT="$(cat "$PORT_FILE")"

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
cat > "$ROUTER_PAIRING_CACHE_FILE" <<EOF
{"paired":true,"router_ip":"127.0.0.1:$PORT","token":"fixture-token","router_id":"fixture-router"}
EOF

# shellcheck disable=SC1090
. "$REPO_DIR/network/app/pairing_gate.sh"
# shellcheck disable=SC1090
. "$REPO_DIR/network/app/router_channel.sh"

network__router__channel_recommend_request "2g" "1"
assert_rc 0 "$?" "channel recommendation succeeds against local router fixture"
assert_file_exists "$KITSUNPING_CHANNEL_CACHE_DIR/router_channel_response.json" "channel response is stored"

recommended_channel="$(network__router__channel_get_cached recommended_channel)"
score_gap="$(network__router__channel_get_cached score_gap)"
assert_eq 6 "$recommended_channel" "cached recommendation exposes recommended channel"
assert_eq 22 "$score_gap" "cached recommendation exposes score gap"

network__router__channel_has_better_option 15
assert_rc 0 "$?" "better-option helper detects meaningful improvement"

network__router__channel_apply_request "2g" "6"
assert_rc 0 "$?" "channel apply succeeds against local router fixture"
assert_file_contains "$REQ_DIR/router_apply.body.json" '"channel":6' "apply request sends the expected channel"
assert_file_contains "$REQ_DIR/router_apply.headers.txt" 'X-Auth-Token: fixture-token' "apply request sends auth token"
assert_file_contains "$REQ_DIR/last_get_path.txt" '/cgi-bin/router-channel-recommend' "recommendation request hits the expected endpoint"

finish