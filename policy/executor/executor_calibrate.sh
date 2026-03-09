#!/system/bin/sh
# executor_calibrate.sh — calibration helpers and run_calibration_phase()
# Sourced by executor.sh after all other helpers are loaded.
# Requires (from executor.sh scope): atomic_write, epoch_now, uint_or_default,
#   is_epoch_like, pick_score_from_state, emit_policy_update_event,
#   append_prop_failure, log_policy, log_policy_warn, log_policy_error,
#   release_executor_lock, RESETPROP_BIN, POLICY_LOG, MODDIR, DAEMON_STATE_FILE,
#   CALIBRATE_LOCK_DIR, CALIBRATE_SH, CALIBRATE_OUT, CALIBRATE_TS_FILE,
#   CALIBRATE_STATE_FILE, CALIBRATE_STREAK_FILE, CALIBRATE_POSTPONE_COUNT_FILE,
#   CALIBRATE_POSTPONE_TS_FILE, CURRENT_FILE, EVENT_NAME, force_calibrate,
#   target_profile, props_applied, calibrate_delay, calibrate_cooldown,
#   calibrate_low_score, calibrate_low_streak_needed, settle_window,
#   calibrate_initial_on_boot, LOCK_HELD, HEAVY_ACTIVITY_LOCK_HELD,
#   CALIBRATION_PRIORITY_SET, CALIBRATE_FORCE_PRIORITY.

# ---------------------------------------------------------------------------
# Calibration lock
# ---------------------------------------------------------------------------
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
    trap 'release_calibrate_lock; release_executor_lock' EXIT INT TERM
}

# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# State / score helpers
# ---------------------------------------------------------------------------
read_daemon_state_value() {
    local key="$1"
    [ -f "$DAEMON_STATE_FILE" ] || { printf ''; return 0; }
    awk -F= -v k="$key" '$1==k {print substr($0, index($0, "=")+1)}' "$DAEMON_STATE_FILE" | tail -n1
}

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

# ---------------------------------------------------------------------------
# run_calibration_phase — gating + runner (called once from executor.sh)
# Uses outer-scope vars: target_profile, applied_profile, force_calibrate,
#   calibrate_delay, calibrate_cooldown, calibrate_low_score,
#   calibrate_low_streak_needed, settle_window, calibrate_initial_on_boot,
#   LOCK_HELD, HEAVY_ACTIVITY_LOCK_HELD, CALIBRATION_PRIORITY_SET,
#   CALIBRATE_FORCE_PRIORITY (all pre-set to 0 by executor.sh).
# ---------------------------------------------------------------------------
run_calibration_phase() {

    # --- time + last-calibration baseline ---
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

    # --- transport context detection ---
    # DONE: transport/profile-aware calibrate gating (wifi/mobile thresholds + cooldown)
    daemon_transport_raw="$(read_daemon_state_value "transport")"
    daemon_wifi_state_raw="$(read_daemon_state_value "wifi.state")"
    transport_context="auto"
    case "$(printf '%s' "$daemon_transport_raw" | tr 'A-Z' 'a-z')" in
        wifi|wlan) transport_context="wifi" ;;
        mobile|cellular) transport_context="mobile" ;;
    esac

    if [ "$transport_context" = "auto" ]; then
        case "$(printf '%s' "$daemon_wifi_state_raw" | tr 'A-Z' 'a-z')" in
            connected) transport_context="wifi" ;;
            disconnected|off|disabled) transport_context="mobile" ;;
        esac
    fi

    if [ "$transport_context" = "auto" ]; then
        case "$target_profile" in
            gaming|benchmark|benchmark_gaming|benchmark_speed) transport_context="wifi" ;;
            speed|stable) transport_context="mobile" ;;
            *) transport_context="wifi" ;;
        esac
    fi

    # --- per-transport tunables ---
    calibrate_cooldown_wifi="$(uint_or_default "${CALIBRATE_COOLDOWN_WIFI:-$calibrate_cooldown}" "$calibrate_cooldown")"
    calibrate_cooldown_mobile="$(uint_or_default "${CALIBRATE_COOLDOWN_MOBILE:-$calibrate_cooldown}" "$calibrate_cooldown")"
    calibrate_low_score_wifi="$(uint_or_default "${CALIBRATE_SCORE_LOW_WIFI:-$calibrate_low_score}" "$calibrate_low_score")"
    calibrate_low_score_mobile="$(uint_or_default "${CALIBRATE_SCORE_LOW_MOBILE:-$calibrate_low_score}" "$calibrate_low_score")"
    calibrate_low_streak_wifi="$(uint_or_default "${CALIBRATE_LOW_STREAK_WIFI:-$calibrate_low_streak_needed}" "$calibrate_low_streak_needed")"
    calibrate_low_streak_mobile="$(uint_or_default "${CALIBRATE_LOW_STREAK_MOBILE:-$calibrate_low_streak_needed}" "$calibrate_low_streak_needed")"

    active_cooldown="$calibrate_cooldown"
    active_low_score="$calibrate_low_score"
    active_low_streak_needed="$calibrate_low_streak_needed"
    case "$transport_context" in
        mobile)
            active_cooldown="$calibrate_cooldown_mobile"
            active_low_score="$calibrate_low_score_mobile"
            active_low_streak_needed="$calibrate_low_streak_mobile"
            ;;
        *)
            active_cooldown="$calibrate_cooldown_wifi"
            active_low_score="$calibrate_low_score_wifi"
            active_low_streak_needed="$calibrate_low_streak_wifi"
            ;;
    esac

    log_policy "Calibrate gate context: profile=$target_profile transport=$transport_context cooldown=${active_cooldown}s low_score=$active_low_score streak_needed=$active_low_streak_needed"

    # --- gating decision ---
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
            echo "idle" | atomic_write "$CALIBRATE_STATE_FILE"
            current_score=$(pick_score)
            streak=$(cat "$CALIBRATE_STREAK_FILE" 2>/dev/null || echo 0)
            case "$current_score" in
                ''|*[!0-9.]*) current_score=100 ;;
            esac
            if awk "BEGIN {exit !($current_score < $active_low_score)}"; then
                streak=$((streak + 1))
            else
                streak=0
            fi
            echo "$streak" | atomic_write "$CALIBRATE_STREAK_FILE"

            if [ "$last_calib" -eq 0 ]; then
                if [ "$calibrate_initial_on_boot" -eq 1 ]; then
                    log_policy "No previous calibration; CALIBRATE_INITIAL_ON_BOOT=1 so initial calibrate runs"
                    run_calibrate=1
                else
                    log_policy "No previous calibration; skipping initial calibrate (set CALIBRATE_INITIAL_ON_BOOT=1 to enable)"
                    run_calibrate=0
                fi
            elif [ "$streak" -ge "$active_low_streak_needed" ] && [ "$elapsed" -ge "$active_cooldown" ]; then
                log_policy "Score low ($current_score) streak=$streak cooldown_ok; running calibrate"
                run_calibrate=1
            else
                log_policy "Skip calibrate: score=$current_score streak=$streak elapsed=${elapsed}s/<${active_cooldown}s"
            fi
        fi
    fi

    # --- calibrate runner (timeout, states, cooldown) ---
    CALIBRATE_TIMEOUT="${CALIBRATE_TIMEOUT:-600}"

    # DONE: Allow override of output/state files via env
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
    CALIBRATE_FORCE_LOCK_WAIT_SEC_USER="$(uint_or_default "${CALIBRATE_FORCE_LOCK_WAIT_SEC_USER:-45}" "45")"

    if [ "$run_calibrate" -eq 1 ] && [ "$force_calibrate" -eq 1 ] && [ "${EVENT_NAME:-}" = "user_requested_calibrate" ]; then
        CALIBRATE_FORCE_PRIORITY=1
        if [ "$CALIBRATE_FORCE_LOCK_WAIT_SEC_USER" -gt "$CALIBRATE_FORCE_LOCK_WAIT_SEC" ]; then
            CALIBRATE_FORCE_LOCK_WAIT_SEC="$CALIBRATE_FORCE_LOCK_WAIT_SEC_USER"
        fi
        log_policy "User requested calibration; enabling heavy-load bypass and extended lock wait (${CALIBRATE_FORCE_LOCK_WAIT_SEC}s)"
    fi

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

    # --- calibration runner ---
    if [ "$run_calibrate" -eq 1 ] && [ -f "$CALIBRATE_SH" ]; then
        calibration_started=0
        clear_calibration_postpone_tracker
        log_policy "Starting calibration (delay=$calibrate_delay, timeout=${CALIBRATE_TIMEOUT}s) profile=$target_profile"

        now_ts=$(epoch_now)
        echo "$now_ts" | atomic_write "$CALIBRATE_TS_FILE"
        echo "running" | atomic_write "$CALIBRATE_STATE_FILE"
        calibration_started=1
        emit_policy_update_event "CALIBRATION_STARTED"
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

            if [ "$calibration_started" -eq 1 ]; then
                emit_policy_update_event "CALIBRATION_FINISHED"
            fi
        fi
    else
        log_policy "Skipping calibrate (disabled, gated, or missing)"
    fi

    # --- cleanup locks ---
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
}
