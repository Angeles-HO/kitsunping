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

python3 "$REPO_DIR/testing/fixtures/http/router_mock.py" --output-dir "$REQ_DIR" --port-file "$PORT_FILE" >/dev/null 2>&1 &
SERVER_PID=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$PORT_FILE" ] && break
    sleep 1
done

assert_file_exists "$PORT_FILE" "router mock publishes a local port for push cycle"
PORT="$(cat "$PORT_FILE")"

getprop() { printf '%s' ''; }
get_router_paired_flag() { printf '%s' '1'; }
atomic_write() {
    target="$1"
    tmp_file="${target}.tmp"
    cat > "$tmp_file" && mv "$tmp_file" "$target"
}
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_debug() { :; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

MODDIR="$TMP_DIR/moddir"
mkdir -p "$MODDIR/cache"
ROUTER_PAIRING_CACHE_FILE="$TMP_DIR/pairing.json"
KITSUNROUTER_ENABLE=1
ROUTER_STATUS_PUSH_INTERVAL_SEC=15
ROUTER_PUSH_TIMEOUT_SEC=5
KITSUNPING_MODULE_ID=kitsunping

cat > "$ROUTER_PAIRING_CACHE_FILE" <<EOF
{"paired":true,"router_ip":"127.0.0.1:$PORT","token":"fixture-token","router_id":"fixture-router"}
EOF

printf '%s' 'gaming' > "$MODDIR/cache/policy.current"
printf '%s' 'gaming' > "$MODDIR/cache/policy.target"
printf '%s' 'high' > "$MODDIR/cache/policy.priority"
printf '%s' '80' > "$MODDIR/cache/policy.priority.weight"
printf '%s' '32' > "$MODDIR/cache/policy.priority.min_mbit"
printf '%s' 'APP_OVERRIDE' > "$MODDIR/cache/target.state"
printf '%s' 'source=test priority=high' > "$MODDIR/cache/target.state.reason"

wifi_bssid='aa:bb:cc:dd:ee:ff'
wifi_ssid='FixtureWiFi'
wifi_band='5g'
wifi_width='80'
wifi_state='connected'
wifi_score='88'
transport='wifi'
last_event='PROFILE_CHANGED'
WIFI_IFACE='wlan0'

# shellcheck disable=SC1090
. "$REPO_DIR/network/app/state_io.sh"
# shellcheck disable=SC1090
. "$REPO_DIR/network/app/pairing_gate.sh"
# shellcheck disable=SC1090
. "$REPO_DIR/network/app/router_push.sh"

network__app__router_status_push_cycle
assert_file_exists "$MODDIR/cache/router.status.last_push.ts" "router push writes last push timestamp"
assert_file_contains "$REQ_DIR/router_event.body.json" '"event":"MODULE_STATUS"' "router push sends module status payload"
assert_file_contains "$REQ_DIR/router_event.body.json" '"priority_target":"high"' "router push includes priority context"
assert_file_contains "$REQ_DIR/router_event.headers.txt" 'X-Auth-Token: fixture-token' "router push sends auth token"
assert_file_contains "$REQ_DIR/router_event.headers.txt" 'X-KP-KeyId: kitsunping' "router push sends module key id"

first_count="$(cat "$REQ_DIR/event.count")"
network__app__router_status_push_cycle
second_count="$(cat "$REQ_DIR/event.count")"
assert_eq "$first_count" "$second_count" "router push respects rate limiting on immediate second run"

finish