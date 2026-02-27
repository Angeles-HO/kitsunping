#!/system/bin/sh
# executor.sh - executes network profile changes
# Part of Kitsunping - daemon.sh
# DONE: Refactor common functions with daemon.sh into shared helpers
# DONE: Improve logging consistency with daemon.sh
# DONE: Move atomic_write/command detection/now_epoch to shared helper sourced by daemon/executor/policy
# DONE: Refine pick_score to prefer wifi vs mobile based on transport/event and handle missing daemon.state explicitly
# DONE: Add concurrency guard (lock/PID) to prevent overlapping calibrations
# DONE: Validate time source before gating/emitting and define fallback when date returns 0
# Note: now_ts is checked for 0 and gating logic skips calibrate if invalid; fallback and warnings are logged.
# DONE: Surface per-prop failures from apply_network_optimizations/resetprop in policy.event.json
# DONE: Document cooldown/low-streak tunables (and per-profile overrides) in README and expose via env
# DONE: Keep APK JSON schema/timestamps (epoch seconds) documented with minimal fields applied_profile/props_applied/calibrate_state/ts
# DONE: Explain debounce vs INTERVAL coupling (daemon) and consider fractional debounce
# FIX: ensure calibration gating/JSON keep epoch seconds (do not mix /proc/uptime) to stay compatible with daemon/network_policy
SCRIPT_DIR="${0%/*}"            # kitsunping/addon/policy
ADDON_DIR="${SCRIPT_DIR%/policy}"  # kitsunping/addon
MODDIR="${ADDON_DIR%/addon}"     # kitsunping (root of the module)
 
# Allows override from daemon (passed via environment)
[ -n "${LOG_DIR:-}" ] || LOG_DIR="$MODDIR/logs"
[ -n "${POLICY_LOG:-}" ] || POLICY_LOG="$LOG_DIR/policy.log"
[ -n "${SERVICES_LOGS:-}" ] || SERVICES_LOGS="$LOG_DIR/services_daemon.log"
export SERVICES_LOGS

TARGET_FILE="$MODDIR/cache/policy.target"
CURRENT_FILE="$MODDIR/cache/policy.current"
REQUEST_FILE="$MODDIR/cache/policy.request"
SRD_ERRORS="$MODDIR/addon/functions/debug/shared_errors.sh"
KITSUTILS_SH="$MODDIR/addon/functions/utils/Kitsutils.sh"
CORE_SH="$MODDIR/addon/functions/core.sh"
POLICY_COMMON_SH="$MODDIR/addon/functions/policy_common.sh"
CALIBRATE_SH="$MODDIR/addon/Net_Calibrate/calibrate.sh"
CALIBRATE_OUT="$MODDIR/logs/results.env"
POLICY_EVENT_JSON="$MODDIR/cache/policy.event.json"
CALIBRATE_STATE_FILE="$MODDIR/cache/calibrate.state"
CALIBRATE_TS_FILE="$MODDIR/cache/calibrate.ts"
CALIBRATE_STREAK_FILE="$MODDIR/cache/calibrate.streak"
CALIBRATE_POSTPONE_COUNT_FILE="$MODDIR/cache/calibrate.postpone.count"
CALIBRATE_POSTPONE_TS_FILE="$MODDIR/cache/calibrate.postpone.ts"
DAEMON_STATE_FILE="$MODDIR/cache/daemon.state"

mkdir -p "$LOG_DIR" 2>/dev/null
: >> "$POLICY_LOG" 2>/dev/null

EXECUTOR_LOCK_DIR="${EXECUTOR_LOCK_DIR:-$MODDIR/cache/executor.lock}"
EXECUTOR_LOCK_HELD=0

release_executor_lock() {
    [ "$EXECUTOR_LOCK_HELD" -eq 1 ] || return 0
    rm -rf "$EXECUTOR_LOCK_DIR" 2>/dev/null || true
    EXECUTOR_LOCK_HELD=0
}

acquire_executor_lock() {
    local pidfile="$EXECUTOR_LOCK_DIR/pid" old_pid=""

    if mkdir "$EXECUTOR_LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$pidfile" 2>/dev/null || true
        EXECUTOR_LOCK_HELD=1
        return 0
    fi

    if [ -f "$pidfile" ]; then
        old_pid="$(cat "$pidfile" 2>/dev/null)"
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            return 1
        fi
    fi

    rm -rf "$EXECUTOR_LOCK_DIR" 2>/dev/null || true
    if mkdir "$EXECUTOR_LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$pidfile" 2>/dev/null || true
        EXECUTOR_LOCK_HELD=1
        return 0
    fi

    return 1
}

if ! acquire_executor_lock; then
    printf '[%s][POLICY] Skip: executor already running (event=%s details=%s)\n' "$(date +%s)" "${EVENT_NAME:-}" "${EVENT_DETAILS:-}" >> "$POLICY_LOG"
    exit 0
fi
trap 'release_executor_lock' EXIT INT TERM

# Shared helpers
if [ -f "$CORE_SH" ]; then
    . "$CORE_SH"
fi

if [ -f "$POLICY_COMMON_SH" ]; then
    . "$POLICY_COMMON_SH"
fi

# Policy loggers (stable format, independent from sourced helpers)
log_policy() {
    printf '[POLICY][INFO] %s\n' "$*" >> "$POLICY_LOG"
}
log_policy_warn() {
    printf '[POLICY][WARN] %s\n' "$*" >> "$POLICY_LOG"
}
log_policy_error() {
    printf '[POLICY][ERROR] %s\n' "$*" >> "$POLICY_LOG"
}

command -v uint_or_default >/dev/null 2>&1 || uint_or_default() {
    local raw="$1" def="$2"
    case "$raw" in
        ''|*[!0-9]*) printf '%s' "$def" ;;
        *) printf '%s' "$raw" ;;
    esac
}

# Prefer Kitsutils logging if available
if [ -f "$SRD_ERRORS" ]; then
    . "$SRD_ERRORS"
fi

if [ -f "$KITSUTILS_SH" ]; then
    . "$KITSUTILS_SH"
fi

# Detect resetprop
RESETPROP_BIN=""
if command_exists resetprop; then
    RESETPROP_BIN="$(command -v resetprop 2>/dev/null)"
    #log_policy "resetprop resolved to $RESETPROP_BIN"
fi

# Load functions without executing main flow
. "$SCRIPT_DIR/profile_runner.sh" >>"$POLICY_LOG" 2>&1

# If daemon passed event via env, log it (not essential, but useful for logs)
if [ -n "${EVENT_NAME:-}" ]; then
    log_policy "ctx EVENT_NAME=${EVENT_NAME} EVENT_TS=${EVENT_TS:-} DETAILS=${EVENT_DETAILS:-}"
fi

force_reapply_raw="${FORCE_REAPPLY:-0}"
force_reapply=0
case "$force_reapply_raw" in
    1|true|TRUE|yes|YES|on|ON) force_reapply=1 ;;
esac

force_calibrate_raw="${FORCE_CALIBRATE:-0}"
force_calibrate=0
case "$force_calibrate_raw" in
    1|true|TRUE|yes|YES|on|ON) force_calibrate=1 ;;
esac

if [ "${EVENT_NAME:-}" = "user_requested_restart" ]; then
    force_reapply=1
fi

if [ "${EVENT_NAME:-}" = "user_requested_calibrate" ]; then
    force_calibrate=1
fi

# Determine desired target profile.
desired_profile="${TARGET_PROFILE:-}"

# Prefer PROFILE_CHANGED event details when present (expected: "from=x to=y ...").
if [ -z "$desired_profile" ] && [ "${EVENT_NAME:-}" = "PROFILE_CHANGED" ] && [ -n "${EVENT_DETAILS:-}" ]; then
    desired_profile=$(printf '%s' "${EVENT_DETAILS}" | sed -n 's/.*\bto=\([^ ]*\).*/\1/p')
fi

# Otherwise, use existing target file.
if [ -z "$desired_profile" ] && [ -f "$TARGET_FILE" ]; then
    desired_profile="$(cat "$TARGET_FILE" 2>/dev/null)"
fi

# Fallback: if only policy.request exists, treat it as the desired target.
if [ -z "$desired_profile" ] && [ -f "$REQUEST_FILE" ]; then
    desired_profile="$(cat "$REQUEST_FILE" 2>/dev/null)"
    [ -n "$desired_profile" ] && log_policy "Using policy.request as target_profile=$desired_profile"
fi

# User restart can force a re-apply of the currently active profile.
if [ -z "$desired_profile" ] && [ "$force_reapply" -eq 1 ] && [ -f "$CURRENT_FILE" ]; then
    desired_profile="$(cat "$CURRENT_FILE" 2>/dev/null)"
    [ -n "$desired_profile" ] && log_policy "Using policy.current as target_profile=$desired_profile (forced reapply)"
fi

if [ -z "$desired_profile" ]; then
    log_policy "No target profile; nothing to do"
    exit 0
fi

# Persist target (single-writer) and use it for this run.
printf '%s' "$desired_profile" | atomic_write "$TARGET_FILE" || true
target_profile="$desired_profile"

# Validate target profile
[ -z "$target_profile" ] && exit 0

current_profile=""
[ -f "$CURRENT_FILE" ] && current_profile="$(cat "$CURRENT_FILE" 2>/dev/null)"

skip_profile_apply=0

if [ "$target_profile" = "$current_profile" ] && [ "$force_reapply" -ne 1 ]; then
    if [ "$force_calibrate" -eq 1 ]; then
        log_policy "Profile unchanged ($target_profile); forced calibrate requested"
        skip_profile_apply=1
    else
        log_policy "Profile unchanged ($target_profile)"
        exit 0
    fi
fi

if [ "$target_profile" = "$current_profile" ] && [ "$force_reapply" -eq 1 ]; then
    log_policy "Forced reapply requested for profile ($target_profile)"
fi

applied_profile=0
props_applied=0
props_failed=0
props_failed_json=""
props_failed_keys=""

append_prop_failure() {
    local prop_key="$1" esc_key
    [ -n "$prop_key" ] || return 0

    case ",$props_failed_keys," in
        *,"$prop_key",*) return 0 ;;
    esac

    props_failed_keys="${props_failed_keys}${props_failed_keys:+,}$prop_key"
    props_failed=$((props_failed + 1))

    esc_key=$(printf '%s' "$prop_key" | sed 's/\\/\\\\/g; s/"/\\"/g')
    props_failed_json="${props_failed_json}${props_failed_json:+,}\"$esc_key\""
    return 0
}

log_line_count() {
    wc -l < "$POLICY_LOG" 2>/dev/null | tr -d '[:space:]'
}

collect_resetprop_failures_from_log() {
    local start_line="$1"
    [ -f "$POLICY_LOG" ] || return 0
    case "$start_line" in
        ''|*[!0-9]*) start_line=0 ;;
    esac

    awk -v start="$start_line" '
        NR > start {
            if ($0 ~ /resetprop failed: /) {
                line=$0
                sub(/^.*resetprop failed: /, "", line)
                sub(/=.*/, "", line)
                if (line != "") print line
            }
            if ($0 ~ /resetprop failed for /) {
                line=$0
                sub(/^.*resetprop failed for /, "", line)
                sub(/[[:space:]].*$/, "", line)
                if (line != "") print line
            }
            if ($0 ~ /resetprop missing; skipping /) {
                line=$0
                sub(/^.*resetprop missing; skipping /, "", line)
                sub(/[[:space:]].*$/, "", line)
                if (line != "") print line
            }
        }
    ' "$POLICY_LOG" | while IFS= read -r failed_prop; do
        append_prop_failure "$failed_prop"
    done
}

if [ "$skip_profile_apply" -eq 0 ]; then
    log_policy "Switching profile: $current_profile -> $target_profile"

    # Apply profile: prefer net_profiles scripts via run_profile_script.
    if command -v run_profile_script >/dev/null 2>&1; then
        log_policy "Applying profile script: $target_profile"
        if run_profile_script "$target_profile" >> "$POLICY_LOG" 2>&1; then
            applied_profile=1
            printf '%s' "$target_profile" | atomic_write "$CURRENT_FILE" || true
        else
            log_policy_error "run_profile_script failed"
        fi
    elif command -v apply_network_optimizations >/dev/null 2>&1; then
        # Back-compat fallback
        log_policy "Applying built-in profile: $target_profile"
        if apply_network_optimizations "$target_profile" >> "$POLICY_LOG" 2>&1; then
            applied_profile=1
            printf '%s' "$target_profile" | atomic_write "$CURRENT_FILE" || true
        else
            log_policy_error "apply_network_optimizations failed"
            append_prop_failure "apply_network_optimizations"
        fi
    else
        log_policy_error "No profile applier available (missing run_profile_script/apply_network_optimizations)"
    fi
else
    log_policy "Skipping profile reapply; calibration path only"
fi

if [ "$applied_profile" -eq 1 ]; then
    if command -v apply_qcom_wcnss_profile >/dev/null 2>&1; then
        if apply_qcom_wcnss_profile "$MODDIR" "$target_profile" "$POLICY_LOG"; then
            log_policy "Applied Qualcomm WCNSS profile sync: $target_profile"
        else
            log_policy_warn "Failed Qualcomm WCNSS profile sync: $target_profile"
        fi
    else
        log_policy_warn "apply_qcom_wcnss_profile not available"
    fi

    if command -v apply_profile_runtime_resetprops >/dev/null 2>&1; then
        runtime_resetprop_log_start=$(log_line_count)
        if apply_profile_runtime_resetprops "$target_profile" "$POLICY_LOG"; then
            log_policy "Applied runtime resetprops for profile: $target_profile"
        else
            log_policy_warn "Runtime resetprops were not applied for profile: $target_profile"
        fi
        collect_resetprop_failures_from_log "$runtime_resetprop_log_start"
    else
        log_policy_warn "apply_profile_runtime_resetprops not available"
    fi
fi

# calibrate policy: gated by cooldown + low-score streak
calibrate_delay="${CALIBRATE_DELAY:-10}"
calibrate_cooldown="${CALIBRATE_COOLDOWN:-1800}"
calibrate_low_score="${CALIBRATE_SCORE_LOW:-40}"
calibrate_low_streak_needed="${CALIBRATE_LOW_STREAK:-2}"
settle_window="$calibrate_cooldown"
calibrate_initial_on_boot_raw="${CALIBRATE_INITIAL_ON_BOOT:-0}"
calibrate_initial_on_boot=0
case "$calibrate_initial_on_boot_raw" in
    1|true|TRUE|yes|YES|on|ON) calibrate_initial_on_boot=1 ;;
esac
CALIBRATE_LOCK_DIR="${CALIBRATE_LOCK_DIR:-$MODDIR/cache/calibrate.lock}"
LOCK_HELD=0
LOCK_TRAP_SET=0
HEAVY_ACTIVITY_LOCK_HELD=0
CALIBRATION_PRIORITY_SET=0
CALIBRATE_FORCE_PRIORITY=0

acquire_calibrate_lock() {
    local pidfile="$CALIBRATE_LOCK_DIR/pid" old_pid

    if mkdir "$CALIBRATE_LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$pidfile" 2>/dev/null || true
        return 0
    fi

    if [ -f "$pidfile" ]; then
        old_pid=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            return 1
        fi
    fi

    rm -rf "$CALIBRATE_LOCK_DIR" 2>/dev/null
    if mkdir "$CALIBRATE_LOCK_DIR" 2>/dev/null; then
        echo "$$" > "$pidfile" 2>/dev/null || true
        return 0
    fi
    return 1
}

release_calibrate_lock() {
    rm -rf "$CALIBRATE_LOCK_DIR" 2>/dev/null
}

set_lock_trap() {
    local existing
    existing=$(trap -p EXIT | awk -F"'" '{print $2}')
    if [ -n "$existing" ]; then
        trap "$existing; release_calibrate_lock" EXIT
    else
        trap "release_calibrate_lock" EXIT
    fi
    LOCK_TRAP_SET=1
}

read_uint_file() {
    local file="$1" value
    [ -f "$file" ] || { printf '%s' 0; return 0; }
    value=$(cat "$file" 2>/dev/null)
    case "$value" in ''|*[!0-9]*) value=0 ;; esac
    printf '%s' "$value"
}

record_calibration_postpone() {
    local reason="$1" now count first_ts age
    now=$(epoch_now)
    count=$(read_uint_file "$CALIBRATE_POSTPONE_COUNT_FILE")
    first_ts=$(read_uint_file "$CALIBRATE_POSTPONE_TS_FILE")

    count=$((count + 1))
    [ "$first_ts" -gt 0 ] || first_ts="$now"
    age=$((now - first_ts))
    [ "$age" -lt 0 ] && age=0

    printf '%s' "$count" | atomic_write "$CALIBRATE_POSTPONE_COUNT_FILE"
    printf '%s' "$first_ts" | atomic_write "$CALIBRATE_POSTPONE_TS_FILE"
    printf '%s' "$now" | atomic_write "$CALIBRATE_TS_FILE"
    echo "postponed" | atomic_write "$CALIBRATE_STATE_FILE"

    log_policy "Calibration postponed: $reason (count=$count age=${age}s)"
}

clear_calibration_postpone_tracker() {
    echo 0 | atomic_write "$CALIBRATE_POSTPONE_COUNT_FILE"
    echo 0 | atomic_write "$CALIBRATE_POSTPONE_TS_FILE"
}

# --- calibrate gating logic ---
run_calibrate=0
now_ts=$(epoch_now)
now_ts="$(uint_or_default "$now_ts" "0")"
if [ "${NOW_EPOCH_SOURCE:-unknown}" != "epoch" ]; then
    log_policy "Time source ${NOW_EPOCH_SOURCE:-unknown}; epoch unavailable"
fi

last_calib=$(cat "$CALIBRATE_TS_FILE" 2>/dev/null || echo 0)
last_calib="$(uint_or_default "$last_calib" "0")"
if [ "${NOW_EPOCH_SOURCE:-unknown}" != "epoch" ] && is_epoch_like "$last_calib"; then
    log_policy "Time source mismatch (epoch vs ${NOW_EPOCH_SOURCE:-unknown}); resetting last_calib"
    last_calib=0
fi

calib_state=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "idle")
elapsed=$((now_ts - last_calib))

# DONE: Refactor pick_score to shared function used by daemon/executor
pick_score() {
    local prefer_transport="${1:-auto}" score

    if ! command -v pick_score_from_state >/dev/null 2>&1; then
        log_policy "pick_score helper missing: pick_score_from_state"
        return 1
    fi

    score=$(pick_score_from_state "$DAEMON_STATE_FILE" "$prefer_transport" "${EVENT_NAME:-}" "${EVENT_DETAILS:-}") || {
        log_policy "pick_score: daemon.state missing/unusable at $DAEMON_STATE_FILE"
        return 1
    }

    log_policy "pick_score selected=$score source=${PICK_SCORE_SOURCE:-unknown} prefer=${PICK_SCORE_PREFER:-$prefer_transport} transport=${PICK_SCORE_TRANSPORT:-unknown} event=${EVENT_NAME:-none}"
    printf '%s' "$score"
    return 0
}

# --- calibrate gating decision ---
# TODO: [PENDING] Improve gating logic (consider profile type, e.g., mobile vs wifi) TODO:
if [ "$force_calibrate" -eq 1 ]; then
    log_policy "Calibration forced by env FORCE_CALIBRATE=1"
    run_calibrate=1
elif [ "$now_ts" -eq 0 ]; then
    log_policy "Invalid time source; skipping calibrate gating"
else
    if [ "$calib_state" != "idle" ] && [ "$elapsed" -lt "$settle_window" ]; then
        log_policy "Calibration settling ($elapsed/${settle_window}s); skip calibrate"
        run_calibrate=0
    else
        echo "idle" > "$CALIBRATE_STATE_FILE"
        current_score=$(pick_score)
        streak=$(cat "$CALIBRATE_STREAK_FILE" 2>/dev/null || echo 0)
        case "$current_score" in
            ''|*[!0-9.]*) current_score=100 ;;
        esac
        if awk "BEGIN {exit !($current_score < $calibrate_low_score)}"; then
            streak=$((streak + 1))
        else
            streak=0
        fi
        echo "$streak" > "$CALIBRATE_STREAK_FILE"

        if [ "$last_calib" -eq 0 ]; then
            if [ "$calibrate_initial_on_boot" -eq 1 ]; then
                log_policy "No previous calibration; CALIBRATE_INITIAL_ON_BOOT=1 so initial calibrate runs"
                run_calibrate=1
            else
                log_policy "No previous calibration; skipping initial calibrate (set CALIBRATE_INITIAL_ON_BOOT=1 to enable)"
                run_calibrate=0
            fi
        elif [ "$streak" -ge "$calibrate_low_streak_needed" ] && [ "$elapsed" -ge "$calibrate_cooldown" ]; then
            log_policy "Score low ($current_score) streak=$streak cooldown_ok; running calibrate"
            run_calibrate=1
        else
            log_policy "Skip calibrate: score=$current_score streak=$streak elapsed=${elapsed}s/<${calibrate_cooldown}s"
        fi
    fi
fi

# --- calibrate runner (timeout, estados, cooldown) ---
CALIBRATE_TIMEOUT="${CALIBRATE_TIMEOUT:-600}"
CALIBRATE_SETTLE_MARGIN="${CALIBRATE_SETTLE_MARGIN:-60}"

# DONE: Allow override of output/state files via env
# Default output and state files
: "${CALIBRATE_OUT:=${CALIBRATE_OUT:-$MODDIR/logs/results.env}}"
: "${CALIBRATE_TS_FILE:=${CALIBRATE_TS_FILE:-$MODDIR/cache/calibrate.ts}}"
: "${CALIBRATE_STATE_FILE:=${CALIBRATE_STATE_FILE:-$MODDIR/cache/calibrate.state}}"
: "${CALIBRATE_STREAK_FILE:=${CALIBRATE_STREAK_FILE:-$MODDIR/cache/calibrate.streak}}"

# DONE: Prevent multiple concurrent calibrates
current_state="$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "idle")"
if [ "$current_state" = "running" ]; then
    log_policy "Calibration already running; skipping new run"
    run_calibrate=0
fi
# Ensure only one calibration at a time across concurrent executor runs.
if [ "$run_calibrate" -eq 1 ]; then
    if acquire_calibrate_lock; then
        LOCK_HELD=1
        set_lock_trap
    else
        log_policy "Calibration lock busy; skipping new run"
        run_calibrate=0
    fi
fi
# DONE: Prevent calibrate during heavy daemon activity windows
HEAVY_LOAD_PROP="${HEAVY_LOAD_PROP:-kitsunping.heavy_load}"
HEAVY_LOAD_MAX_FOR_CALIBRATE="${HEAVY_LOAD_MAX_FOR_CALIBRATE:-0}"
CALIBRATE_FORCE_AFTER_POSTPONES="${CALIBRATE_FORCE_AFTER_POSTPONES:-12}"
CALIBRATE_FORCE_AFTER_SEC="${CALIBRATE_FORCE_AFTER_SEC:-600}"
CALIBRATE_FORCE_LOCK_WAIT_SEC="${CALIBRATE_FORCE_LOCK_WAIT_SEC:-20}"
CALIBRATION_PRIORITY_PROP="${CALIBRATION_PRIORITY_PROP:-kitsunping.calibration.priority}"
heavy_load_now=0
HEAVY_LOAD_MAX_FOR_CALIBRATE="$(uint_or_default "$HEAVY_LOAD_MAX_FOR_CALIBRATE" "0")"
CALIBRATE_FORCE_AFTER_POSTPONES="$(uint_or_default "$CALIBRATE_FORCE_AFTER_POSTPONES" "12")"
CALIBRATE_FORCE_AFTER_SEC="$(uint_or_default "$CALIBRATE_FORCE_AFTER_SEC" "600")"
CALIBRATE_FORCE_LOCK_WAIT_SEC="$(uint_or_default "$CALIBRATE_FORCE_LOCK_WAIT_SEC" "20")"

if [ "$run_calibrate" -eq 1 ]; then
    postpone_count=$(read_uint_file "$CALIBRATE_POSTPONE_COUNT_FILE")
    postpone_first_ts=$(read_uint_file "$CALIBRATE_POSTPONE_TS_FILE")
    postpone_age=0
    if [ "$postpone_first_ts" -gt 0 ] && [ "$now_ts" -gt 0 ]; then
        postpone_age=$((now_ts - postpone_first_ts))
        [ "$postpone_age" -lt 0 ] && postpone_age=0
    fi

    if [ "$postpone_count" -ge "$CALIBRATE_FORCE_AFTER_POSTPONES" ] || [ "$postpone_age" -ge "$CALIBRATE_FORCE_AFTER_SEC" ]; then
        CALIBRATE_FORCE_PRIORITY=1
        if command -v calibration_priority_write >/dev/null 2>&1; then
            calibration_priority_write 1 >/dev/null 2>&1 || true
            CALIBRATION_PRIORITY_SET=1
        elif command -v setprop >/dev/null 2>&1; then
            setprop "$CALIBRATION_PRIORITY_PROP" 1 >/dev/null 2>&1 || true
            CALIBRATION_PRIORITY_SET=1
        fi
        log_policy "Calibration starvation guard active (count=$postpone_count age=${postpone_age}s); requesting daemon heavy-task yield"
    fi
fi

if [ "$run_calibrate" -eq 1 ]; then
    heavy_load_now=$(getprop "$HEAVY_LOAD_PROP" 2>/dev/null | tr -d '\r\n')
    heavy_load_now="$(uint_or_default "$heavy_load_now" "0")"

    if [ "$heavy_load_now" -gt "$HEAVY_LOAD_MAX_FOR_CALIBRATE" ]; then
        if [ "$CALIBRATE_FORCE_PRIORITY" -eq 1 ]; then
            log_policy "Ignoring heavy_load gate under starvation guard ($HEAVY_LOAD_PROP=$heavy_load_now)"
        elif command -v heavy_activity_lock_acquire >/dev/null 2>&1; then
            if heavy_activity_lock_acquire; then
                HEAVY_ACTIVITY_LOCK_HELD=1
                if command -v heavy_load_write >/dev/null 2>&1; then
                    heavy_load_write 0 >/dev/null 2>&1 || true
                elif command -v setprop >/dev/null 2>&1; then
                    setprop "$HEAVY_LOAD_PROP" 0 >/dev/null 2>&1 || true
                fi
                log_policy "Recovered stale heavy activity state ($HEAVY_LOAD_PROP was $heavy_load_now; lock was free); continuing calibration"
                heavy_load_now=0
            else
                record_calibration_postpone "heavy daemon activity detected ($HEAVY_LOAD_PROP=$heavy_load_now > $HEAVY_LOAD_MAX_FOR_CALIBRATE)"
                run_calibrate=0
            fi
        else
            record_calibration_postpone "heavy daemon activity detected ($HEAVY_LOAD_PROP=$heavy_load_now > $HEAVY_LOAD_MAX_FOR_CALIBRATE)"
            run_calibrate=0
        fi
    fi
fi

if [ "$run_calibrate" -eq 1 ] && command -v heavy_activity_lock_acquire >/dev/null 2>&1; then
    if [ "$HEAVY_ACTIVITY_LOCK_HELD" -eq 1 ]; then
        :
    elif [ "$CALIBRATE_FORCE_PRIORITY" -eq 1 ]; then
        waited=0
        while [ "$waited" -lt "$CALIBRATE_FORCE_LOCK_WAIT_SEC" ]; do
            if heavy_activity_lock_acquire; then
                HEAVY_ACTIVITY_LOCK_HELD=1
                break
            fi
            sleep 1
            waited=$((waited + 1))
        done
        if [ "$HEAVY_ACTIVITY_LOCK_HELD" -ne 1 ]; then
            record_calibration_postpone "heavy activity lock busy after force-wait (${CALIBRATE_FORCE_LOCK_WAIT_SEC}s)"
            run_calibrate=0
        fi
    elif heavy_activity_lock_acquire; then
        HEAVY_ACTIVITY_LOCK_HELD=1
    else
        record_calibration_postpone "heavy activity lock busy"
        run_calibrate=0
    fi
fi

if [ "$run_calibrate" -eq 1 ] && [ -f "$CALIBRATE_SH" ]; then
    clear_calibration_postpone_tracker
    log_policy "Starting calibration (delay=$calibrate_delay, timeout=${CALIBRATE_TIMEOUT}s) profile=$target_profile"

    now_ts=$(epoch_now)
    echo "$now_ts" | atomic_write "$CALIBRATE_TS_FILE"
    echo "running" | atomic_write "$CALIBRATE_STATE_FILE"
    rm -f "$CALIBRATE_OUT" 2>/dev/null

    if ! . "$CALIBRATE_SH" >> "$POLICY_LOG" 2>&1; then
        log_policy "Failed to source $CALIBRATE_SH; aborting calibrate"
        echo "idle" | atomic_write "$CALIBRATE_STATE_FILE"
    else
        ( calibrate_network_settings "$calibrate_delay" > "$CALIBRATE_OUT" 2>>"$POLICY_LOG" ) &
        calib_pid=$!
        log_policy "Calibrate started pid=$calib_pid, waiting up to ${CALIBRATE_TIMEOUT}s"

        waited=0
        timed_out=0
        while kill -0 "$calib_pid" 2>/dev/null; do
            sleep 1
            waited=$((waited + 1))
            if [ $((waited % 60)) -eq 0 ]; then
                log_policy "Calibrate still running pid=$calib_pid (${waited}s elapsed)"
            fi
            if [ "$waited" -ge "$CALIBRATE_TIMEOUT" ]; then
                timed_out=1
                log_policy "Calibrate timeout (${CALIBRATE_TIMEOUT}s) reached; killing pid=$calib_pid"
                kill "$calib_pid" 2>/dev/null || true
                break
            fi
        done

        if [ "$timed_out" -eq 1 ]; then
            calib_rc=124
        else
            wait "$calib_pid" 2>/dev/null
            calib_rc=$?
        fi

        log_policy "Calibrate finished rc=$calib_rc"

        if [ "$calib_rc" -eq 0 ] && [ -s "$CALIBRATE_OUT" ]; then
            while IFS='=' read -r key val; do
                case "$key" in BEST_*) ;; *) continue ;; esac
                [ -z "$val" ] && continue
                prop="${key#BEST_}"
                prop="${prop//_/.}"
                if [ -n "$RESETPROP_BIN" ]; then
                    log_policy "resetprop $prop=$val"
                    if "$RESETPROP_BIN" "$prop" "$val" >>"$POLICY_LOG" 2>&1; then
                        props_applied=$((props_applied + 1))
                    else
                        log_policy "resetprop failed for $prop"
                        append_prop_failure "$prop"
                    fi
                else
                    log_policy "resetprop missing; skipping $prop"
                    append_prop_failure "$prop"
                fi
            done < "$CALIBRATE_OUT"

            printf '%s' "$target_profile" | atomic_write "$CURRENT_FILE" || true
            now_ts=$(epoch_now)
            echo "$now_ts" | atomic_write "$CALIBRATE_TS_FILE"
            echo "cooling" | atomic_write "$CALIBRATE_STATE_FILE"
            echo 0 | atomic_write "$CALIBRATE_STREAK_FILE"
            log_policy "Calibration applied: props_applied=$props_applied; entering cooling state"
        elif [ "$calib_rc" -eq 3 ]; then
            log_policy "Calibrate postponed by child (rc=3); deferring next run"
            now_ts=$(epoch_now)
            echo "$now_ts" | atomic_write "$CALIBRATE_TS_FILE"
            echo "postponed" | atomic_write "$CALIBRATE_STATE_FILE"
        elif [ "$calib_rc" -eq 1 ] || [ "$calib_rc" -eq 2 ] || [ "$calib_rc" -eq 4 ]; then
            log_policy "Calibrate aborted (rc=$calib_rc); leaving profile unchanged"
            echo "idle" | atomic_write "$CALIBRATE_STATE_FILE"
        else
            log_policy "Calibrate failed or empty output (rc=$calib_rc)"
            now_ts=$(epoch_now)
            echo "$now_ts" | atomic_write "$CALIBRATE_TS_FILE"
            echo "cooling" | atomic_write "$CALIBRATE_STATE_FILE"
            echo 0 | atomic_write "$CALIBRATE_STREAK_FILE"
        fi
    fi
else
    log_policy "Skipping calibrate (disabled, gated, or missing)"
fi

if [ "$LOCK_HELD" -eq 1 ]; then
    release_calibrate_lock
    LOCK_HELD=0
    lock_state=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "unknown")
    log_policy "Calibration lock released; state=$lock_state"
fi

if [ "$HEAVY_ACTIVITY_LOCK_HELD" -eq 1 ] && command -v heavy_activity_lock_release >/dev/null 2>&1; then
    heavy_activity_lock_release >/dev/null 2>&1 || true
    HEAVY_ACTIVITY_LOCK_HELD=0
    log_policy "Heavy activity lock released"
fi

if [ "$CALIBRATION_PRIORITY_SET" -eq 1 ]; then
    if command -v calibration_priority_write >/dev/null 2>&1; then
        calibration_priority_write 0 >/dev/null 2>&1 || true
    elif command -v setprop >/dev/null 2>&1; then
        setprop "$CALIBRATION_PRIORITY_PROP" 0 >/dev/null 2>&1 || true
    fi
    CALIBRATION_PRIORITY_SET=0
    log_policy "Calibration priority request cleared"
fi

# Emit simple JSON event for the APK (polling-friendly)

ts_now=$(epoch_now)
calib_state_out=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "unknown")
calib_ts_out=$(cat "$CALIBRATE_TS_FILE" 2>/dev/null || echo 0)
ts_now=$(pick_event_ts "$ts_now" "${EVENT_TS:-0}" "$calib_ts_out")
if [ -n "$props_failed_json" ]; then
    props_failed_payload="[$props_failed_json]"
else
    props_failed_payload="[]"
fi
cat <<EOF | atomic_write "$POLICY_EVENT_JSON"
{"ts":$ts_now,"target":"$target_profile","applied_profile":$applied_profile,"props_applied":$props_applied,"props_failed":$props_failed,"props_failed_list":$props_failed_payload,"calibrate_state":"$calib_state_out","calibrate_ts":$calib_ts_out,"event":"EXECUTOR_RUN"}
EOF

event_payload=$(cat "$POLICY_EVENT_JSON" 2>/dev/null | tr -d '\n')
if [ -n "$event_payload" ] && command -v am >/dev/null 2>&1; then
    am broadcast -a com.kitsunping.ACTION_UPDATE -p app.kitsunping \
        --es payload "$event_payload" \
        --es event "EXECUTOR_RUN" \
        --es ts "$ts_now" \
        >/dev/null 2>&1
fi

exit 0
