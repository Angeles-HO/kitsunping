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
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

getprop() {
    case "$1" in
        persist.kitsunping.daemon.adaptive_sampling|kitsunping.daemon.adaptive_sampling) printf '%s' "${TEST_ADAPTIVE_SAMPLING:-1}" ;;
        persist.kitsunping.daemon.adaptive_base_sec|kitsunping.daemon.adaptive_base_sec) printf '%s' "${TEST_ADAPTIVE_BASE:-30}" ;;
        persist.kitsunping.daemon.adaptive_degraded_sec|kitsunping.daemon.adaptive_degraded_sec) printf '%s' "${TEST_ADAPTIVE_DEGRADED:-8}" ;;
        persist.kitsunping.daemon.adaptive_bad_streak|kitsunping.daemon.adaptive_bad_streak) printf '%s' "${TEST_ADAPTIVE_BAD_STREAK:-1}" ;;
        persist.kitsunping.daemon.adaptive_good_streak|kitsunping.daemon.adaptive_good_streak) printf '%s' "${TEST_ADAPTIVE_GOOD_STREAK:-1}" ;;
        *) printf '%s' '' ;;
    esac
}

uint_or_default() {
    raw="$1"
    def="$2"
    case "$raw" in
        ''|*[!0-9]*) printf '%s' "$def" ;;
        *) printf '%s' "$raw" ;;
    esac
}

# shellcheck disable=SC1090
. "$REPO_DIR/addon/functions/daemon_adaptive_sampling.sh"

TEST_ADAPTIVE_SAMPLING=1
TEST_ADAPTIVE_BASE=30
TEST_ADAPTIVE_DEGRADED=8
TEST_ADAPTIVE_BAD_STREAK=1
TEST_ADAPTIVE_GOOD_STREAK=1
INTERVAL=10

daemon_adaptive_sampling_init
WIFI_IFACE=wlan0
wifi_state=disconnected
interval_file="$TMP_DIR/adaptive_interval.txt"
daemon_sampling_pick_interval 10 > "$interval_file"
interval_result="$(cat "$interval_file")"
assert_eq 8 "$interval_result" "adaptive sampling degrades interval when Wi-Fi is disconnected"
assert_eq degraded "$DAEMON_SAMPLE_MODE" "adaptive sampling enters degraded mode"
assert_eq wifi_not_connected "$DAEMON_SAMPLE_REASON" "adaptive sampling records disconnection reason"

wifi_state=connected
wifi_quality_reason=good
wifi_score=90
wifi_latency_ms=20
wifi_jitter_ms=4
wifi_loss_pct=0
wifi_loss_trend_pct=+0
wifi_probe_ok=1
daemon_sampling_pick_interval 10 > "$interval_file"
interval_result="$(cat "$interval_file")"
assert_eq 30 "$interval_result" "adaptive sampling returns to base interval on healthy Wi-Fi"
assert_eq base "$DAEMON_SAMPLE_MODE" "adaptive sampling returns to base mode"

TEST_ADAPTIVE_SAMPLING=0
daemon_adaptive_sampling_init
daemon_sampling_pick_interval 12 > "$interval_file"
interval_result="$(cat "$interval_file")"
assert_eq 12 "$interval_result" "adaptive-off mode keeps caller interval"
assert_eq fixed "$DAEMON_SAMPLE_MODE" "adaptive-off mode reports fixed sampling"
assert_eq adaptive_off "$DAEMON_SAMPLE_REASON" "adaptive-off mode exposes reason"

rm -f "$interval_file"

finish