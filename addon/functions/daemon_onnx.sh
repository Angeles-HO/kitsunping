#!/system/bin/sh

# ONNX adaptive inference scaffold (Phase 2):
# - Optional runtime inference loop (guarded by props)
# - Step-capped weight deltas + EMA smoothing
# - Circuit breaker on repeated score degradation
# This file is intentionally safe-by-default and no-op when infer binary is absent.

daemon_onnx_uint_or_default() {
    local raw="$1" def="$2"
    case "$raw" in
        ''|*[!0-9]*) printf '%s' "$def" ;;
        *) printf '%s' "$raw" ;;
    esac
}

daemon_onnx_float_or_default() {
    local raw="$1" def="$2"
    LC_ALL=C awk -v v="$raw" -v d="$def" 'BEGIN {
        if (v ~ /^-?[0-9]+([.][0-9]+)?$/) {
            printf "%.6f", v + 0
        } else {
            printf "%.6f", d + 0
        }
    }'
}

daemon_onnx_now_epoch() {
    if command -v now_epoch >/dev/null 2>&1; then
        now_epoch
        return 0
    fi
    date +%s 2>/dev/null || echo 0
}

daemon_onnx_log_debug() {
    if command -v log_debug >/dev/null 2>&1; then
        log_debug "$*"
    fi
}

daemon_onnx_log_warn() {
    if command -v log_warning >/dev/null 2>&1; then
        log_warning "$*"
    fi
}

daemon_onnx_log_info() {
    if command -v log_info >/dev/null 2>&1; then
        log_info "$*"
    fi
}

daemon_onnx_atomic_write_text() {
    local dst="$1"
    local tmp="${dst}.tmp.$$"

    cat > "$tmp" 2>/dev/null || {
        rm -f "$tmp" 2>/dev/null || true
        return 1
    }

    if command -v atomic_write >/dev/null 2>&1; then
        cat "$tmp" | atomic_write "$dst" >/dev/null 2>&1 || {
            rm -f "$tmp" 2>/dev/null || true
            return 1
        }
        rm -f "$tmp" 2>/dev/null || true
        return 0
    fi

    mv "$tmp" "$dst" 2>/dev/null || {
        rm -f "$tmp" 2>/dev/null || true
        return 1
    }
    return 0
}

daemon_onnx_read_json_number_field() {
    local key="$1" file="$2" out

    [ -f "$file" ] || {
        printf '%s' ""
        return 0
    }

    if command -v jq >/dev/null 2>&1; then
        out="$(jq -r "try .${key} // empty" "$file" 2>/dev/null || true)"
        printf '%s' "$out"
        return 0
    fi

    out="$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\([-0-9.][0-9.]*\).*/\1/p" "$file" 2>/dev/null | head -n1)"
    printf '%s' "$out"
}

daemon_onnx_current_score() {
    local score="0" t
    t="${transport:-unknown}"

    case "$t" in
        wifi)
            score="$(daemon_onnx_uint_or_default "${wifi_score:-0}" "0")"
            ;;
        mobile)
            score="$(daemon_onnx_uint_or_default "${mobile_score:-0}" "0")"
            ;;
        *)
            score="$(daemon_onnx_uint_or_default "${wifi_score:-0}" "0")"
            ;;
    esac

    printf '%s' "$score"
}

daemon_onnx_build_features_json() {
    local out_file="$1"
    local battery_pct charging

    battery_pct="$(getprop sys.battery.level 2>/dev/null | tr -d '\r\n')"
    battery_pct="$(daemon_onnx_uint_or_default "$battery_pct" "0")"

    charging="$(getprop sys.battery.charging 2>/dev/null | tr -d '\r\n')"
    case "$charging" in
        1|true|TRUE|yes|YES|on|ON) charging=1 ;;
        *) charging=0 ;;
    esac

    printf '{"wifi_score":%s,"mobile_score":%s,"rssi_dbm":%s,"rsrp_dbm":%s,"sinr_db":%s,"latency_ms":%s,"jitter_ms":%s,"loss_pct":%s,"battery_pct":%s,"is_charging":%s,"sample_mode":"%s"}\n' \
        "$(daemon_onnx_uint_or_default "${wifi_score:-0}" "0")" \
        "$(daemon_onnx_uint_or_default "${mobile_score:-0}" "0")" \
        "$(daemon_onnx_float_or_default "${wifi_rssi_dbm:-0}" "0")" \
        "$(daemon_onnx_float_or_default "${rsrp:-0}" "0")" \
        "$(daemon_onnx_float_or_default "${sinr:-0}" "0")" \
        "$(daemon_onnx_uint_or_default "${wifi_latency_ms:-0}" "0")" \
        "$(daemon_onnx_uint_or_default "${wifi_jitter_ms:-0}" "0")" \
        "$(daemon_onnx_uint_or_default "${wifi_loss_pct:-0}" "0")" \
        "$battery_pct" \
        "$charging" \
        "${DAEMON_SAMPLE_MODE:-unknown}" > "$out_file"
}

daemon_onnx_capped_delta() {
    local delta="$1" cap="$2"
    LC_ALL=C awk -v d="$delta" -v c="$cap" 'BEGIN {
        if (d > c) d = c
        if (d < -c) d = -c
        printf "%.6f", d
    }'
}

daemon_onnx_apply_weight_deltas() {
    local da_raw="$1" db_raw="$2" dg_raw="$3" dd_raw="$4"
    local da db dg dd cap ema one_minus
    local old_a old_b old_g old_d
    local capped_a capped_b capped_g capped_d
    local target_a target_b target_g target_d
    local new_a new_b new_g new_d
    local normalized

    cap="$(daemon_onnx_float_or_default "${ONNX_STEP_CAP:-0.05}" "0.05")"
    ema="$(daemon_onnx_float_or_default "${ONNX_EMA_FACTOR:-0.20}" "0.20")"
    one_minus="$(LC_ALL=C awk -v e="$ema" 'BEGIN{v=1-e; if(v<0)v=0; printf "%.6f", v}')"

    da="$(daemon_onnx_float_or_default "$da_raw" "0")"
    db="$(daemon_onnx_float_or_default "$db_raw" "0")"
    dg="$(daemon_onnx_float_or_default "$dg_raw" "0")"
    dd="$(daemon_onnx_float_or_default "$dd_raw" "0")"

    old_a="$(daemon_onnx_float_or_default "${LCL_ALPHA:-0.4}" "0.4")"
    old_b="$(daemon_onnx_float_or_default "${LCL_BETA:-0.3}" "0.3")"
    old_g="$(daemon_onnx_float_or_default "${LCL_GAMMA:-0.3}" "0.3")"
    old_d="$(daemon_onnx_float_or_default "${LCL_DELTA:-0.1}" "0.1")"

    capped_a="$(daemon_onnx_capped_delta "$da" "$cap")"
    capped_b="$(daemon_onnx_capped_delta "$db" "$cap")"
    capped_g="$(daemon_onnx_capped_delta "$dg" "$cap")"
    capped_d="$(daemon_onnx_capped_delta "$dd" "$cap")"

    target_a="$(LC_ALL=C awk -v o="$old_a" -v d="$capped_a" 'BEGIN{printf "%.6f", o+d}')"
    target_b="$(LC_ALL=C awk -v o="$old_b" -v d="$capped_b" 'BEGIN{printf "%.6f", o+d}')"
    target_g="$(LC_ALL=C awk -v o="$old_g" -v d="$capped_g" 'BEGIN{printf "%.6f", o+d}')"
    target_d="$(LC_ALL=C awk -v o="$old_d" -v d="$capped_d" 'BEGIN{printf "%.6f", o+d}')"

    new_a="$(LC_ALL=C awk -v om="$one_minus" -v e="$ema" -v o="$old_a" -v t="$target_a" 'BEGIN{v=om*o + e*t; if(v<0)v=0; if(v>1)v=1; printf "%.6f", v}')"
    new_b="$(LC_ALL=C awk -v om="$one_minus" -v e="$ema" -v o="$old_b" -v t="$target_b" 'BEGIN{v=om*o + e*t; if(v<0)v=0; if(v>1)v=1; printf "%.6f", v}')"
    new_g="$(LC_ALL=C awk -v om="$one_minus" -v e="$ema" -v o="$old_g" -v t="$target_g" 'BEGIN{v=om*o + e*t; if(v<0)v=0; if(v>1)v=1; printf "%.6f", v}')"
    new_d="$(LC_ALL=C awk -v om="$one_minus" -v e="$ema" -v o="$old_d" -v t="$target_d" 'BEGIN{v=om*o + e*t; if(v<0)v=0; if(v>0.5)v=0.5; printf "%.6f", v}')"

    if command -v daemon_normalize_sigmoid_weights >/dev/null 2>&1; then
        normalized="$(daemon_normalize_sigmoid_weights "$new_a" "$new_b" "$new_g" "$new_d")"
        LCL_ALPHA="${normalized%% *}"; normalized="${normalized#* }"
        LCL_BETA="${normalized%% *}"; normalized="${normalized#* }"
        LCL_GAMMA="${normalized%% *}"; LCL_DELTA="${normalized#* }"
    else
        LCL_ALPHA="$new_a"
        LCL_BETA="$new_b"
        LCL_GAMMA="$new_g"
        LCL_DELTA="$new_d"
    fi

    daemon_onnx_log_debug "onnx weights applied alpha=${LCL_ALPHA:-0} beta=${LCL_BETA:-0} gamma=${LCL_GAMMA:-0} delta=${LCL_DELTA:-0}"
}

daemon_onnx_load_circuit_state() {
    local until bad
    until=0
    bad=0

    if [ -f "$ONNX_CIRCUIT_FILE" ]; then
        until="$(awk -F= '$1=="until" {print $2; exit}' "$ONNX_CIRCUIT_FILE" 2>/dev/null)"
        bad="$(awk -F= '$1=="bad_streak" {print $2; exit}' "$ONNX_CIRCUIT_FILE" 2>/dev/null)"
    fi

    ONNX_CIRCUIT_UNTIL="$(daemon_onnx_uint_or_default "$until" "0")"
    ONNX_BAD_STREAK="$(daemon_onnx_uint_or_default "$bad" "0")"
}

daemon_onnx_save_circuit_state() {
    {
        printf 'until=%s\n' "${ONNX_CIRCUIT_UNTIL:-0}"
        printf 'bad_streak=%s\n' "${ONNX_BAD_STREAK:-0}"
    } | daemon_onnx_atomic_write_text "$ONNX_CIRCUIT_FILE" >/dev/null 2>&1 || true
}

daemon_onnx_open_circuit() {
    local now cooldown
    now="$1"
    cooldown="$(daemon_onnx_uint_or_default "${ONNX_CIRCUIT_COOLDOWN_SEC:-600}" "600")"
    ONNX_CIRCUIT_UNTIL=$((now + cooldown))
    daemon_onnx_save_circuit_state
    daemon_onnx_log_warn "onnx circuit opened for ${cooldown}s (until=${ONNX_CIRCUIT_UNTIL})"
}

daemon_onnx_register_score_feedback() {
    local current="$1" now prev

    current="$(daemon_onnx_uint_or_default "$current" "0")"
    prev="$(daemon_onnx_uint_or_default "${ONNX_PREV_SCORE:-$current}" "$current")"

    if LC_ALL=C awk -v c="$current" -v p="$prev" 'BEGIN{exit !(c < (p - 5))}'; then
        ONNX_BAD_STREAK=$(( ${ONNX_BAD_STREAK:-0} + 1 ))
    else
        ONNX_BAD_STREAK=0
    fi

    if [ "${ONNX_BAD_STREAK:-0}" -ge 3 ]; then
        now="$(daemon_onnx_now_epoch)"
        daemon_onnx_open_circuit "$now"
        ONNX_BAD_STREAK=0
    fi

    ONNX_PREV_SCORE="$current"
    daemon_onnx_save_circuit_state
}

daemon_onnx_call_infer() {
    local in_file="$1" out_file="$2" timeout_sec rc
    local model_arg_1 model_arg_2

    [ -x "$ONNX_INFER_BIN" ] || return 127

    model_arg_1=""
    model_arg_2=""
    if [ -n "${ONNX_MODEL_PATH:-}" ] && [ -f "$ONNX_MODEL_PATH" ]; then
        model_arg_1="--model"
        model_arg_2="$ONNX_MODEL_PATH"
    fi

    timeout_sec="$(daemon_onnx_uint_or_default "${ONNX_INFER_TIMEOUT_SEC:-2}" "2")"
    [ "$timeout_sec" -lt 1 ] && timeout_sec=1

    if command -v timeout >/dev/null 2>&1; then
        if [ -n "$model_arg_1" ]; then
            timeout "$timeout_sec" "$ONNX_INFER_BIN" "$model_arg_1" "$model_arg_2" < "$in_file" > "$out_file" 2>/dev/null
        else
            timeout "$timeout_sec" "$ONNX_INFER_BIN" < "$in_file" > "$out_file" 2>/dev/null
        fi
        rc=$?
    else
        if [ -n "$model_arg_1" ]; then
            "$ONNX_INFER_BIN" "$model_arg_1" "$model_arg_2" < "$in_file" > "$out_file" 2>/dev/null
        else
            "$ONNX_INFER_BIN" < "$in_file" > "$out_file" 2>/dev/null
        fi
        rc=$?
    fi

    return "$rc"
}

daemon_onnx_write_runtime_state() {
    local now="$1" rc="$2"
    {
        printf 'enabled=%s\n' "${ONNX_ENABLE:-0}"
        printf 'learning_enabled=%s\n' "${ONNX_LEARNING_ENABLE:-1}"
        printf 'use_default_model=%s\n' "${ONNX_USE_DEFAULT_MODEL:-1}"
        printf 'model_path=%s\n' "${ONNX_MODEL_PATH:-}"
        printf 'last_ts=%s\n' "$now"
        printf 'last_rc=%s\n' "$rc"
        printf 'infer_interval=%s\n' "${ONNX_INFER_INTERVAL:-5}"
        printf 'bad_streak=%s\n' "${ONNX_BAD_STREAK:-0}"
        printf 'circuit_until=%s\n' "${ONNX_CIRCUIT_UNTIL:-0}"
        printf 'alpha=%s\n' "${LCL_ALPHA:-0}"
        printf 'beta=%s\n' "${LCL_BETA:-0}"
        printf 'gamma=%s\n' "${LCL_GAMMA:-0}"
        printf 'delta=%s\n' "${LCL_DELTA:-0}"
    } | daemon_onnx_atomic_write_text "$ONNX_STATE_FILE" >/dev/null 2>&1 || true
}

daemon_onnx_init() {
    ONNX_ENABLE="${ONNX_ENABLE:-1}"
    case "$ONNX_ENABLE" in
        1|true|TRUE|yes|YES|on|ON) ONNX_ENABLE=1 ;;
        *) ONNX_ENABLE=0 ;;
    esac

    ONNX_INFER_INTERVAL="$(daemon_onnx_uint_or_default "${ONNX_INFER_INTERVAL:-5}" "5")"
    [ "$ONNX_INFER_INTERVAL" -lt 1 ] && ONNX_INFER_INTERVAL=1
    [ "$ONNX_INFER_INTERVAL" -gt 120 ] && ONNX_INFER_INTERVAL=120

    ONNX_INFER_TIMEOUT_SEC="$(daemon_onnx_uint_or_default "${ONNX_INFER_TIMEOUT_SEC:-2}" "2")"
    [ "$ONNX_INFER_TIMEOUT_SEC" -lt 1 ] && ONNX_INFER_TIMEOUT_SEC=1
    [ "$ONNX_INFER_TIMEOUT_SEC" -gt 15 ] && ONNX_INFER_TIMEOUT_SEC=15

    ONNX_CIRCUIT_COOLDOWN_SEC="$(daemon_onnx_uint_or_default "${ONNX_CIRCUIT_COOLDOWN_SEC:-600}" "600")"
    [ "$ONNX_CIRCUIT_COOLDOWN_SEC" -lt 30 ] && ONNX_CIRCUIT_COOLDOWN_SEC=30

    ONNX_LEARNING_ENABLE="${ONNX_LEARNING_ENABLE:-1}"
    case "$ONNX_LEARNING_ENABLE" in
        1|true|TRUE|yes|YES|on|ON) ONNX_LEARNING_ENABLE=1 ;;
        *) ONNX_LEARNING_ENABLE=0 ;;
    esac

    ONNX_USE_DEFAULT_MODEL="${ONNX_USE_DEFAULT_MODEL:-1}"
    case "$ONNX_USE_DEFAULT_MODEL" in
        1|true|TRUE|yes|YES|on|ON) ONNX_USE_DEFAULT_MODEL=1 ;;
        *) ONNX_USE_DEFAULT_MODEL=0 ;;
    esac

    ONNX_STEP_CAP="$(daemon_onnx_float_or_default "${ONNX_STEP_CAP:-0.05}" "0.05")"
    ONNX_EMA_FACTOR="$(daemon_onnx_float_or_default "${ONNX_EMA_FACTOR:-0.20}" "0.20")"

    ONNX_INFER_BIN="${ONNX_INFER_BIN:-$MODDIR/bin/infer}"
    ONNX_MODEL_PATH="${ONNX_MODEL_PATH:-$MODDIR/models/base.onnx}"
    if [ "${ONNX_USE_DEFAULT_MODEL:-1}" -eq 1 ]; then
        ONNX_MODEL_PATH="$MODDIR/models/base.onnx"
    fi
    ONNX_STATE_FILE="${ONNX_STATE_FILE:-$MODDIR/cache/onnx_runtime.state}"
    ONNX_CIRCUIT_FILE="${ONNX_CIRCUIT_FILE:-$MODDIR/cache/onnx_circuit.state}"

    ONNX_LOOP_COUNTER=0
    daemon_onnx_load_circuit_state
    daemon_onnx_log_info "onnx init enable=$ONNX_ENABLE learning=$ONNX_LEARNING_ENABLE default_model=$ONNX_USE_DEFAULT_MODEL interval=${ONNX_INFER_INTERVAL} timeout=${ONNX_INFER_TIMEOUT_SEC}s"
}

daemon_run_onnx_cycle() {
    local now infer_in infer_out infer_rc
    local da db dg dd current_score

    [ "${ONNX_INITIALIZED:-0}" -eq 1 ] || {
        daemon_onnx_init
        ONNX_INITIALIZED=1
    }

    [ "${ONNX_ENABLE:-0}" -eq 1 ] || return 0

    now="$(daemon_onnx_now_epoch)"
    now="$(daemon_onnx_uint_or_default "$now" "0")"

    if [ "${ONNX_CIRCUIT_UNTIL:-0}" -gt "$now" ]; then
        return 0
    fi

    ONNX_LOOP_COUNTER=$(( ${ONNX_LOOP_COUNTER:-0} + 1 ))
    if [ "$ONNX_LOOP_COUNTER" -lt "$ONNX_INFER_INTERVAL" ]; then
        return 0
    fi
    ONNX_LOOP_COUNTER=0

    infer_in="$TMPDIR/kp_infer_in.json"
    infer_out="$TMPDIR/kp_infer_out.json"

    daemon_onnx_build_features_json "$infer_in" || return 0

    daemon_onnx_call_infer "$infer_in" "$infer_out"
    infer_rc=$?

    if [ "$infer_rc" -eq 0 ]; then
        da="$(daemon_onnx_read_json_number_field "delta_alpha" "$infer_out")"
        db="$(daemon_onnx_read_json_number_field "delta_beta" "$infer_out")"
        dg="$(daemon_onnx_read_json_number_field "delta_gamma" "$infer_out")"
        dd="$(daemon_onnx_read_json_number_field "delta_delta" "$infer_out")"

        if [ "${ONNX_LEARNING_ENABLE:-1}" -eq 1 ]; then
            daemon_onnx_apply_weight_deltas "$da" "$db" "$dg" "$dd"
        else
            daemon_onnx_log_debug "onnx learning disabled: skipping adaptive weight update"
        fi
    fi

    current_score="$(daemon_onnx_current_score)"
    daemon_onnx_register_score_feedback "$current_score"
    daemon_onnx_write_runtime_state "$now" "$infer_rc"

    rm -f "$infer_in" "$infer_out" 2>/dev/null || true
}
