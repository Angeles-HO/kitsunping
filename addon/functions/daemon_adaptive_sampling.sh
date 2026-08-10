#!/system/bin/sh

daemon_adaptive_sampling_init() {
    local adaptive_sampling_prop adaptive_base_prop adaptive_degraded_prop
    local adaptive_bad_streak_prop adaptive_good_streak_prop

    adaptive_sampling_prop="$(getprop persist.kitsunping.daemon.adaptive_sampling | tr -d '\r\n')"
    [ -z "$adaptive_sampling_prop" ] && adaptive_sampling_prop="$(getprop kitsunping.daemon.adaptive_sampling | tr -d '\r\n')"

    adaptive_base_prop="$(getprop persist.kitsunping.daemon.adaptive_base_sec | tr -d '\r\n')"
    [ -z "$adaptive_base_prop" ] && adaptive_base_prop="$(getprop kitsunping.daemon.adaptive_base_sec | tr -d '\r\n')"

    adaptive_degraded_prop="$(getprop persist.kitsunping.daemon.adaptive_degraded_sec | tr -d '\r\n')"
    [ -z "$adaptive_degraded_prop" ] && adaptive_degraded_prop="$(getprop kitsunping.daemon.adaptive_degraded_sec | tr -d '\r\n')"

    adaptive_bad_streak_prop="$(getprop persist.kitsunping.daemon.adaptive_bad_streak | tr -d '\r\n')"
    [ -z "$adaptive_bad_streak_prop" ] && adaptive_bad_streak_prop="$(getprop kitsunping.daemon.adaptive_bad_streak | tr -d '\r\n')"

    adaptive_good_streak_prop="$(getprop persist.kitsunping.daemon.adaptive_good_streak | tr -d '\r\n')"
    [ -z "$adaptive_good_streak_prop" ] && adaptive_good_streak_prop="$(getprop kitsunping.daemon.adaptive_good_streak | tr -d '\r\n')"

    ADAPTIVE_SAMPLING_ENABLE=1
    case "$adaptive_sampling_prop" in
        0|false|FALSE|no|NO|off|OFF) ADAPTIVE_SAMPLING_ENABLE=0 ;;
        1|true|TRUE|yes|YES|on|ON|'') ADAPTIVE_SAMPLING_ENABLE=1 ;;
    esac

    ADAPTIVE_BASE_SEC="$(uint_or_default "$adaptive_base_prop" "30")"
    [ "$ADAPTIVE_BASE_SEC" -lt 10 ] && ADAPTIVE_BASE_SEC=10

    ADAPTIVE_DEGRADED_SEC="$(uint_or_default "$adaptive_degraded_prop" "8")"
    [ "$ADAPTIVE_DEGRADED_SEC" -lt 5 ] && ADAPTIVE_DEGRADED_SEC=5
    [ "$ADAPTIVE_DEGRADED_SEC" -gt 10 ] && ADAPTIVE_DEGRADED_SEC=10

    ADAPTIVE_BAD_STREAK="$(uint_or_default "$adaptive_bad_streak_prop" "2")"
    [ "$ADAPTIVE_BAD_STREAK" -lt 1 ] && ADAPTIVE_BAD_STREAK=1

    ADAPTIVE_GOOD_STREAK="$(uint_or_default "$adaptive_good_streak_prop" "3")"
    [ "$ADAPTIVE_GOOD_STREAK" -lt 1 ] && ADAPTIVE_GOOD_STREAK=1

    ADAPTIVE_WIFI_SCORE_THRESHOLD="$(uint_or_default "${ADAPTIVE_WIFI_SCORE_THRESHOLD:-65}" "65")"
    ADAPTIVE_WIFI_LATENCY_THRESHOLD_MS="$(uint_or_default "${ADAPTIVE_WIFI_LATENCY_THRESHOLD_MS:-120}" "120")"
    ADAPTIVE_WIFI_JITTER_THRESHOLD_MS="$(uint_or_default "${ADAPTIVE_WIFI_JITTER_THRESHOLD_MS:-30}" "30")"
    ADAPTIVE_WIFI_LOSS_THRESHOLD_PCT="$(uint_or_default "${ADAPTIVE_WIFI_LOSS_THRESHOLD_PCT:-5}" "5")"

    daemon_adaptive_bad_streak=0
    daemon_adaptive_good_streak=0
    DAEMON_SAMPLE_MODE="base"
    DAEMON_SAMPLE_REASON="startup"
    DAEMON_SAMPLE_INTERVAL_SEC="${INTERVAL:-10}"
}

daemon_sampling_should_degrade() {
    DAEMON_SAMPLE_REASON="stable"

    if [ "${wifi_state:-unknown}" != "connected" ]; then
        case "${WIFI_IFACE:-none}" in
            wlan*|swlan*) DAEMON_SAMPLE_REASON="wifi_not_connected"; return 0 ;;
        esac
        return 1
    fi

    case "${wifi_quality_reason:-}" in
        bad|limbo) DAEMON_SAMPLE_REASON="wifi_quality_${wifi_quality_reason}"; return 0 ;;
    esac

    case "${wifi_score:-}" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$wifi_score" -lt "$ADAPTIVE_WIFI_SCORE_THRESHOLD" ]; then
                DAEMON_SAMPLE_REASON="wifi_score_low"
                return 0
            fi
            ;;
    esac

    case "${wifi_latency_ms:-}" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$wifi_latency_ms" -ge "$ADAPTIVE_WIFI_LATENCY_THRESHOLD_MS" ]; then
                DAEMON_SAMPLE_REASON="wifi_latency_high"
                return 0
            fi
            ;;
    esac

    case "${wifi_jitter_ms:-}" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$wifi_jitter_ms" -ge "$ADAPTIVE_WIFI_JITTER_THRESHOLD_MS" ]; then
                DAEMON_SAMPLE_REASON="wifi_jitter_high"
                return 0
            fi
            ;;
    esac

    case "${wifi_loss_pct:-}" in
        ''|*[!0-9]*) ;;
        *)
            if [ "$wifi_loss_pct" -ge "$ADAPTIVE_WIFI_LOSS_THRESHOLD_PCT" ]; then
                DAEMON_SAMPLE_REASON="wifi_loss_high"
                return 0
            fi
            ;;
    esac

    case "${wifi_loss_trend_pct:-}" in
        +*)
            trend_abs="${wifi_loss_trend_pct#+}"
            case "$trend_abs" in
                ''|*[!0-9]*) ;;
                *)
                    if [ "$trend_abs" -ge 2 ]; then
                        DAEMON_SAMPLE_REASON="wifi_loss_trending_up"
                        return 0
                    fi
                    ;;
            esac
            ;;
    esac

    if [ "${wifi_probe_ok:-1}" != "1" ]; then
        DAEMON_SAMPLE_REASON="wifi_probe_fail"
        return 0
    fi

    return 1
}

daemon_sampling_pick_interval_bash() {
    local base_interval="$1" desired

    case "$base_interval" in ''|*[!0-9]* ) base_interval="${INTERVAL:-10}" ;; esac

    if [ "${ADAPTIVE_SAMPLING_ENABLE:-1}" -ne 1 ]; then
        DAEMON_SAMPLE_MODE="fixed"
        DAEMON_SAMPLE_REASON="adaptive_off"
        DAEMON_SAMPLE_INTERVAL_SEC="$base_interval"
        printf '%s' "$base_interval"
        return 0
    fi

    if daemon_sampling_should_degrade; then
        daemon_adaptive_bad_streak=$((daemon_adaptive_bad_streak + 1))
        daemon_adaptive_good_streak=0
        if [ "$daemon_adaptive_bad_streak" -ge "${ADAPTIVE_BAD_STREAK:-2}" ]; then
            DAEMON_SAMPLE_MODE="degraded"
        fi
    else
        daemon_adaptive_good_streak=$((daemon_adaptive_good_streak + 1))
        daemon_adaptive_bad_streak=0
        if [ "$daemon_adaptive_good_streak" -ge "${ADAPTIVE_GOOD_STREAK:-3}" ]; then
            DAEMON_SAMPLE_MODE="base"
        fi
    fi

    if [ "$DAEMON_SAMPLE_MODE" = "degraded" ]; then
        desired="${ADAPTIVE_DEGRADED_SEC:-8}"
    else
        desired="${ADAPTIVE_BASE_SEC:-30}"
    fi

    DAEMON_SAMPLE_INTERVAL_SEC="$desired"
    printf '%s' "$desired"
}

daemon_sampling_pick_interval() {
    local base_interval="$1" native_bin timeout_sec native_output
    local interval mode reason bad_streak good_streak line key value
    local interval_seen=0 mode_seen=0 reason_seen=0 bad_seen=0 good_seen=0
    local wifi_score_arg wifi_latency_arg wifi_jitter_arg wifi_loss_arg

    interval=""
    mode=""
    reason=""
    bad_streak=""
    good_streak=""

    case "$base_interval" in ''|*[!0-9]*) base_interval="${INTERVAL:-10}" ;; esac

    if [ -n "${KITSUNPINGD_ADAPTIVE_BIN:-}" ]; then
        native_bin="$KITSUNPINGD_ADAPTIVE_BIN"
    elif [ -x /data/local/tmp/kitsunping_dev/bin/kitsunpingd ]; then
        native_bin=/data/local/tmp/kitsunping_dev/bin/kitsunpingd
    else
        native_bin="${MODDIR:-/data/adb/modules/Kitsunping}/bin/kitsunpingd"
    fi
    timeout_sec="${KITSUNPINGD_ADAPTIVE_TIMEOUT_SEC:-1}"
    case "$timeout_sec" in ''|*[!0-9]*) timeout_sec=1 ;; esac
    [ "$timeout_sec" -lt 1 ] && timeout_sec=1

    [ -x "$native_bin" ] && command -v timeout >/dev/null 2>&1 || {
        daemon_sampling_pick_interval_bash "$base_interval"
        return
    }

    wifi_score_arg="${wifi_score:-}"
    case "$wifi_score_arg" in *[!0-9]*) wifi_score_arg="" ;; esac
    wifi_latency_arg="${wifi_latency_ms:-}"
    case "$wifi_latency_arg" in *[!0-9]*) wifi_latency_arg="" ;; esac
    wifi_jitter_arg="${wifi_jitter_ms:-}"
    case "$wifi_jitter_arg" in *[!0-9]*) wifi_jitter_arg="" ;; esac
    wifi_loss_arg="${wifi_loss_pct:-}"
    case "$wifi_loss_arg" in *[!0-9]*) wifi_loss_arg="" ;; esac

    native_output="$(timeout "$timeout_sec" "$native_bin" --adaptive-sampling \
        --base-interval "$base_interval" \
        --enabled "${ADAPTIVE_SAMPLING_ENABLE:-1}" \
        --mode "${DAEMON_SAMPLE_MODE:-base}" \
        --wifi-iface "${WIFI_IFACE:-none}" \
        --wifi-state "${wifi_state:-unknown}" \
        --wifi-quality-reason "${wifi_quality_reason:-}" \
        --wifi-score "$wifi_score_arg" \
        --wifi-latency-ms "$wifi_latency_arg" \
        --wifi-jitter-ms "$wifi_jitter_arg" \
        --wifi-loss-pct "$wifi_loss_arg" \
        --wifi-loss-trend-pct "${wifi_loss_trend_pct:-}" \
        --wifi-probe-ok "${wifi_probe_ok:-1}" \
        --bad-streak "${daemon_adaptive_bad_streak:-0}" \
        --good-streak "${daemon_adaptive_good_streak:-0}" \
        --required-bad-streak "${ADAPTIVE_BAD_STREAK:-2}" \
        --required-good-streak "${ADAPTIVE_GOOD_STREAK:-3}" \
        --base-seconds "${ADAPTIVE_BASE_SEC:-30}" \
        --degraded-seconds "${ADAPTIVE_DEGRADED_SEC:-8}" \
        --wifi-score-threshold "${ADAPTIVE_WIFI_SCORE_THRESHOLD:-65}" \
        --wifi-latency-threshold-ms "${ADAPTIVE_WIFI_LATENCY_THRESHOLD_MS:-120}" \
        --wifi-jitter-threshold-ms "${ADAPTIVE_WIFI_JITTER_THRESHOLD_MS:-30}" \
        --wifi-loss-threshold-pct "${ADAPTIVE_WIFI_LOSS_THRESHOLD_PCT:-5}" 2>/dev/null)" || native_output=""

    while IFS= read -r line || [ -n "$line" ]; do
        key="${line%%=*}"
        value="${line#*=}"
        [ "$key" != "$line" ] || { native_output=""; break; }
        case "$key" in
            interval) [ "$interval_seen" -eq 0 ] || { native_output=""; break; }; interval="$value"; interval_seen=1 ;;
            mode) [ "$mode_seen" -eq 0 ] || { native_output=""; break; }; mode="$value"; mode_seen=1 ;;
            reason) [ "$reason_seen" -eq 0 ] || { native_output=""; break; }; reason="$value"; reason_seen=1 ;;
            bad_streak) [ "$bad_seen" -eq 0 ] || { native_output=""; break; }; bad_streak="$value"; bad_seen=1 ;;
            good_streak) [ "$good_seen" -eq 0 ] || { native_output=""; break; }; good_streak="$value"; good_seen=1 ;;
            *) native_output=""; break ;;
        esac
    done <<EOF
$native_output
EOF

    case "$interval:$bad_streak:$good_streak" in *[!0-9:]*|::*) native_output="" ;; esac
    case "$mode" in base|degraded|fixed) ;; *) native_output="" ;; esac
    case "$reason" in ''|*[!a-z_]* ) native_output="" ;; esac
    [ "$interval_seen:$mode_seen:$reason_seen:$bad_seen:$good_seen" = "1:1:1:1:1" ] || native_output=""

    if [ -n "$native_output" ]; then
        DAEMON_SAMPLE_MODE="$mode"
        DAEMON_SAMPLE_REASON="$reason"
        DAEMON_SAMPLE_INTERVAL_SEC="$interval"
        daemon_adaptive_bad_streak="$bad_streak"
        daemon_adaptive_good_streak="$good_streak"
        printf '%s' "$interval"
        return 0
    fi

    command -v log_warning >/dev/null 2>&1 && log_warning "adaptive sampling Rust result invalid; using Bash fallback"
    daemon_sampling_pick_interval_bash "$base_interval"
}