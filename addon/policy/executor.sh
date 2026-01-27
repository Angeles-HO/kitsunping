#!/system/bin/sh
# executor.sh - executes network profile changes
# Part of Kitsunping - daemon.sh
# TODO: refactor common functions with daemon.sh
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

TARGET_FILE="$MODDIR/cache/policy.target"
CURRENT_FILE="$MODDIR/cache/policy.current"
KITSUTILS_SH="$MODDIR/addon/functions/debug/shared_errors.sh"
CALIBRATE_SH="$MODDIR/addon/Net_Calibrate/calibrate.sh"
CALIBRATE_OUT="$MODDIR/logs/results.env"
POLICY_EVENT_JSON="$MODDIR/cache/policy.event.json"
CALIBRATE_STATE_FILE="$MODDIR/cache/calibrate.state"
CALIBRATE_TS_FILE="$MODDIR/cache/calibrate.ts"
CALIBRATE_STREAK_FILE="$MODDIR/cache/calibrate.streak"
DAEMON_STATE_FILE="$MODDIR/cache/daemon.state"

mkdir -p "$LOG_DIR" 2>/dev/null
: >> "$POLICY_LOG" 2>/dev/null

# Fallback logger
log_policy() { printf '[%s][POLICY] %s\n' "$(date +%s)" "$*" >> "$POLICY_LOG"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# atomic write helper
atomic_write() {
    local target="$1" tmp
    tmp="${target}.$$.$RANDOM.tmp"
    cat - > "$tmp" 2>/dev/null && mv "$tmp" "$target" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

# Prefer Kitsutils logging if available
if [ -f "$KITSUTILS_SH" ]; then
    . "$KITSUTILS_SH"
    # Re-map to log_policy for consistency
    log_policy() { log_info "$@"; }
fi

# Detect resetprop
RESETPROP_BIN=""
if command_exists resetprop; then
    RESETPROP_BIN="$(command -v resetprop 2>/dev/null)"
    log_policy "resetprop resolved to $RESETPROP_BIN"
fi

# Load functions without executing main flow
SKIP_SERVICE_MAIN=1
. "$MODDIR/service.sh" >>"$POLICY_LOG" 2>&1

# If daemon passed event via env, log it (not essential, but useful for logs)
if [ -n "${EVENT_NAME:-}" ]; then
    log_policy "ctx EVENT_NAME=${EVENT_NAME} EVENT_TS=${EVENT_TS:-} DETAILS=${EVENT_DETAILS:-}"
fi

# If the daemon signalled a profile change, prefer that value and let executor
# own writing the target file. EVENT_DETAILS expected like "from=x to=y ...".
if [ "${EVENT_NAME:-}" = "PROFILE_CHANGED" ] && [ -n "${EVENT_DETAILS:-}" ]; then
    policy_to=$(printf '%s' "${EVENT_DETAILS}" | sed -n 's/.*\bto=\([^ ]*\).*/\1/p')
    if [ -n "$policy_to" ]; then
        printf '%s' "$policy_to" > "$TARGET_FILE" 2>/dev/null || true
        log_policy "PROFILE_CHANGED event -> wrote target_profile=$policy_to"
    fi
fi

if [ ! -f "$TARGET_FILE" ]; then
    log_policy "No target profile; nothing to do"
    exit 0
fi

# Read target profile
target_profile="$(cat "$TARGET_FILE" 2>/dev/null)"

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

# If apply_network_optimizations exists, try it first (it might set props)
if command_exists apply_network_optimizations; then
    log_policy "Applying built-in profile: $target_profile"
    if apply_network_optimizations "$target_profile" >> "$POLICY_LOG" 2>&1; then
        applied_profile=1
        echo "$target_profile" > "$CURRENT_FILE"
    else
        log_policy "apply_network_optimizations failed"
    fi
else
    log_policy "apply_network_optimizations not available"
fi

# calibrate policy: gated by cooldown + low-score streak
calibrate_delay="${CALIBRATE_DELAY:-10}"
calibrate_cooldown="${CALIBRATE_COOLDOWN:-1800}"
calibrate_low_score="${CALIBRATE_SCORE_LOW:-40}"
calibrate_low_streak_needed="${CALIBRATE_LOW_STREAK:-2}"
settle_window="$calibrate_cooldown"
force_calibrate="${FORCE_CALIBRATE:-0}"

# --- calibrate gating logic ---
run_calibrate=0
now_ts=$(date +%s 2>/dev/null || busybox date +%s 2>/dev/null || echo 0)
last_calib=$(cat "$CALIBRATE_TS_FILE" 2>/dev/null || echo 0)
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
CALIBRATE_TIMEOUT="${CALIBRATE_TIMEOUT:-1200}"
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
# TODO: prevent calibrate during daemon activity
## 
if [ $run_calibrate -eq 1 ] && [ -f "$CALIBRATE_SH" ]; then
    log_policy "Starting calibration (delay=$calibrate_delay, timeout=${CALIBRATE_TIMEOUT}s) profile=$target_profile"

    now_ts=$(date +%s 2>/dev/null || busybox date +%s 2>/dev/null || echo 0)
    echo "$now_ts" > "$CALIBRATE_TS_FILE"
    echo "running" > "$CALIBRATE_STATE_FILE"
    rm -f "$CALIBRATE_OUT"

    if ! . "$CALIBRATE_SH" >>"$POLICY_LOG" 2>&1; then
        log_policy "Failed to source $CALIBRATE_SH; aborting calibrate"
        echo "idle" > "$CALIBRATE_STATE_FILE"
        run_calibrate=0
    else
        ( calibrate_network_settings "$calibrate_delay" 2>>"$POLICY_LOG" > "$CALIBRATE_OUT" ) &
        calib_pid=$!
        log_policy "Calibrate started pid=$calib_pid, waiting up to ${CALIBRATE_TIMEOUT}s"

        waited=0
        while kill -0 "$calib_pid" 2>/dev/null; do
            sleep 1
            waited=$((waited + 1))
            if [ $((waited % 60)) -eq 0 ]; then
                log_policy "Calibrate still running pid=$calib_pid (${waited}s elapsed)"
            fi
            if [ "$waited" -ge "$CALIBRATE_TIMEOUT" ]; then
                log_policy "Calibrate timeout (${CALIBRATE_TIMEOUT}s) reached; killing pid=$calib_pid"
                kill "$calib_pid" 2>/dev/null || true
                break
            fi
        done

        wait "$calib_pid" 2>/dev/null || true
        calib_rc=$?

        if [ "$calib_rc" -eq 0 ] && [ -s "$CALIBRATE_OUT" ]; then
            log_policy "Calibrate finished successfully; applying props from $CALIBRATE_OUT"
            props_applied=0
            while IFS= read -r line || [ -n "$line" ]; do
                case "$line" in ''|\#*) continue ;; esac
                key="${line%%=*}"
                val="${line#*=}"
                case "$key" in BEST_*) ;; *) continue ;; esac
                [ -z "$val" ] && continue
                prop="${key#BEST_}"
                prop="${prop//_/.}"
                if [ -n "$RESETPROP_BIN" ]; then
                    log_policy "resetprop $prop=$val"
                    "$RESETPROP_BIN" "$prop" "$val" >>"$POLICY_LOG" 2>&1 || log_policy "resetprop failed for $prop"
                else
                    log_policy "resetprop missing; skipping $prop"
                fi
                props_applied=$((props_applied + 1))
            done < "$CALIBRATE_OUT"

            echo "$target_profile" > "$CURRENT_FILE"
            echo "$now_ts" > "$CALIBRATE_TS_FILE"
            echo "cooling" > "$CALIBRATE_STATE_FILE"
            echo 0 > "$CALIBRATE_STREAK_FILE"
            log_policy "Calibration applied: props_applied=$props_applied; entering cooling state"
        else
            log_policy "Calibrate failed or empty output (rc=$calib_rc)"
            echo "idle" > "$CALIBRATE_STATE_FILE"
        fi
    fi
else
    log_policy "Skipping calibrate (disabled or missing)"
fi

# Emit simple JSON event for the APK (polling-friendly)
ts_now=$(date +%s 2>/dev/null || busybox date +%s 2>/dev/null || echo 0)
calib_state_out=$(cat "$CALIBRATE_STATE_FILE" 2>/dev/null || echo "unknown")
calib_ts_out=$(cat "$CALIBRATE_TS_FILE" 2>/dev/null || echo 0)
cat <<EOF | atomic_write "$POLICY_EVENT_JSON"
{"ts":$ts_now,"target":"$target_profile","applied_profile":$applied_profile,"props_applied":$props_applied,"calibrate_state":"$calib_state_out","calibrate_ts":$calib_ts_out,"event":"EXECUTOR_RUN"}
EOF

exit 0
