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
mkdir -p "$MODDIR/cache" "$MODDIR/logs" "$MODDIR/policy/executor"

cat > "$MODDIR/module.prop" <<'EOF'
id=Kitsunping
name=Kitsunping
version=7.0-beta
versionCode=700
EOF

POLICY_LOG="$MODDIR/logs/policy.log"
DAEMON_STATE_FILE="$MODDIR/cache/daemon.state"
CALIBRATE_SH="$MODDIR/calibration/calibrate.sh"
CALIBRATE_OUT="$MODDIR/logs/results.env"
CALIBRATE_TS_FILE="$MODDIR/cache/calibrate.ts"
CALIBRATE_STATE_FILE="$MODDIR/cache/calibrate.state"
CALIBRATE_STREAK_FILE="$MODDIR/cache/calibrate.streak"
CALIBRATE_POSTPONE_COUNT_FILE="$MODDIR/cache/calibrate.postpone.count"
CALIBRATE_POSTPONE_TS_FILE="$MODDIR/cache/calibrate.postpone.ts"
CURRENT_FILE="$MODDIR/cache/policy.current"
CALIBRATE_LOCK_DIR="$MODDIR/cache/calibrate.lock"
RESETPROP_BIN=""

mkdir -p "$MODDIR/calibration"
cat > "$CALIBRATE_SH" <<'EOF'
calibrate_network_settings() {
    case "${CALIBRATE_TEST_RESULT:-aborted}" in
        completed)
            printf '%s\n' 'BEST_ro_ril_hsupa_category=6'
            return 0
            ;;
        postponed) return 3 ;;
        timed_out) sleep 5 ;;
        *) return 1 ;;
    esac
}
EOF

EPOCH_NOW=0
NOW_EPOCH_SOURCE="unknown"

atomic_write() {
    local dest="$1" tmp
    tmp="${dest}.tmp.$$"
    cat > "$tmp"
    mv "$tmp" "$dest"
}

epoch_now() {
    printf '%s' "$EPOCH_NOW"
}

uint_or_default() {
    local raw="$1" def="$2"
    case "$raw" in
        ''|*[!0-9]*) printf '%s' "$def" ;;
        *) printf '%s' "$raw" ;;
    esac
}

is_epoch_like() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) [ "$1" -ge 1000000000 ] ;;
    esac
}

pick_score_from_state() {
    PICK_SCORE_SOURCE="wifi"
    PICK_SCORE_PREFER="auto"
    PICK_SCORE_TRANSPORT="wifi"
    printf '10'
}

append_prop_failure() { :; }
emit_policy_update_event() { :; }
release_executor_lock() { :; }
log_policy_warn() { log_policy "$*"; }
log_policy_error() { log_policy "$*"; }
log_policy() { printf '%s\n' "$*" >> "$POLICY_LOG"; }
getprop() { printf '0'; }

EVENT_DETAILS=""
EVENT_TS="0"
EVENT_NAME="WIFI_JOINED"
force_calibrate=1
target_profile="stable"
props_applied=0
calibrate_delay=0
calibrate_cooldown=1800
calibrate_low_score=40
calibrate_low_streak_needed=2
settle_window=1800
calibrate_initial_on_boot=0
LOCK_HELD=0
HEAVY_ACTIVITY_LOCK_HELD=0
CALIBRATION_PRIORITY_SET=0
CALIBRATE_FORCE_PRIORITY=0

printf 'idle' > "$CALIBRATE_STATE_FILE"
printf '0' > "$CALIBRATE_TS_FILE"
printf '0' > "$CALIBRATE_STREAK_FILE"
printf '0' > "$CALIBRATE_POSTPONE_COUNT_FILE"
printf '0' > "$CALIBRATE_POSTPONE_TS_FILE"
printf '1700000000' > "$MODDIR/cache/policy.boot.ts"

CALIBRATE_BOOT_GUARD_SEC=1800
CALIBRATE_BOOT_TS_FILE="$MODDIR/cache/policy.boot.ts"
CALIBRATE_INSTALL_MARKER_FILE="$MODDIR/cache/calibrate.install.version"
printf '700' > "$CALIBRATE_INSTALL_MARKER_FILE"

# shellcheck disable=SC1090
. "$REPO_DIR/policy/executor/executor_calibrate.sh"

printf 'running' > "$CALIBRATE_STATE_FILE"
mkdir -p "$CALIBRATE_LOCK_DIR"
printf '999999' > "$CALIBRATE_LOCK_DIR/pid"
recover_stale_calibration_running

recovered_state=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "")
recovered_log=$(cat "$POLICY_LOG" 2>/dev/null || echo "")
assert_eq "idle" "$recovered_state" "stale running calibration is recovered to idle"
assert_file_not_exists "$CALIBRATE_LOCK_DIR" "stale calibration lock is removed"
assert_contains "Calibration interrupted: recovered stale running state" "$recovered_log" "stale calibration recovery is logged"

printf 'idle' > "$CALIBRATE_STATE_FILE"
: > "$POLICY_LOG"

EPOCH_NOW=1700000900
run_calibration_phase

state_after_auto=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "")
ts_after_auto=$(cat "$CALIBRATE_TS_FILE" 2>/dev/null || echo "")
log_after_auto=$(cat "$POLICY_LOG" 2>/dev/null || echo "")

assert_eq "postponed" "$state_after_auto" "boot guard postpones automatic calibration"
assert_eq "0" "$ts_after_auto" "boot guard preserves last actual calibration timestamp"
assert_contains "Boot calibration guard active" "$log_after_auto" "boot guard emits postpone log"
if printf '%s' "$log_after_auto" | grep -Fq "epoch unavailable"; then
    fail "valid epoch timestamp must not be treated as unavailable"
else
    pass "valid epoch timestamp overrides lost source marker"
fi

: > "$POLICY_LOG"
EVENT_NAME="WIFI_JOINED"
force_calibrate=0
EPOCH_NOW=1700001801
run_calibration_phase

state_after_guard_expiry=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "")
log_after_guard_expiry=$(cat "$POLICY_LOG" 2>/dev/null || echo "")
assert_eq "idle" "$state_after_guard_expiry" "expired boot guard returns to normal calibration evaluation"
if printf '%s' "$log_after_guard_expiry" | grep -Fq "Calibration settling"; then
    fail "postponed boot guard must not add a settling cooldown"
else
    pass "postponed boot guard does not add settling cooldown"
fi

: > "$POLICY_LOG"
printf 'idle' > "$CALIBRATE_STATE_FILE"
printf '0' > "$CALIBRATE_TS_FILE"
printf '0' > "$CALIBRATE_STREAK_FILE"
rm -f "$CALIBRATE_INSTALL_MARKER_FILE" 2>/dev/null || true

EVENT_NAME="BOOT_COMPLETED"
force_calibrate=0
EPOCH_NOW=1700000900
run_calibration_phase

state_after_install_bootstrap=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "")
marker_after_install_bootstrap=$(cat "$CALIBRATE_INSTALL_MARKER_FILE" 2>/dev/null || echo "")
log_after_install_bootstrap=$(cat "$POLICY_LOG" 2>/dev/null || echo "")

assert_eq "aborted" "$state_after_install_bootstrap" "failed install bootstrap records aborted outcome"
assert_eq "" "$marker_after_install_bootstrap" "failed install bootstrap keeps version marker pending"
assert_contains "Install/update calibration bootstrap pending" "$log_after_install_bootstrap" "install bootstrap pending log is emitted"
assert_contains "Calibration forced for first boot after install/update" "$log_after_install_bootstrap" "install bootstrap forces calibration"
if printf '%s' "$log_after_install_bootstrap" | grep -Fq "Boot calibration guard active"; then
    fail "install bootstrap should bypass boot guard"
else
    pass "install bootstrap bypasses boot guard"
fi

: > "$POLICY_LOG"
printf 'idle' > "$CALIBRATE_STATE_FILE"
printf '0' > "$CALIBRATE_TS_FILE"
printf '0' > "$CALIBRATE_STREAK_FILE"
CALIBRATE_TEST_RESULT=completed
EVENT_NAME="BOOT_COMPLETED"
force_calibrate=0
EPOCH_NOW=1700000900
run_calibration_phase
CALIBRATE_TEST_RESULT=aborted

marker_after_successful_bootstrap=$(cat "$CALIBRATE_INSTALL_MARKER_FILE" 2>/dev/null || echo "")
state_after_successful_bootstrap=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "")
assert_eq "700" "$marker_after_successful_bootstrap" "successful install bootstrap consumes version marker"
assert_eq "completed" "$state_after_successful_bootstrap" "successful install bootstrap records completed outcome"

: > "$POLICY_LOG"
printf 'idle' > "$CALIBRATE_STATE_FILE"
printf '0' > "$CALIBRATE_TS_FILE"
printf '0' > "$CALIBRATE_STREAK_FILE"

EVENT_NAME="BOOT_COMPLETED"
force_calibrate=0
EPOCH_NOW=1700000900
run_calibration_phase

state_after_second_boot=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "")
log_after_second_boot=$(cat "$POLICY_LOG" 2>/dev/null || echo "")

assert_eq "postponed" "$state_after_second_boot" "after marker is set, boot guard is applied again"
assert_contains "Boot calibration guard active" "$log_after_second_boot" "second boot re-enters boot guard"

: > "$POLICY_LOG"
printf 'idle' > "$CALIBRATE_STATE_FILE"
printf '0' > "$CALIBRATE_TS_FILE"
printf '0' > "$CALIBRATE_STREAK_FILE"
rm -f "$CALIBRATE_BOOT_TS_FILE" 2>/dev/null || true
CALIBRATE_BOOT_UPTIME_SEC=300

EVENT_NAME="WIFI_JOINED"
force_calibrate=0
EPOCH_NOW=1700001200
run_calibration_phase

state_after_boot_ts_fallback=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "")
log_after_boot_ts_fallback=$(cat "$POLICY_LOG" 2>/dev/null || echo "")

assert_eq "postponed" "$state_after_boot_ts_fallback" "missing boot timestamp still enforces boot guard via uptime fallback"
assert_contains "Boot calibration guard recovered boot timestamp from uptime" "$log_after_boot_ts_fallback" "boot timestamp fallback is logged"
assert_contains "Boot calibration guard active" "$log_after_boot_ts_fallback" "boot guard remains active after fallback recovery"
CALIBRATE_BOOT_UPTIME_SEC=0

: > "$POLICY_LOG"
printf 'idle' > "$CALIBRATE_STATE_FILE"
printf '0' > "$CALIBRATE_TS_FILE"
printf '0' > "$CALIBRATE_STREAK_FILE"

EVENT_NAME="user_requested_calibrate"
force_calibrate=1
EPOCH_NOW=1700000900
run_calibration_phase

state_after_manual=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "")
log_after_manual=$(cat "$POLICY_LOG" 2>/dev/null || echo "")

assert_eq "aborted" "$state_after_manual" "manual calibration records aborted outcome"
assert_contains "Calibration forced by user request" "$log_after_manual" "manual calibration logs forced user request"
if printf '%s' "$log_after_manual" | grep -Fq "Boot calibration guard active"; then
    fail "manual calibration should not log boot guard postpone"
else
    pass "manual calibration does not trigger boot guard"
fi

: > "$POLICY_LOG"
printf 'idle' > "$CALIBRATE_STATE_FILE"
printf '0' > "$CALIBRATE_TS_FILE"
CALIBRATE_TEST_RESULT=postponed
EVENT_NAME="user_requested_calibrate"
force_calibrate=1
EPOCH_NOW=1700001900
run_calibration_phase
CALIBRATE_TEST_RESULT=aborted
assert_eq "postponed" "$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "")" "child postpone records postponed outcome"

: > "$POLICY_LOG"
printf 'idle' > "$CALIBRATE_STATE_FILE"
printf '0' > "$CALIBRATE_TS_FILE"
CALIBRATE_TEST_RESULT=timed_out
CALIBRATE_TIMEOUT=1
EVENT_NAME="user_requested_calibrate"
force_calibrate=1
EPOCH_NOW=1700002000
run_calibration_phase
CALIBRATE_TEST_RESULT=aborted
CALIBRATE_TIMEOUT=600
assert_eq "timed_out" "$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "")" "calibration timeout records timed_out outcome"

finish
