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

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

MODDIR="$TMP_ROOT/mod"
mkdir -p "$MODDIR/cache" "$MODDIR/logs"

EVENT_CAPTURE="$TMP_ROOT/event.txt"

atomic_write() {
    local dest="$1" tmp
    tmp="${dest}.tmp.$$"
    cat > "$tmp"
    mv "$tmp" "$dest"
}

get_signal_quality() {
    printf '%s' '{"quality_score":45,"rsrp_dbm":-95,"sinr_db":-5}'
}

jq_stub() {
    case "$2" in
        'try .quality_score // empty') printf '%s' '45' ;;
        'try .rsrp_dbm // empty') printf '%s' '-95' ;;
        'try .sinr_db // empty') printf '%s' '-5' ;;
        *) printf '%s' '' ;;
    esac
}

score_rsrp_cached() {
    printf '%s' '40'
}

score_sinr_cached() {
    printf '%s' '30.00'
}

composite_ema() {
    printf '%s' "$1"
}

decide_profile() {
    printf '%s' 'speed'
}

emit_event() {
    printf '%s|%s\n' "$1" "$2" > "$EVENT_CAPTURE"
}

log_info() { :; }
log_debug() { :; }

transport="mobile"
signal_loop_count=0
SIGNAL_POLL_INTERVAL=1
JQ_BIN="jq_stub"
mobile_score=80
LCL_ALPHA=0.4
LCL_BETA=0.3
LCL_GAMMA=0.3
LCL_DELTA=0
POLICY_DIR="$TMP_ROOT/no_policy"
wifi_path_reason=""
EV_SIGNAL_DEGRADED="SIGNAL_DEGRADED"

# shellcheck disable=SC1090
. "$REPO_DIR/network/mobile/cycle.sh"

network__mobile__transport_cycle

auto_profile=$(cat "$MODDIR/cache/policy.auto_request" 2>/dev/null || echo "")
assert_eq "speed" "$auto_profile" "mobile selector publishes automatic profile candidate"
assert_file_not_exists "$MODDIR/cache/policy.request" "mobile selector does not write shared profile intent"
assert_file_not_exists "$EVENT_CAPTURE" "mobile selector does not emit profile command directly"

finish
