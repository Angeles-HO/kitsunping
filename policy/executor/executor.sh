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
# REFACTOR: KPI functions split into executor_kpi.sh, calibration logic split into executor_calibrate.sh
SCRIPT_DIR="${0%/*}"            # kitsunping/policy/executor
MODDIR="${SCRIPT_DIR%/policy/executor}"     # kitsunping (root of the module)

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
CALIBRATE_SH="$MODDIR/calibration/calibrate.sh"
if [ ! -f "$CALIBRATE_SH" ]; then
    CALIBRATE_SH="$MODDIR/addon/Net_Calibrate/calibrate.sh"
fi
CALIBRATE_OUT="$MODDIR/logs/results.env"
POLICY_EVENT_JSON="$MODDIR/cache/policy.event.json"
EXECUTOR_KPI_HOURLY_FILE="$MODDIR/cache/executor.kpi.hourly"
CALIBRATE_STATE_FILE="$MODDIR/cache/calibrate.state"
CALIBRATE_TS_FILE="$MODDIR/cache/calibrate.ts"
CALIBRATE_STREAK_FILE="$MODDIR/cache/calibrate.streak"
CALIBRATE_POSTPONE_COUNT_FILE="$MODDIR/cache/calibrate.postpone.count"
CALIBRATE_POSTPONE_TS_FILE="$MODDIR/cache/calibrate.postpone.ts"
DAEMON_STATE_FILE="$MODDIR/cache/daemon.state"

mkdir -p "$LOG_DIR" 2>/dev/null
epoch_ms_now() {
    local now_ms
    now_ms=$(date +%s%3N 2>/dev/null | tr -d '\r\n')
    case "$now_ms" in
        ''|*[!0-9]*)
            now_ms=$(epoch_now)
            now_ms="$(uint_or_default "$now_ms" "0")"
            now_ms=$((now_ms * 1000))
            ;;
    esac
    printf '%s' "$now_ms"
}

# ---------------------------------------------------------------------------
# Executor lock -- prevents overlapping executor runs
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
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
fi

# ---------------------------------------------------------------------------
# KPI counters (sourced; defines load/write/update_executor_kpi_hourly)
# ---------------------------------------------------------------------------
. "$SCRIPT_DIR/executor_kpi.sh"
: >> "$POLICY_LOG" 2>/dev/null

# Load profile runner functions without executing main flow
. "$SCRIPT_DIR/profile_runner.sh" >>"$POLICY_LOG" 2>&1

# If daemon passed event via env, log it
if [ -n "${EVENT_NAME:-}" ]; then
    log_policy "ctx EVENT_NAME=${EVENT_NAME} EVENT_TS=${EVENT_TS:-} DETAILS=${EVENT_DETAILS:-}"
fi

# ---------------------------------------------------------------------------
# Flags: force_reapply / force_calibrate
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Determine desired target profile
# ---------------------------------------------------------------------------
desired_profile="${TARGET_PROFILE:-}"

# Prefer PROFILE_CHANGED event details when present (expected: "from=x to=y ...").
if [ -z "$desired_profile" ] && [ "${EVENT_NAME:-}" = "PROFILE_CHANGED" ] && [ -n "${EVENT_DETAILS:-}" ]; then
    desired_profile=$(printf '%s' "${EVENT_DETAILS}" | sed -n 's/.*\bto=\([^ ]*\).*/\1/p')
fi

# For app/target overrides, request_profile carries details like: "... to=gaming ..."
if [ -z "$desired_profile" ] && [ "${EVENT_NAME:-}" = "request_profile" ] && [ -n "${EVENT_DETAILS:-}" ]; then
    desired_profile=$(printf '%s' "${EVENT_DETAILS}" | sed -n 's/.*\bto=\([^ ]*\).*/\1/p')
fi

# For request_profile, prefer policy.request over policy.target to avoid stale target shadowing.
if [ -z "$desired_profile" ] && [ "${EVENT_NAME:-}" = "request_profile" ] && [ -f "$REQUEST_FILE" ]; then
    desired_profile="$(cat "$REQUEST_FILE" 2>/dev/null)"
    [ -n "$desired_profile" ] && log_policy "Using policy.request for request_profile target_profile=$desired_profile"
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

# ---------------------------------------------------------------------------
# Transition tracking
# ---------------------------------------------------------------------------
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

transition_from="${current_profile:-none}"
transition_to="$target_profile"
transition_duration_ms=0
transition_status="skipped"
transition_reason="unchanged"
transition_started_ms=0
transition_finished_ms=0
transition_change_inc=0
transition_rollback_inc=0
transition_apply_count_inc=0

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

# ---------------------------------------------------------------------------
# APK broadcast helper
# ---------------------------------------------------------------------------
emit_policy_update_event() {
    local event_name="${1:-EXECUTOR_RUN}"
    local ts_now calib_state_out calib_ts_out props_failed_payload event_payload

    ts_now=$(epoch_now)
    calib_state_out=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "unknown")
    calib_ts_out=$(cat "$CALIBRATE_TS_FILE" 2>/dev/null || echo 0)
    ts_now=$(pick_event_ts "$ts_now" "${EVENT_TS:-0}" "$calib_ts_out")

    if [ -n "$props_failed_json" ]; then
        props_failed_payload="[$props_failed_json]"
    else
        props_failed_payload="[]"
    fi

    cat <<EVJSON | atomic_write "$POLICY_EVENT_JSON"
{"ts":$ts_now,"target":"$target_profile","applied_profile":$applied_profile,"props_applied":$props_applied,"props_failed":$props_failed,"props_failed_list":$props_failed_payload,"calibrate_state":"$calib_state_out","calibrate_ts":$calib_ts_out,"event":"$event_name","transition":{"from":"$transition_from","to":"$transition_to","duration_ms":$transition_duration_ms,"status":"$transition_status","reason":"$transition_reason"},"kpi":{"changes_hour":$KPI_CHANGES_HOUR,"rollbacks_hour":$KPI_ROLLBACKS_HOUR,"mean_apply_ms":$KPI_MEAN_APPLY_MS}}
EVJSON

    event_payload=$(cat "$POLICY_EVENT_JSON" 2>/dev/null | tr -d '\n')
    if [ -n "$event_payload" ] && command -v am >/dev/null 2>&1; then
        am broadcast -a com.kitsunping.ACTION_UPDATE -p app.kitsunping \
            --include-stopped-packages \
            --es payload "$event_payload" \
            --es event "$event_name" \
            --es ts "$ts_now" \
            >/dev/null 2>&1
    fi
}

# ---------------------------------------------------------------------------
# Profile apply
# ---------------------------------------------------------------------------
if [ "$skip_profile_apply" -eq 0 ]; then
    log_policy "Switching profile: $current_profile -> $target_profile"
    transition_started_ms=$(epoch_ms_now)
    transition_status="failed"
    transition_reason="apply_failed"

    # Apply profile: prefer net_profiles scripts via run_profile_script.
    if command -v run_profile_script >/dev/null 2>&1; then
        log_policy "Applying profile script: $target_profile"
        if run_profile_script "$target_profile" >> "$POLICY_LOG" 2>&1; then
            applied_profile=1
            printf '%s' "$target_profile" | atomic_write "$CURRENT_FILE" || true
            transition_status="success"
            transition_reason="profile_script_applied"
        else
            log_policy_error "run_profile_script failed"
            transition_reason="run_profile_script_failed"
        fi
    elif command -v apply_network_optimizations >/dev/null 2>&1; then
        # Back-compat fallback
        log_policy "Applying built-in profile: $target_profile"
        if apply_network_optimizations "$target_profile" >> "$POLICY_LOG" 2>&1; then
            applied_profile=1
            printf '%s' "$target_profile" | atomic_write "$CURRENT_FILE" || true
            transition_status="success"
            transition_reason="apply_network_optimizations_applied"
        else
            log_policy_error "apply_network_optimizations failed"
            append_prop_failure "apply_network_optimizations"
            transition_reason="apply_network_optimizations_failed"
        fi
    else
        log_policy_error "No profile applier available (missing run_profile_script/apply_network_optimizations)"
        transition_reason="no_profile_applier"
    fi

    transition_finished_ms=$(epoch_ms_now)
    transition_duration_ms=$((transition_finished_ms - transition_started_ms))
    [ "$transition_duration_ms" -lt 0 ] && transition_duration_ms=0

    if [ "$transition_status" = "success" ]; then
        transition_change_inc=1
        transition_apply_count_inc=1
    else
        transition_rollback_inc=1
    fi

    update_executor_kpi_hourly "$transition_change_inc" "$transition_rollback_inc" "$transition_duration_ms" "$transition_apply_count_inc"
    log_policy "[executor] transition ${transition_from} -> ${transition_to} took ${transition_duration_ms}ms status=${transition_status} reason=${transition_reason}"
    log_policy "[executor] kpi changes_hour=${KPI_CHANGES_HOUR} rollbacks_hour=${KPI_ROLLBACKS_HOUR} mean_apply_ms=${KPI_MEAN_APPLY_MS}"

    # Emit PROFILE_APPLIED immediately -- APK should not wait for EXECUTOR_RUN
    if [ "$transition_status" = "success" ]; then
        emit_policy_update_event "PROFILE_APPLIED"
    fi
else
    log_policy "Skipping profile reapply; calibration path only"
    transition_status="skipped"
    transition_reason="calibration_only"
    update_executor_kpi_hourly 0 0 0 0
    log_policy "[executor] transition ${transition_from} -> ${transition_to} took 0ms status=${transition_status} reason=${transition_reason}"
    log_policy "[executor] kpi changes_hour=${KPI_CHANGES_HOUR} rollbacks_hour=${KPI_ROLLBACKS_HOUR} mean_apply_ms=${KPI_MEAN_APPLY_MS}"
fi

# ---------------------------------------------------------------------------
# Post-apply: WCNSS sync + runtime resetprops
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Calibration phase -- tunables + sub-module
# ---------------------------------------------------------------------------
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
HEAVY_ACTIVITY_LOCK_HELD=0
CALIBRATION_PRIORITY_SET=0
CALIBRATE_FORCE_PRIORITY=0

# Source calibration helpers + defines run_calibration_phase()
. "$SCRIPT_DIR/executor_calibrate.sh"
run_calibration_phase

# ---------------------------------------------------------------------------
# Final broadcast -- signals APK that this executor run is fully complete
# ---------------------------------------------------------------------------
emit_policy_update_event "EXECUTOR_RUN"

exit 0