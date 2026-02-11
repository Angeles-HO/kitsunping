#!/system/bin/sh
# executor.sh - executes network profile changes
# Part of Kitsunping - daemon.sh
# TODO: refactor common functions with daemon.sh (50% - 100%)
# TODO: improve logging consistency with daemon.sh 
# TODO: move atomic_write/command detection/now_epoch to shared helper sourced by daemon/executor/policy
# TODO: refine pick_score to prefer wifi vs mobile based on transport/event and handle missing daemon.state explicitly
# TODO: add concurrency guard (lock/PID) to prevent overlapping calibrations and consider daemon activity window
# TODO: validate time source before gating/emitting and define fallback when date returns 0
# TODO: surface per-prop failures from apply_network_optimizations/resetprop in policy.event.json
# TODO: document cooldown/low-streak tunables (and per-profile overrides) in README and expose via env
# TODO: keep APK JSON schema/timestamps (epoch seconds) documented with minimal fields applied_profile/props_applied/calibrate_state/ts
# TODO: explain debounce vs INTERVAL coupling (daemon) and consider fractional debounce
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
CALIBRATE_SH="$MODDIR/addon/Net_Calibrate/calibrate.sh"
CALIBRATE_OUT="$MODDIR/logs/results.env"
POLICY_EVENT_JSON="$MODDIR/cache/policy.event.json"
CALIBRATE_STATE_FILE="$MODDIR/cache/calibrate.state"
CALIBRATE_TS_FILE="$MODDIR/cache/calibrate.ts"
CALIBRATE_STREAK_FILE="$MODDIR/cache/calibrate.streak"
DAEMON_STATE_FILE="$MODDIR/cache/daemon.state"

mkdir -p "$LOG_DIR" 2>/dev/null
: >> "$POLICY_LOG" 2>/dev/null

# Shared helpers
if [ -f "$CORE_SH" ]; then
    . "$CORE_SH"
fi

# Fallback logger
command -v log_policy >/dev/null 2>&1 || log_policy() {
    printf '[%s][POLICY] %s\n' "$(date +%s)" "$*" >> "$POLICY_LOG"
}

command -v command_exists >/dev/null 2>&1 || command_exists() { command -v "$1" >/dev/null 2>&1; }

# Prefer Kitsutils logging if available
if [ -f "$SRD_ERRORS" ]; then
    . "$SRD_ERRORS"
    # Re-map to log_policy for consistency
    log_policy() { log_info "$@"; }
fi

if [ -f "$KITSUTILS_SH" ]; then
    . "$KITSUTILS_SH"
    # Re-map to log_policy for consistency
    log_policy() { log_info "$@"; }
fi

# Ensure atomic_write exists even if helpers couldn't be sourced.
command -v atomic_write >/dev/null 2>&1 || atomic_write() {
    local target="$1" tmp
    tmp=$(mktemp "${target}.XXXXXX" 2>/dev/null) || tmp="${target}.$$.$(date +%s).tmp"
    if cat - > "$tmp" 2>/dev/null; then
        mv "$tmp" "$target" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 1
}

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

if [ "$target_profile" = "$current_profile" ]; then
    log_policy "Profile unchanged ($target_profile)"
    exit 0
fi

log_policy "Switching profile: $current_profile -> $target_profile"

applied_profile=0
props_applied=0
props_failed=0
props_failed_json=""

# Apply profile: prefer net_profiles scripts via run_profile_script.
if command -v run_profile_script >/dev/null 2>&1; then
    log_policy "Applying profile script: $target_profile"
    if run_profile_script "$target_profile" >> "$POLICY_LOG" 2>&1; then
        applied_profile=1
        printf '%s' "$target_profile" | atomic_write "$CURRENT_FILE" || true
    else
        log_policy "run_profile_script failed"
    fi
elif command -v apply_network_optimizations >/dev/null 2>&1; then
    # Back-compat fallback
    log_policy "Applying built-in profile: $target_profile"
    if apply_network_optimizations "$target_profile" >> "$POLICY_LOG" 2>&1; then
        applied_profile=1
        printf '%s' "$target_profile" | atomic_write "$CURRENT_FILE" || true
    else
        log_policy "apply_network_optimizations failed"
    fi
else
    log_policy "No profile applier available (missing run_profile_script/apply_network_optimizations)"
fi

# calibrate policy: gated by cooldown + low-score streak
calibrate_delay="${CALIBRATE_DELAY:-10}"
calibrate_cooldown="${CALIBRATE_COOLDOWN:-1800}"
calibrate_low_score="${CALIBRATE_SCORE_LOW:-40}"
calibrate_low_streak_needed="${CALIBRATE_LOW_STREAK:-2}"
settle_window="$calibrate_cooldown"
force_calibrate="${FORCE_CALIBRATE:-0}"
CALIBRATE_LOCK_DIR="${CALIBRATE_LOCK_DIR:-$MODDIR/cache/calibrate.lock}"
LOCK_HELD=0
LOCK_TRAP_SET=0

is_epoch_like() {
    local ts="$1"
    case "$ts" in ''|*[!0-9]*) return 1 ;; esac
    [ "$ts" -ge 1000000000 ]
}

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

epoch_now() {
    local ts
    ts=$(now_epoch)
    case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
    if [ "${NOW_EPOCH_SOURCE:-unknown}" != "epoch" ]; then
        ts=0
    fi
    printf '%s' "$ts"
}

# --- calibrate gating logic ---
run_calibrate=0
now_ts=$(epoch_now)
if [ "${NOW_EPOCH_SOURCE:-unknown}" != "epoch" ]; then
    log_policy "Time source ${NOW_EPOCH_SOURCE:-unknown}; epoch unavailable"
fi

last_calib=$(cat "$CALIBRATE_TS_FILE" 2>/dev/null || echo 0)
case "$last_calib" in ''|*[!0-9]*) last_calib=0 ;; esac
if [ "${NOW_EPOCH_SOURCE:-unknown}" != "epoch" ] && is_epoch_like "$last_calib"; then
    log_policy "Time source mismatch (epoch vs ${NOW_EPOCH_SOURCE:-unknown}); resetting last_calib"
    last_calib=0
fi

calib_state=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "idle")
elapsed=$((now_ts - last_calib))

# TODO: refactor pick_score to daemon shared function
# TODO: better score logic (consider wifi vs mobile, etc)
pick_score() {
    local want_wifi="$1" score
    [ -f "$DAEMON_STATE_FILE" ] || return 1
    wifi_state=$(awk -F'=' '/^wifi.state=/{print $2}' "$DAEMON_STATE_FILE" | tail -n1)
    wifi_score=$(awk -F'=' '/^wifi.score=/{print $2}' "$DAEMON_STATE_FILE" | tail -n1)
    mobile_score=$(awk -F'=' '/^mobile.score=/{print $2}' "$DAEMON_STATE_FILE" | tail -n1)

    case "$wifi_score" in
        ''|*[!0-9.]*) wifi_score="" ;;
    esac
    case "$mobile_score" in
        ''|*[!0-9.]*) mobile_score="" ;;
    esac

    if [ "$wifi_state" = "connected" ] && [ -n "$wifi_score" ]; then
        score="$wifi_score"
    elif [ -n "$mobile_score" ]; then
        score="$mobile_score"
    elif [ -n "$wifi_score" ]; then
        score="$wifi_score"
    else
        score=""
    fi
    [ -n "$score" ] || return 1
    printf '%s' "$score"
    return 0
}

# --- calibrate gating decision ---
# TODO: improve gating logic (consider profile type, e.g., mobile vs wifi)
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
            log_policy "No previous calibration; running initial calibrate"
            run_calibrate=1
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

# TODO: allow override of output/state files via env
# Default output and state files
: "${CALIBRATE_OUT:=${CALIBRATE_OUT:-$MODDIR/logs/results.env}}"
: "${CALIBRATE_TS_FILE:=${CALIBRATE_TS_FILE:-$MODDIR/cache/calibrate.ts}}"
: "${CALIBRATE_STATE_FILE:=${CALIBRATE_STATE_FILE:-$MODDIR/cache/calibrate.state}}"
: "${CALIBRATE_STREAK_FILE:=${CALIBRATE_STREAK_FILE:-$MODDIR/cache/calibrate.streak}}"

# TODO: prevent multiple concurrent calibrates
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
# TODO: prevent calibrate during daemon activity
## 
if [ "$run_calibrate" -eq 1 ] && [ -f "$CALIBRATE_SH" ]; then
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
                        props_failed=$((props_failed + 1))
                        props_failed_json="${props_failed_json}${props_failed_json:+,}\"$prop\""
                    fi
                else
                    log_policy "resetprop missing; skipping $prop"
                    props_failed=$((props_failed + 1))
                    props_failed_json="${props_failed_json}${props_failed_json:+,}\"$prop\""
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

# Emit simple JSON event for the APK (polling-friendly)
ts_now=$(epoch_now)
calib_state_out=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "unknown")
calib_ts_out=$(cat "$CALIBRATE_TS_FILE" 2>/dev/null || echo 0)
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
