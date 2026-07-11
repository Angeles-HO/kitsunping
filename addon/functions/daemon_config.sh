#!/system/bin/sh

daemon_normalize_weight_value() {
    local raw="$1" def="$2"
    LC_ALL=C awk -v v="$raw" -v d="$def" 'BEGIN {
        out = ""
        if (v ~ /^-?[0-9]+([.][0-9]+)?$/) {
            n = v + 0
            if (n < 0) n = 0
            if (n > 1) n = 1
            out = sprintf("%.4f", n)
        } else {
            out = sprintf("%.4f", d + 0)
        }
        sub(/0+$/, "", out)
        sub(/[.]$/, "", out)
        if (out == "") out = "0"
        printf "%s", out
    }'
}

daemon_normalize_sigmoid_weights() {
    local a="$1" b="$2" g="$3" d="$4"
    LC_ALL=C awk -v a="$a" -v b="$b" -v g="$g" -v d="$d" 'BEGIN {
        sum = a + b + g
        if (sum <= 0) { a = 0.4; b = 0.3; g = 0.3; sum = 1.0 }
        if (sum != 1.0) { a = a/sum; b = b/sum; g = g/sum }
        if (d < 0) d = 0
        if (d > 0.5) d = 0.5
        printf "%.4f %.4f %.4f %.4f", a, b, g, d
    }'
}

daemon_load_runtime_config() {
    local interval_prop signal_poll_prop net_probe_prop
    local conf_alpha conf_beta conf_gamma
    local router_debug_raw kitsunrouter_enable_raw kitsunrouter_debug_raw
    local router_experimental_raw router_experimental_raw_2
    local router_openwrt_raw router_openwrt_raw_2
    local router_cache_ttl_raw router_cache_ttl_raw_2
    local router_infer_width_raw router_infer_width_raw_2
    local router_infer_width_2g_raw router_infer_width_2g_raw_2
    local onnx_enable_raw onnx_enable_raw_2
    local onnx_infer_interval_raw onnx_infer_interval_raw_2
    local onnx_infer_timeout_raw onnx_infer_timeout_raw_2
    local onnx_circuit_cooldown_raw onnx_circuit_cooldown_raw_2
    local onnx_learning_enable_raw onnx_learning_enable_raw_2
    local onnx_use_default_model_raw onnx_use_default_model_raw_2
    local onnx_model_path_raw onnx_model_path_raw_2

    DAEMON_INTERVAL="${DAEMON_INTERVAL:-10}"
    LAST_TS_WIFI_LEFT=0
    LAST_TS_WIFI_JOINED=0
    LAST_TS_IFACE_CHANGED=0
    INTERVAL_DEFAULT=10
    INTERVAL="$INTERVAL_DEFAULT"
    SIGNAL_POLL_INTERVAL=5
    NET_PROBE_INTERVAL=3

    interval_prop="$(getprop kitsunping.daemon.interval | tr -d '\r\n')"
    signal_poll_prop="$(getprop kitsunping.daemon.signal_poll_interval | tr -d '\r\n')"
    net_probe_prop="$(getprop kitsunping.daemon.net_probe_interval | tr -d '\r\n')"
    interval_prop="$(uint_or_default "$interval_prop" "")"
    signal_poll_prop="$(uint_or_default "$signal_poll_prop" "")"
    net_probe_prop="$(uint_or_default "$net_probe_prop" "")"

    CONF_ALPHA="$(getprop kitsunping.sigmoid.alpha)"
    CONF_BETA="$(getprop kitsunping.sigmoid.beta)"
    CONF_GAMMA="$(getprop kitsunping.sigmoid.gamma)"

    conf_alpha="$(daemon_normalize_weight_value "${CONF_ALPHA:-}" "0.4")"
    conf_beta="$(daemon_normalize_weight_value "${CONF_BETA:-}" "0.3")"
    conf_gamma="$(daemon_normalize_weight_value "${CONF_GAMMA:-}" "0.3")"
    local conf_delta
    conf_delta="$(daemon_normalize_weight_value "$(getprop kitsunping.sigmoid.delta)" "0.1")"

    local _norm
    _norm="$(daemon_normalize_sigmoid_weights "$conf_alpha" "$conf_beta" "$conf_gamma" "$conf_delta")"
    LCL_ALPHA="${_norm%% *}"; _norm="${_norm#* }"
    LCL_BETA="${_norm%% *}";  _norm="${_norm#* }"
    LCL_GAMMA="${_norm%% *}"; LCL_DELTA="${_norm#* }"

    onnx_enable_raw="$(getprop persist.kitsunping.onnx.enable)"
    onnx_enable_raw_2="$(getprop kitsunping.onnx.enable)"
    onnx_infer_interval_raw="$(getprop persist.kitsunping.onnx.infer_interval)"
    onnx_infer_interval_raw_2="$(getprop kitsunping.onnx.infer_interval)"
    onnx_infer_timeout_raw="$(getprop persist.kitsunping.onnx.infer_timeout_sec)"
    onnx_infer_timeout_raw_2="$(getprop kitsunping.onnx.infer_timeout_sec)"
    onnx_circuit_cooldown_raw="$(getprop persist.kitsunping.onnx.circuit_cooldown_sec)"
    onnx_circuit_cooldown_raw_2="$(getprop kitsunping.onnx.circuit_cooldown_sec)"
    onnx_learning_enable_raw="$(getprop persist.kitsunping.onnx.learning_enable)"
    onnx_learning_enable_raw_2="$(getprop kitsunping.onnx.learning_enable)"
    onnx_use_default_model_raw="$(getprop persist.kitsunping.onnx.use_default_model)"
    onnx_use_default_model_raw_2="$(getprop kitsunping.onnx.use_default_model)"
    onnx_model_path_raw="$(getprop persist.kitsunping.onnx.model_path | tr -d '\r\n')"
    onnx_model_path_raw_2="$(getprop kitsunping.onnx.model_path | tr -d '\r\n')"

    ONNX_ENABLE="${ONNX_ENABLE:-${onnx_enable_raw:-$onnx_enable_raw_2}}"
    case "${ONNX_ENABLE:-}" in
        1|true|TRUE|yes|YES|on|ON|'') ONNX_ENABLE=1 ;;
        *) ONNX_ENABLE=0 ;;
    esac

    ONNX_INFER_INTERVAL="${ONNX_INFER_INTERVAL:-${onnx_infer_interval_raw:-$onnx_infer_interval_raw_2}}"
    ONNX_INFER_INTERVAL="$(uint_or_default "$ONNX_INFER_INTERVAL" "5")"
    [ "$ONNX_INFER_INTERVAL" -lt 1 ] && ONNX_INFER_INTERVAL=1
    [ "$ONNX_INFER_INTERVAL" -gt 120 ] && ONNX_INFER_INTERVAL=120

    ONNX_INFER_TIMEOUT_SEC="${ONNX_INFER_TIMEOUT_SEC:-${onnx_infer_timeout_raw:-$onnx_infer_timeout_raw_2}}"
    ONNX_INFER_TIMEOUT_SEC="$(uint_or_default "$ONNX_INFER_TIMEOUT_SEC" "2")"
    [ "$ONNX_INFER_TIMEOUT_SEC" -lt 1 ] && ONNX_INFER_TIMEOUT_SEC=1
    [ "$ONNX_INFER_TIMEOUT_SEC" -gt 15 ] && ONNX_INFER_TIMEOUT_SEC=15

    ONNX_CIRCUIT_COOLDOWN_SEC="${ONNX_CIRCUIT_COOLDOWN_SEC:-${onnx_circuit_cooldown_raw:-$onnx_circuit_cooldown_raw_2}}"
    ONNX_CIRCUIT_COOLDOWN_SEC="$(uint_or_default "$ONNX_CIRCUIT_COOLDOWN_SEC" "600")"
    [ "$ONNX_CIRCUIT_COOLDOWN_SEC" -lt 30 ] && ONNX_CIRCUIT_COOLDOWN_SEC=30

    ONNX_LEARNING_ENABLE="${ONNX_LEARNING_ENABLE:-${onnx_learning_enable_raw:-$onnx_learning_enable_raw_2}}"
    case "${ONNX_LEARNING_ENABLE:-}" in
        1|true|TRUE|yes|YES|on|ON|'') ONNX_LEARNING_ENABLE=1 ;;
        *) ONNX_LEARNING_ENABLE=0 ;;
    esac

    ONNX_USE_DEFAULT_MODEL="${ONNX_USE_DEFAULT_MODEL:-${onnx_use_default_model_raw:-$onnx_use_default_model_raw_2}}"
    case "${ONNX_USE_DEFAULT_MODEL:-}" in
        1|true|TRUE|yes|YES|on|ON|'') ONNX_USE_DEFAULT_MODEL=1 ;;
        *) ONNX_USE_DEFAULT_MODEL=0 ;;
    esac

    ONNX_MODEL_PATH="${ONNX_MODEL_PATH:-${onnx_model_path_raw:-$onnx_model_path_raw_2}}"
    if [ "${ONNX_USE_DEFAULT_MODEL:-1}" -eq 1 ] || [ -z "$ONNX_MODEL_PATH" ]; then
        ONNX_MODEL_PATH="$MODDIR/models/base.onnx"
    fi

    router_debug_raw="$(getprop kitsunping.router.debug)"
    kitsunrouter_enable_raw="$(getprop persist.kitsunrouter.enable)"
    kitsunrouter_debug_raw="$(getprop persist.kitsunrouter.debug)"
    router_experimental_raw="$(getprop persist.kitsunping.router.experimental)"
    router_experimental_raw_2="$(getprop kitsunping.router.experimental)"
    router_openwrt_raw="$(getprop persist.kitsunping.router.openwrt_mode)"
    router_openwrt_raw_2="$(getprop kitsunping.router.openwrt_mode)"
    router_cache_ttl_raw="$(getprop persist.kitsunping.router.cache_ttl)"
    router_cache_ttl_raw_2="$(getprop kitsunping.router.cache_ttl)"
    router_infer_width_raw="$(getprop persist.kitsunping.router.infer_width)"
    router_infer_width_raw_2="$(getprop kitsunping.router.infer_width)"
    router_infer_width_2g_raw="$(getprop persist.kitsunping.router.infer_width_2g)"
    router_infer_width_2g_raw_2="$(getprop kitsunping.router.infer_width_2g)"

    ROUTER_DEBUG_RAW="$router_debug_raw"
    KITSUNROUTER_ENABLE_RAW="$kitsunrouter_enable_raw"
    KITSUNROUTER_DEBUG_RAW="$kitsunrouter_debug_raw"
    ROUTER_EXPERIMENTAL_RAW="$router_experimental_raw"
    ROUTER_EXPERIMENTAL_RAW_2="$router_experimental_raw_2"
    ROUTER_OPENWRT_RAW="$router_openwrt_raw"
    ROUTER_OPENWRT_RAW_2="$router_openwrt_raw_2"
    ROUTER_CACHE_TTL_RAW="$router_cache_ttl_raw"
    ROUTER_CACHE_TTL_RAW_2="$router_cache_ttl_raw_2"
    ROUTER_INFER_WIDTH_RAW="$router_infer_width_raw"
    ROUTER_INFER_WIDTH_RAW_2="$router_infer_width_raw_2"
    ROUTER_INFER_WIDTH_2G_RAW="$router_infer_width_2g_raw"
    ROUTER_INFER_WIDTH_2G_RAW_2="$router_infer_width_2g_raw_2"

    WIFI_SPEED_THRESHOLD="$(getprop kitsunping.wifi.speed_threshold | tr -d '\r\n')"
    WIFI_SPEED_THRESHOLD="$(uint_or_default "$WIFI_SPEED_THRESHOLD" "75")"

    EMIT_EVENTS_RAW="$(getprop persist.kitsunping.emit_events)"
    EVENT_DEBOUNCE_RAW="$(getprop persist.kitsunping.event_debounce_sec)"
    EVENT_DEBOUNCE_RAW_2="$(getprop kitsunping.event.debounce_sec)"

    EMIT_EVENTS_RAW="${EMIT_EVENTS_RAW:-1}"
    EMIT_EVENTS=1
    EVENT_DEBOUNCE_SEC=""

    case "${EMIT_EVENTS_RAW:-}" in
        0|false|FALSE|no|NO|off|OFF) EMIT_EVENTS=0 ;;
        1|true|TRUE|yes|YES|on|ON|'') EMIT_EVENTS=1 ;;
        *[!0-9]* ) EMIT_EVENTS=1 ;;
        *)
            if [ "$EMIT_EVENTS_RAW" -gt 1 ] && [ -z "$EVENT_DEBOUNCE_RAW" ] && [ -z "$EVENT_DEBOUNCE_RAW_2" ]; then
                EVENT_DEBOUNCE_SEC="$EMIT_EVENTS_RAW"
            fi
            EMIT_EVENTS=1
            ;;
    esac

    if [ -z "$EVENT_DEBOUNCE_SEC" ]; then
        case "${EVENT_DEBOUNCE_RAW:-$EVENT_DEBOUNCE_RAW_2}" in
            ''|*[!0-9]* ) EVENT_DEBOUNCE_SEC=60 ;;
            *)
                if [ "${EVENT_DEBOUNCE_RAW:-$EVENT_DEBOUNCE_RAW_2}" -gt 0 ]; then
                    EVENT_DEBOUNCE_SEC="${EVENT_DEBOUNCE_RAW:-$EVENT_DEBOUNCE_RAW_2}"
                else
                    EVENT_DEBOUNCE_SEC=60
                fi
                ;;
        esac
    fi

    ROUTER_DEBUG="${ROUTER_DEBUG:-$ROUTER_DEBUG_RAW}"
    case "${ROUTER_DEBUG:-}" in
        1|true|TRUE|yes|YES|on|ON) ROUTER_DEBUG=1 ;;
        *) ROUTER_DEBUG=0 ;;
    esac

    KITSUNROUTER_ENABLE="${KITSUNROUTER_ENABLE:-$KITSUNROUTER_ENABLE_RAW}"
    case "${KITSUNROUTER_ENABLE:-}" in
        1|true|TRUE|yes|YES|on|ON) KITSUNROUTER_ENABLE=1 ;;
        *) KITSUNROUTER_ENABLE=0 ;;
    esac

    if [ -n "${KITSUNROUTER_DEBUG_RAW:-}" ]; then
        case "${KITSUNROUTER_DEBUG_RAW:-}" in
            1|true|TRUE|yes|YES|on|ON) ROUTER_DEBUG=1 ;;
            *) ROUTER_DEBUG=0 ;;
        esac
    fi

    ROUTER_EXPERIMENTAL="${ROUTER_EXPERIMENTAL:-${ROUTER_EXPERIMENTAL_RAW:-$ROUTER_EXPERIMENTAL_RAW_2}}"
    case "${ROUTER_EXPERIMENTAL:-}" in
        1|true|TRUE|yes|YES|on|ON) ROUTER_EXPERIMENTAL=1 ;;
        *) ROUTER_EXPERIMENTAL=0 ;;
    esac

    ROUTER_OPENWRT_MODE="${ROUTER_OPENWRT_MODE:-${ROUTER_OPENWRT_RAW:-$ROUTER_OPENWRT_RAW_2}}"
    case "${ROUTER_OPENWRT_MODE:-}" in
        1|true|TRUE|yes|YES|on|ON) ROUTER_OPENWRT_MODE=1 ;;
        *) ROUTER_OPENWRT_MODE=0 ;;
    esac

    ROUTER_CACHE_TTL="${ROUTER_CACHE_TTL:-${ROUTER_CACHE_TTL_RAW:-$ROUTER_CACHE_TTL_RAW_2}}"
    case "${ROUTER_CACHE_TTL:-}" in
        ''|*[!0-9]* ) ROUTER_CACHE_TTL=3600 ;;
    esac

    ROUTER_INFER_WIDTH="${ROUTER_INFER_WIDTH:-${ROUTER_INFER_WIDTH_RAW:-$ROUTER_INFER_WIDTH_RAW_2}}"
    case "${ROUTER_INFER_WIDTH:-}" in
        1|true|TRUE|yes|YES|on|ON) ROUTER_INFER_WIDTH=1 ;;
        *) ROUTER_INFER_WIDTH=0 ;;
    esac

    ROUTER_INFER_WIDTH_2G="${ROUTER_INFER_WIDTH_2G:-${ROUTER_INFER_WIDTH_2G_RAW:-$ROUTER_INFER_WIDTH_2G_RAW_2}}"
    case "${ROUTER_INFER_WIDTH_2G:-}" in
        1|true|TRUE|yes|YES|on|ON) ROUTER_INFER_WIDTH_2G=1 ;;
        *) ROUTER_INFER_WIDTH_2G=0 ;;
    esac

    DAEMON_CONFIG_INTERVAL_PROP="$interval_prop"
    DAEMON_CONFIG_SIGNAL_POLL_PROP="$signal_poll_prop"
    DAEMON_CONFIG_NET_PROBE_PROP="$net_probe_prop"
}