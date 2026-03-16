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

daemon_sampling_pick_interval() {
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