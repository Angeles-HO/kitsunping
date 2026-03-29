#!/system/bin/sh
# Net Calibrate.sh Script
# Version: 5.4 - non release
# Description: This script calibrates network properties for optimal performance.
# Status: re open - 26/02/2026
# DONE: Optional IPv6 calibration path (ping6 + route validation + IPv4 fallback)
# DONE: Granular latency metrics optional path (P90/P99) with fallback to legacy scoring
# TODO: [PENDING] Add option for continuous background calibration with adaptive intervals (requires daemon integration) TODO:
# TODO: [PENDING] Add support for saving historical calibration data and trends (requires lightweight DB or log rotation) TODO:
# TODO: [PENDING] Implement a more robust caching mechanism that considers multiple factors (e.g., signal strength, recent connectivity changes) rather than just provider and time-based expiration. TODO:
# Global variables
# NOTE: This script is commonly *sourced* by executor.sh. When sourced, $0 is the
# caller, so prefer caller-provided NEWMODPATH/MODDIR and avoid clobbering them.
if [ -z "${NEWMODPATH:-}" ] || [ ! -d "${NEWMODPATH:-/}" ]; then
    if [ -n "${MODDIR:-}" ] && [ -d "${MODDIR:-/}" ]; then
        NEWMODPATH="$MODDIR"
    else
        # Best-effort derive module root from caller path.
        _caller_dir="${0%/*}"
        case "$_caller_dir" in
            */calibration) NEWMODPATH="${_caller_dir%%/calibration}" ;;
            */addon/Net_Calibrate) NEWMODPATH="${_caller_dir%%/addon/Net_Calibrate}" ;;
            */addon/*) NEWMODPATH="${_caller_dir%%/addon/*}" ;;
            */addon) NEWMODPATH="${_caller_dir%%/addon}" ;;
            *) NEWMODPATH="${_caller_dir%/*}" ;;
        esac
    fi
fi

: "${MODDIR:=$NEWMODPATH}"

uint_or_default() {
    local raw="$1" def="$2"
    case "$raw" in
        ''|*[!0-9]*) printf '%s' "$def" ;;
        *) printf '%s' "$raw" ;;
    esac
}

is_enabled_token() {
    case "$1" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
    esac
    return 1
}

is_granular_latency_enabled() {
    local raw
    raw="${CALIBRATE_GRANULAR_LATENCY_ENABLE:-$(getprop persist.kitsunping.calibrate_granular_latency_enable 2>/dev/null | tr -d '\r\n')}"
    [ -z "$raw" ] && raw=0
    is_enabled_token "$raw"
}

network_hints_load() {
    [ "${NETWORK_HINTS_LOADED:-0}" = "1" ] && return 0

    NETWORK_HINTS_LOADED=1
    NETWORK_HINTS_SOURCE=""

    for candidate in \
        "$MODDIR/cache/network_hints.env" \
        "$MODDIR/configs/network_hints.env"
    do
        [ -f "$candidate" ] || continue
        . "$candidate" 2>/dev/null || continue
        NETWORK_HINTS_SOURCE="$candidate"
        break
    done
}

network_hints_iso_country() {
    network_hints_load
    printf '%s' "${NETWORK_HINTS_ACTIVE_ISO:-}"
}

network_hints_numeric() {
    network_hints_load
    printf '%s' "${NETWORK_HINTS_ACTIVE_NUMERIC:-}"
}

get_active_default_iface() {
    local iface

    iface=$(ip route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
    [ -z "$iface" ] && iface=$(ip -6 route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
    [ -z "$iface" ] && iface=$(awk '$2=="00000000"{print $1; exit}' /proc/self/net/route 2>/dev/null)

    printf '%s' "$iface"
}

get_transport_key_from_iface() {
    local iface="$1"
    case "$iface" in
        rmnet*|ccmni*) printf '%s' "mobile" ;;
        wlan*|swlan*) printf '%s' "wifi" ;;
        *) printf '%s' "unknown" ;;
    esac
}

is_ipv6_literal() {
    case "$1" in
        *:*) return 0 ;;
    esac
    return 1
}

detect_ping6_binary() {
    local c

    if c="$(command -v ping6 2>/dev/null)" && [ -x "$c" ]; then
        PING6_BIN="$c"
        return 0
    fi

    for c in \
        /system/bin/ping6 \
        /system/xbin/ping6 \
        /vendor/bin/ping6
    do
        if [ -x "$c" ]; then
            PING6_BIN="$c"
            return 0
        fi
    done

    return 1
}

ipv6_route_usable() {
    local target="$1"
    local iface="$2"

    [ -n "$target" ] || return 1

    if ip -6 route get "$target" >/dev/null 2>&1; then
        return 0
    fi

    if [ -n "$iface" ] && ip -6 route get "$target" oif "$iface" >/dev/null 2>&1; then
        return 0
    fi

    # Android policy routing fallback:
    # if the active iface has global IPv6 and any default route in any table,
    # treat route as usable and let ping6 be the final validator.
    if [ -n "$iface" ] && \
       ip -6 addr show dev "$iface" 2>/dev/null | grep -q 'scope global' && \
       ip -6 route show table all 2>/dev/null | grep -Eq "^default .* dev ${iface}( |$)"; then
        return 0
    fi

    return 1
}

select_calibration_ping_mode() {
    local active_iface="$1"
    local ipv6_enable_raw ipv6_target

    CALIBRATE_PING_BIN="$PING_BIN"
    CALIBRATE_TARGET_IS_IPV6=0

    ipv6_enable_raw="${CALIBRATE_IPV6_ENABLE:-$(getprop persist.kitsunping.calibrate_ipv6_enable 2>/dev/null | tr -d '\r\n')}"
    [ -z "$ipv6_enable_raw" ] && ipv6_enable_raw=0

    case "$ipv6_enable_raw" in
        1|true|TRUE|yes|YES|on|ON)
            ipv6_target="${CALIBRATE_IPV6_TARGET:-$(getprop persist.kitsunping.calibrate_ipv6_target 2>/dev/null | tr -d '\r\n')}"
            [ -z "$ipv6_target" ] && ipv6_target="2001:4860:4860::8888"

            if ! is_ipv6_literal "$ipv6_target"; then
                log_warning "IPv6 calibration requested but target is not IPv6: $ipv6_target; falling back to IPv4" >> "$trace_log"
                return 0
            fi

            if ! detect_ping6_binary; then
                log_warning "IPv6 calibration requested but ping6 binary not found; falling back to IPv4" >> "$trace_log"
                return 0
            fi

            if ! ipv6_route_usable "$ipv6_target" "$active_iface"; then
                log_warning "IPv6 calibration requested but no usable IPv6 route to $ipv6_target (iface=$active_iface); falling back to IPv4" >> "$trace_log"
                return 0
            fi

            CALIBRATE_PING_BIN="$PING6_BIN"
            CALIBRATE_TARGET_IS_IPV6=1
            PING_VAL="$ipv6_target"
            log_info "IPv6 calibration enabled: target=$PING_VAL ping_bin=$CALIBRATE_PING_BIN iface=${active_iface:-unknown}" >> "$trace_log"
            ;;
        *)
            ;;
    esac
}

# Keep legacy variable names for internal references.
NET_PROPERTIES_KEYS="ro.ril.hsupa.category ro.ril.hsdpa.category" # Priority, for [upload and download] WIFI
NET_OTHERS_PROPERTIES_KEYS="ro.ril.lte.category ro.ril.ltea.category ro.ril.nr5g.category" # Priority, for [LTE, LTEA, 5G] Data
NET_VAL_HSUPA="10 12 14 16 18 20 22 24 26" # Testing values for higher upload
NET_VAL_HSDPA="10 11 12 13 14 15 16 17 18" # Testing values for higher download
NET_VAL_LTE="6 9 10 12 13 15 16" # Testing values for LTE data technology
NET_VAL_LTEA="9 10 12 13 15 16 18 21" # Testing values for LTEA data technology
NET_VAL_5G="1 2 3 4" # Testing values for 5G data technology

# Logs Variables
NETMETER_FILE="$NEWMODPATH/logs/calibrate.log"
trace_log="/sdcard/trace_log.log"

# Binarys Variables
jqbin=""
ipbin=""
pingbin=""

# Cache for Calibrate.sh optimizations
CACHE_DIR_cln="$NEWMODPATH/cache"
data_dir="$NEWMODPATH/calibration/data"
fallback_json="$data_dir/unknown.json"
cache_dir="$data_dir/cache"
ml_cache_dir="$CACHE_DIR_cln/ml"
ml_features_file="$ml_cache_dir/calibration_features.jsonl"
ml_last_file="$ml_cache_dir/last_calibration_feature.json"

## Cache for states
CALIBRATE_STATE_RUN="$NEWMODPATH/cache/calibrate.state"
CALIBRATE_LAST_RUN="$NEWMODPATH/cache/calibrate.ts"
CALIBRATE_PROGRESS_FILE="$NEWMODPATH/cache/calibrate.progress"

# Calibration cache (best values) - avoids re-calibrating from scratch every boot.
# Cache is keyed by provider/operator string (from configure_network JSON).
CALIBRATE_CACHE_ENV="$NEWMODPATH/cache/calibrate.best.env"
CALIBRATE_CACHE_META="$NEWMODPATH/cache/calibrate.best.meta"

# Defensive: installation zips may omit empty directories, so create cache/log paths explicitly.
mkdir -p "$CACHE_DIR_cln" "${NETMETER_FILE%/*}" "$cache_dir" "$ml_cache_dir" 2>/dev/null || true

json_escape() {
    # Minimal JSON string escaping for shell-generated payloads.
    printf '%s' "$1" \
        | sed 's/\\/\\\\/g; s/"/\\"/g; s/'"$'\r'"'/\\r/g; s/'"$'\n'"'/\\n/g; s/'"$'\t'"'/\\t/g'
}

num_or_null() {
    case "$1" in
        ''|*[!0-9.-]*|*.*.*|-|-.*-*) printf 'null' ;;
        *) printf '%s' "$1" ;;
    esac
}

calibrate_get_wifi_rssi_dbm() {
    local rssi
    rssi="$(dumpsys wifi 2>/dev/null | awk -F'RSSI: ' '/RSSI:/{split($2,a,",|[ ]"); print a[1]; exit}')"
    case "$rssi" in
        ''|*[!0-9-]*) printf '' ;;
        *) printf '%s' "$rssi" ;;
    esac
}

calibrate_get_radio_network_type() {
    local nt
    nt="$(getprop gsm.network.type 2>/dev/null | tr -d '\r\n')"
    [ -z "$nt" ] && nt="$(getprop ril.data.network.type 2>/dev/null | tr -d '\r\n')"
    [ -z "$nt" ] && nt="unknown"
    printf '%s' "$nt"
}

calibrate_apply_best_runtime_values() {
    local p v
    for p in $NET_PROPERTIES_KEYS $NET_OTHERS_PROPERTIES_KEYS; do
        eval "v=\${BEST_${p//./_}:-}"
        case "$v" in
            ''|*[!0-9]*) continue ;;
        esac
        resetprop "$p" "$v" >/dev/null 2>&1 || true
    done
}

calibrate_ml_feature_log_enabled() {
    # OFF by default to keep release behavior unchanged unless explicitly enabled.
    # Enable with env KITSUNPING_ML_FEATURE_LOG=1 or property persist.kitsunping.ml_feature_log_enable=1
    local raw
    raw="${KITSUNPING_ML_FEATURE_LOG:-$(getprop persist.kitsunping.ml_feature_log_enable 2>/dev/null | tr -d '\r\n')}"
    [ -z "$raw" ] && raw=0
    case "$raw" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
    esac
    return 1
}

calibrate_ml_append_feature() {
    local provider="$1" transport="$2" iface="$3" target="$4" source="$5"
    local baseline_metrics="$6" baseline_score="$7"
    local final_metrics="$8" final_score="$9"
    local success_flag="${10}" ping_improve_ms="${11}" score_delta="${12}"

    local b_ping b_jitter b_loss b_p90 b_p99
    local f_ping f_jitter f_loss f_p90 f_p99
    local ts hour wifi_rssi radio_type
    local bj bs fj fs
    local line payload

    b_ping="$(printf '%s' "$baseline_metrics" | awk '{print $1}')"
    b_jitter="$(printf '%s' "$baseline_metrics" | awk '{print $2}')"
    b_loss="$(printf '%s' "$baseline_metrics" | awk '{print $3}')"
    b_p90="$(printf '%s' "$baseline_metrics" | awk '{print $4}')"
    b_p99="$(printf '%s' "$baseline_metrics" | awk '{print $5}')"

    f_ping="$(printf '%s' "$final_metrics" | awk '{print $1}')"
    f_jitter="$(printf '%s' "$final_metrics" | awk '{print $2}')"
    f_loss="$(printf '%s' "$final_metrics" | awk '{print $3}')"
    f_p90="$(printf '%s' "$final_metrics" | awk '{print $4}')"
    f_p99="$(printf '%s' "$final_metrics" | awk '{print $5}')"

    ts="$(date +%s 2>/dev/null || echo 0)"
    hour="$(date +%H 2>/dev/null || echo 0)"
    wifi_rssi="$(calibrate_get_wifi_rssi_dbm)"
    radio_type="$(calibrate_get_radio_network_type)"

    [ -z "$b_p90" ] && b_p90="$b_ping"
    [ -z "$b_p99" ] && b_p99="$b_ping"
    [ -z "$f_p90" ] && f_p90="$f_ping"
    [ -z "$f_p99" ] && f_p99="$f_ping"

    bj="$(json_escape "$provider")"
    bs="$(json_escape "$source")"
    fj="$(json_escape "$iface")"
    fs="$(json_escape "$transport")"

    line="$(printf '%s' '{"ts":'"$ts"',"hour":'"$hour"',"provider":"'"$bj"'","source":"'"$bs"'","iface":"'"$fj"'","transport":"'"$fs"'","target":"'"$(json_escape "$target")"'","radio_network":"'"$(json_escape "$radio_type")"'","features":{"wifi_rssi_dbm":'"$(num_or_null "$wifi_rssi")"',"baseline":{"latency_ms":'"$(num_or_null "$b_ping")"',"jitter_ms":'"$(num_or_null "$b_jitter")"',"loss_pct":'"$(num_or_null "$b_loss")"',"p90_ms":'"$(num_or_null "$b_p90")"',"p99_ms":'"$(num_or_null "$b_p99")"',"score_sigmoid":'"$(num_or_null "$baseline_score")"'},"final":{"latency_ms":'"$(num_or_null "$f_ping")"',"jitter_ms":'"$(num_or_null "$f_jitter")"',"loss_pct":'"$(num_or_null "$f_loss")"',"p90_ms":'"$(num_or_null "$f_p90")"',"p99_ms":'"$(num_or_null "$f_p99")"',"score_sigmoid":'"$(num_or_null "$final_score")"'}},"result":{"success":'"$success_flag"',"ping_improvement_ms":'"$(num_or_null "$ping_improve_ms")"',"score_delta":'"$(num_or_null "$score_delta")"'},"best":{"hsupa":'"$(num_or_null "${BEST_ro_ril_hsupa_category:-}")"',"hsdpa":'"$(num_or_null "${BEST_ro_ril_hsdpa_category:-}")"',"lte":'"$(num_or_null "${BEST_ro_ril_lte_category:-}")"',"ltea":'"$(num_or_null "${BEST_ro_ril_ltea_category:-}")"',"nr5g":'"$(num_or_null "${BEST_ro_ril_nr5g_category:-}")"'}}')"

    payload="$(printf '%s\n' "$line")"
    if command -v atomic_write >/dev/null 2>&1; then
        if [ -f "$ml_features_file" ]; then
            { cat "$ml_features_file" 2>/dev/null; printf '%s\n' "$line"; } | atomic_write "$ml_features_file"
        else
            printf '%s\n' "$line" | atomic_write "$ml_features_file"
        fi
        printf '%s\n' "$line" | atomic_write "$ml_last_file"
    else
        printf '%s\n' "$line" >> "$ml_features_file" 2>/dev/null
        printf '%s\n' "$line" > "$ml_last_file" 2>/dev/null
    fi

    log_info "ML feature vector stored: $ml_last_file" >> "$trace_log"
}

# Persist coarse calibration progress to a separate file consumed by setup.sh.
# This keeps stdout clean so ONLY BEST_* lines are parsed for system.prop injection.
calibrate_progress_update() {
    local pct="$1" stage="$2" msg="$3"

    case "$pct" in
        ''|*[!0-9]*) pct=0 ;;
    esac
    [ "$pct" -lt 0 ] && pct=0
    [ "$pct" -gt 100 ] && pct=100

    if command -v atomic_write >/dev/null 2>&1; then
        {
            printf 'pct=%s\n' "$pct"
            printf 'stage=%s\n' "$stage"
            printf 'msg=%s\n' "$msg"
            printf 'ts=%s\n' "$(date +%s 2>/dev/null || echo 0)"
        } | atomic_write "$CALIBRATE_PROGRESS_FILE"
    else
        {
            printf 'pct=%s\n' "$pct"
            printf 'stage=%s\n' "$stage"
            printf 'msg=%s\n' "$msg"
            printf 'ts=%s\n' "$(date +%s 2>/dev/null || echo 0)"
        } > "$CALIBRATE_PROGRESS_FILE" 2>/dev/null
    fi
}

calibrate_cache_load_vars() {
    local env_file="$1"
    [ -f "$env_file" ] || return 1

    # Strictly accept only BEST_ro_ril_* lines (numbers only), for all non-empty lines.
    # Require the full expected set to avoid partial/injected env files.
    if ! awk '
        /^[[:space:]]*$/ { next }
        /^(BEST_ro_ril_(hsupa|hsdpa|lte|ltea|nr5g)_category)=[0-9]+$/ { ok++; next }
        { exit 1 }
        END { exit !(ok >= 5) }
    ' "$env_file" 2>/dev/null; then
        return 1
    fi

    # shellcheck disable=SC1090
    . "$env_file" 2>/dev/null || return 1
    return 0
}

calibrate_cache_try_use() {
    # Args: provider ping_target transport_key
    local provider="$1" ping_target="$2" transport_key="$3"
    local enable max_age now ts age max_rtt max_loss rc

    enable=$(getprop persist.kitsunping.calibrate_cache_enable 2>/dev/null)
    [ -z "$enable" ] && enable=1
    case "$enable" in
        0|false|FALSE|off|OFF|no|NO) return 1 ;;
    esac

    [ -f "$CALIBRATE_CACHE_META" ] || return 1
    [ -f "$CALIBRATE_CACHE_ENV" ] || return 1

    # Meta format: PROVIDER='<str>' TS=<epoch>
    local cached_provider cached_ts cached_transport
    cached_provider=$(awk -F= '/^PROVIDER=/{gsub(/^PROVIDER=|^\x27|\x27$/, "", $0); sub(/^PROVIDER=/, "", $0); print; exit}' "$CALIBRATE_CACHE_META" 2>/dev/null)
    cached_ts=$(awk -F= '/^TS=/{print $2; exit}' "$CALIBRATE_CACHE_META" 2>/dev/null)
    cached_transport=$(awk -F= '/^TRANSPORT=/{print $2; exit}' "$CALIBRATE_CACHE_META" 2>/dev/null | tr -d '\r\n' | tr '[:upper:]' '[:lower:]')
    [ -z "$cached_provider" ] && return 1
    [ -z "$cached_ts" ] && return 1

    if [ "$cached_provider" != "$provider" ]; then
        return 1
    fi

    local transport_strict
    transport_strict=$(getprop persist.kitsunping.calibrate_cache_transport_strict 2>/dev/null | tr -d '\r\n')
    [ -z "$transport_strict" ] && transport_strict=1
    case "$transport_strict" in
        0|false|FALSE|off|OFF|no|NO)
            :
            ;;
        *)
            [ -z "$transport_key" ] && transport_key="unknown"
            if [ -z "$cached_transport" ]; then
                return 1
            fi
            if [ "$cached_transport" != "$transport_key" ]; then
                return 1
            fi
            ;;
    esac

    max_age=$(getprop persist.kitsunping.calibrate_cache_max_age_sec 2>/dev/null | tr -d '\r\n')
    max_age="$(uint_or_default "$max_age" "604800")"

    now=$(date +%s)
    case "$now" in ''|*[!0-9]* ) now=0;; esac
    case "$cached_ts" in ''|*[!0-9]* ) cached_ts=0;; esac

    if [ "$now" -gt 0 ] && [ "$cached_ts" -gt 0 ]; then
        age=$((now - cached_ts))
        [ "$age" -lt 0 ] && age=0
        if [ "$age" -gt "$max_age" ]; then
            return 1
        fi
    fi

    # Quick validation: ensure we still have good ping metrics.
    max_rtt=$(getprop persist.kitsunping.calibrate_cache_rtt_ms 2>/dev/null | tr -d '\r\n')
    max_rtt="$(uint_or_default "$max_rtt" "120")"

    max_loss=$(getprop persist.kitsunping.calibrate_cache_loss_pct 2>/dev/null | tr -d '\r\n')
    max_loss="$(uint_or_default "$max_loss" "5")"

    # Prefer ping_target from JSON, but fallback to 8.8.8.8
    [ -z "$ping_target" ] && ping_target="8.8.8.8"

    test_ping_target "$ping_target"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        return 1
    fi

    # Require numeric metrics
    if ! printf '%s' "${PROBE_RTT_MS:-}" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        return 1
    fi
    if ! printf '%s' "${PROBE_LOSS_PCT:-}" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        return 1
    fi

    if awk -v rtt="$PROBE_RTT_MS" -v max="$max_rtt" 'BEGIN{exit !(rtt>0 && rtt<=max)}' && \
       awk -v loss="$PROBE_LOSS_PCT" -v max="$max_loss" 'BEGIN{exit !(loss>=0 && loss<=max)}'; then
        if ! calibrate_cache_load_vars "$CALIBRATE_CACHE_ENV"; then
            return 1
        fi

        log_info "Using calibration cache for provider=$provider (rtt=${PROBE_RTT_MS}ms loss=${PROBE_LOSS_PCT}%)" >> "$trace_log"
        calibrate_progress_update 100 "done" "cache hit: reused previous calibration"

        # Mark calibration as cooling and refresh last-run timestamp.
        echo "cooling" | atomic_write "$CALIBRATE_STATE_RUN"
        echo "$(date +%s)" | atomic_write "$CALIBRATE_LAST_RUN"

        echo "BEST_ro_ril_hsupa_category=$BEST_ro_ril_hsupa_category"
        echo "BEST_ro_ril_hsdpa_category=$BEST_ro_ril_hsdpa_category"
        echo "BEST_ro_ril_lte_category=$BEST_ro_ril_lte_category"
        echo "BEST_ro_ril_ltea_category=$BEST_ro_ril_ltea_category"
        echo "BEST_ro_ril_nr5g_category=$BEST_ro_ril_nr5g_category"
        return 0
    fi

    return 1
}

calibrate_cache_save() {
    # Args: provider transport_key
    local provider="$1" transport_key="$2" ts
    ts=$(date +%s)
    case "$ts" in ''|*[!0-9]* ) ts=0;; esac
    [ -z "$transport_key" ] && transport_key="unknown"

    # Save env with BEST_* values.
    {
        echo "BEST_ro_ril_hsupa_category=${BEST_ro_ril_hsupa_category:-}"
        echo "BEST_ro_ril_hsdpa_category=${BEST_ro_ril_hsdpa_category:-}"
        echo "BEST_ro_ril_lte_category=${BEST_ro_ril_lte_category:-}"
        echo "BEST_ro_ril_ltea_category=${BEST_ro_ril_ltea_category:-}"
        echo "BEST_ro_ril_nr5g_category=${BEST_ro_ril_nr5g_category:-}"
    } | atomic_write "$CALIBRATE_CACHE_ENV"

    {
        echo "PROVIDER='$provider'"
        echo "TRANSPORT=$transport_key"
        echo "TS=$ts"
    } | atomic_write "$CALIBRATE_CACHE_META"
}

# Getprops variables
calibrate_ping_count="$(getprop persist.kitsunping.calibrate_ping_count 2>/dev/null | tr -d '\r\n')"
[ -z "$calibrate_ping_count" ] && calibrate_ping_count="$(getprop persist.kitsunping.ping_timeout 2>/dev/null | tr -d '\r\n')"
ping_count="$(uint_or_default "$calibrate_ping_count" "5")"
[ "$ping_count" -lt 3 ] && ping_count=3
[ "$ping_count" -gt 10 ] && ping_count=10
CALIBRATE_PING_BIN=""
CALIBRATE_TARGET_IS_IPV6=0
PING6_BIN=""
CALIBRATE_GRANULAR_LATENCY_ENABLE="$(getprop persist.kitsunping.calibrate_granular_latency_enable 2>/dev/null | tr -d '\r\n')"
[ -z "$CALIBRATE_GRANULAR_LATENCY_ENABLE" ] && CALIBRATE_GRANULAR_LATENCY_ENABLE=0

# Rare if not found but just in case
verify_scripts() {
    local script="$1"
    if [ ! -f "$script" ]; then
        echo "[ERROR] Required script not found: $script" >> "$trace_log"
        exit 1
    fi

    # These helpers are sourced, not executed; on Windows-built zips the +x bit
    # is often lost. Ensure readability and continue.
    if [ ! -r "$script" ]; then
        chmod 0644 "$script" 2>/dev/null
    fi
    if [ ! -r "$script" ]; then
        echo "[ERROR] Required script not readable: $script" >> "$trace_log"
        exit 1
    fi

    echo "[INFO] Sourcing script: $script" >> "$trace_log"
    . "$script"
}

# Load helper scripts for advanced functions
verify_scripts "$NEWMODPATH/addon/functions/utils/env_detect.sh"
# Network helpers (test_ping_target/test_dns_ip)
verify_scripts "$NEWMODPATH/addon/functions/network_utils.sh"
# Generic utils
verify_scripts "$NEWMODPATH/addon/functions/utils/Kitsutils.sh"

# Ensure bundled binary directories are available in PATH before detection.
if command -v export_kitsunping_bin_path >/dev/null 2>&1; then
    export_kitsunping_bin_path
fi

# Description: Backup current network-related properties to a file.
echo "$(date +%s)" | atomic_write "$CALIBRATE_LAST_RUN"
echo "running" | atomic_write "$CALIBRATE_STATE_RUN"

# Create backup when calibration starts
create_backup

# Description: Ensure core binaries exist and ping works.
check_and_detect_commands() {
    log_info "====================== check_and_detect_commands =========================" >> "$trace_log"

    check_core_commands ip ndc resetprop awk || return 1
    detect_ip_binary || return 1
    ipbin="$IP_BIN"
    detect_jq_binary || true
    jqbin="$JQ_BIN"
    [ -n "$jqbin" ] || {
        log_error "jq binary not found" >> "$trace_log"
        return 1
    }

    # returns 0 = OK, 1 = ping binary not found, 2 = ping not functional
    check_and_prepare_ping "$pingbin"
    # get output code
    local rc
    rc=$?

    case "$rc" in
        0)
            log_debug "Ping binary functional: $PING_BIN" >> "$trace_log"
            return 0
            ;;
        1)
            log_error "Ping binary not found" >> "$trace_log"
            return 1
            ;;
        2)
            log_warning "Ping binary detected but not functional" >> "$trace_log"

            # Scan for common issues
            if is_install_context; then
                log_info "Install context detected." >> "$trace_log"
                log_info "Error code 2: Ping not functional in install context (possible no connectivity)" >> "$trace_log"
                return 2 # skip calibration in install context
            elif is_daemon_running; then
                # posible SELinux or permission issue, or network blocking while daemon is active
                log_error "Ping not functional while daemon is running" >> "$trace_log"
                log_error "Check SELinux, permissions, or network state" >> "$trace_log"

                if command -v getenforce >/dev/null 2>&1 && getenforce | grep -q Enforcing; then
                    log_warning "SELinux enforcing mode may block ping (CAP_NET_RAW)" >> "$trace_log"
                fi
                return 3
            else
                log_error "Ping not functional; check connectivity or permissions, or if exist" >> "$trace_log"
            fi
            return 1
            ;;
    esac
}

# v4.85
# Main function to calibrate network settings
# Description: Orchestrate full calibration flow for radio properties using ping-based scoring.
# Usage: calibrate_network_settings <delay_seconds>
calibrate_network_settings() {
    if [ -z "$1" ] || ! echo "$1" | grep -Eq '^[0-9]+$' || [ "$1" -lt 1 ]; then
        log_error "calibrate_network_settings <delay_seconds>" >&2
        return 1
    fi

    log_info "====================== calibrate_network_settings =========================" >> "$trace_log" 
    calibrate_progress_update 2 "startup" "checking required tools"
    # Ensure core commands and ping functionality
    check_and_detect_commands
    local calibrate_ping_status=$?

    # v4.89
    # Interpret decision result and return appropriate code to executor.sh for postpone handling, etc.
    case "$calibrate_ping_status" in
        0)
            log_info "Ping functional; proceeding with calibration" >> "$NETMETER_FILE"
            calibrate_progress_update 8 "startup" "network probe available"
            ;;
        1)
            log_error "Ping binary not found; aborting calibration" >> "$NETMETER_FILE"
            return 1
            ;;
        2)
            log_error "Ping not functional (install/context issue); aborting calibration" >> "$NETMETER_FILE"
            return 2
            ;;
        3)
            log_info "Ping not functional while daemon running; requesting postpone" >> "$NETMETER_FILE"
            log_error "Check SELinux, permissions, or network state" >> "$NETMETER_FILE"
            if command -v getenforce >/dev/null 2>&1 && getenforce | grep -q Enforcing; then
                log_warning "SELinux enforcing mode may block ping (CAP_NET_RAW)" >> "$NETMETER_FILE"
            fi
            return 3
            ;;
        *)
            log_error "Unknown status code: $calibrate_ping_status; aborting calibration" >> "$NETMETER_FILE"
            return 4
            ;;
    esac

  
    local delay=$1 # seconds
    local baseline_metrics="" baseline_score=""
    local final_metrics="" final_score=""
    local success_flag="0" ping_improvement_ms="0" score_delta="0"
    local ml_source="full"
    local config_json dns1 dns2 TEST_IP # unassigned local variables

    log_info "====================== calibrate_property =========================" >> "$trace_log"
    log_info "Execution trace, delay: $delay seconds" >> "$trace_log"
    calibrate_progress_update 12 "bootstrap" "loading provider config"
    config_json=$(configure_network) # get network configuration
    log_info "====================== calibrate_property =========================" >> "$trace_log"
    log_info "Network configuration obtained (config_json): $config_json" >> "$trace_log"

    echo "$config_json" | "$jqbin" -e 'type == "object" and has("provider") and has("dns") and has("ping")' >/dev/null || {
        log_info "[ERROR] config_json invalido o incompleto:" >> "$trace_log"
        log_info "$config_json" >> "$trace_log"
        return 1
    }

    provider_name=$(echo "$config_json" | "$jqbin" -r '.provider // "Unknown"')

    # Extract DNS and ping targets from JSON, with defaults
    dns1=$(echo "$config_json" | "$jqbin" -r '.dns[0] // "8.8.8.8"')
    dns2=$(echo "$config_json" | "$jqbin" -r '.dns[1] // "8.8.4.4"')
    PING_VAL=$(echo "$config_json" | "$jqbin" -r '.ping // "8.8.8.8"')

    local active_iface transport_key
    active_iface="$(get_active_default_iface)"
    [ -z "$active_iface" ] && active_iface="unknown"
    transport_key="$(get_transport_key_from_iface "$active_iface")"

    select_calibration_ping_mode "$active_iface"

    # Fast path: if we have a valid cache for this provider/transport and ping is still good, reuse it.
    # This avoids re-calibrating from scratch on every reboot when the operator remains the same.
    if calibrate_cache_try_use "$provider_name" "$PING_VAL" "$transport_key"; then
        ml_source="cache"
        if calibrate_ml_feature_log_enabled; then
            baseline_metrics="$(test_configuration "$delay")"
            baseline_score="$(extract_scores "$baseline_metrics")"
            calibrate_ml_append_feature "$provider_name" "$transport_key" "$active_iface" "$PING_VAL" "$ml_source" \
                "$baseline_metrics" "$baseline_score" "$baseline_metrics" "$baseline_score" "1" "0" "0"
        fi
        return 0
    fi
    calibrate_progress_update 20 "bootstrap" "cache miss: running full calibration"

    test_dns_ip "$dns1" "$dns2" "$PING_VAL"
    status=$?

    case "$status" in
        0) log_info "Provider FULL_OK" >> "$trace_log" ;;
        2) log_warning "Provider DNS_ONLY_OK (ping target no metrics; DNS usable for metrics)" >> "$trace_log" ;;
        3) log_warning "Provider PING_ONLY_OK (ping target usable; DNS not usable for metrics)" >> "$trace_log" ;;
        1)
            # No abort here: we can still try hostname fallback for metrics.
            log_warning "Provider UNUSABLE for metrics; trying fallback targets" >> "$trace_log"
            ;;
    esac

    # If JSON provides an IP for ping, probe both the IP and a geo-aware
    # hostname (so DNS resolution uses the provider DNS we just configured)
    # and choose the target with lower RTT.
    country_code=$(getprop gsm.sim.operator.iso-country 2>/dev/null | tr '[:upper:]' '[:lower:]')
    [ -z "$country_code" ] && country_code="$(network_hints_iso_country)"
    [ -z "$country_code" ] && country_code="global"

    if echo "$PING_VAL" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        ORIGINAL_IP="$PING_VAL"
        HOSTNAME="${country_code}.pool.ntp.org"
        log_info "Ping field is IP; probing ORIGINAL_IP=$ORIGINAL_IP and HOSTNAME=$HOSTNAME" >> "$trace_log"

        # Probe ORIGINAL IP and HOSTNAME.
        # IMPORTANT: Only targets that return RTT stats are usable for calibration.
        avg_ip="9999"
        avg_host="9999"

        test_ping_target "$ORIGINAL_IP"
        rc_ip=$?
        out_ip="$PROBE_LAST_OUTPUT"
        if [ $rc_ip -eq 0 ]; then
            avg_ip="$PROBE_RTT_MS"
        else
            log_debug "Discarding ORIGINAL_IP for calibration (no metrics): rc=$rc_ip" >> "$trace_log"
        fi

        test_ping_target "$HOSTNAME"
        rc_host=$?
        out_host="$PROBE_LAST_OUTPUT"
        if [ $rc_host -eq 0 ]; then
            avg_host="$PROBE_RTT_MS"
        else
            log_debug "Discarding HOSTNAME for calibration (no metrics): rc=$rc_host" >> "$trace_log"
        fi

        # Extract resolved IP for logging (if present in ping output)
        resolved_host_ip=$(echo "$out_host" | awk -F'[()]' 'NR==1{print $2}')
        [ -z "$resolved_host_ip" ] && resolved_host_ip="(unresolved)"

        # Decide: prefer numeric smaller RTT; handle non-numeric gracefully
        choice=$(awk -v a="$avg_ip" -v b="$avg_host" 'BEGIN {
            isnum = "^-?[0-9]+(\.[0-9]+)?$"
            if (a ~ isnum && b ~ isnum) {
                if (a <= 0 && b <= 0) { print "host"; exit }
                if (a <= 0) { print "host"; exit }
                if (b <= 0) { print "ip"; exit }
                if (a <= b) print "ip"; else print "host"
            } else if (a ~ isnum) print "ip"; else print "host"
        }')

        if [ "$choice" = "ip" ]; then
            TEST_IP="$ORIGINAL_IP"
            log_info "Chose ORIGINAL_IP ($avg_ip ms) over HOSTNAME ($avg_host ms)" >> "$trace_log"
        else
            TEST_IP="$HOSTNAME"
            log_info "Chose HOSTNAME $HOSTNAME -> $resolved_host_ip ($avg_host ms) over ORIGINAL_IP ($avg_ip ms)" >> "$trace_log"
        fi
    else
        TEST_IP="$PING_VAL"
    fi

    log_info "DNS1: $dns1, DNS2: $dns2, TEST_IP: $TEST_IP" >> "$trace_log"
    log_info "Checking connectivity..."  >> "$trace_log"

    PING_BIN="$CALIBRATE_PING_BIN"

    if ! $PING_BIN -c 3 -W 5 "$TEST_IP" >/dev/null; then
        log_error "[ERROR] No Internet connection" >> "$trace_log"
        return 1
    else
        log_info "Connectivity test passed" >> "$trace_log"
        calibrate_progress_update 28 "bootstrap" "connectivity verified"
    fi

    # Baseline sample only when ML feature logging is enabled.
    if calibrate_ml_feature_log_enabled; then
        baseline_metrics="$(test_configuration "$delay")"
        baseline_score="$(extract_scores "$baseline_metrics")"
    fi

    local index=1 total_calibrate count_primary count_secondary current_pct
    local run_secondary=0 has_sim=0
    export TEST_IP

    # Early SIM + transport detection for progress scaling and secondary decision.
    sim_iso=$(getprop gsm.sim.operator.iso-country 2>/dev/null | tr '[:upper:]' '[:lower:]')
    [ -z "$sim_iso" ] && sim_iso="$(network_hints_iso_country)"
    [ -n "$sim_iso" ] && has_sim=1

    # Decide if secondary (LTE/LTEA/5G) calibration will run.
    # WiFi+SIM: calibrate via WiFi as baseline; daemon recalibrates on mobile later.
    # WiFi-only (no SIM): apply safe defaults (no cellular network available).
    # Mobile: full calibration (optimal accuracy).
    case "$active_iface" in
        rmnet*|RMNET*) run_secondary=1 ;;
        wlan*|WLAN*)   [ "$has_sim" -eq 1 ] && run_secondary=1 ;;
        *)             [ "$has_sim" -eq 1 ] && run_secondary=1 ;;
    esac

    count_primary=$(printf '%s' "$NET_PROPERTIES_KEYS" | wc -w | tr -d ' ')
    [ -z "$count_primary" ] || [ "$count_primary" -lt 1 ] && count_primary=1
    count_secondary=0
    [ "$run_secondary" -eq 1 ] && count_secondary=$(printf '%s' "$NET_OTHERS_PROPERTIES_KEYS" | wc -w | tr -d ' ')
    total_calibrate=$((count_primary + count_secondary))
    [ "$total_calibrate" -lt 1 ] && total_calibrate=1

    log_info "Starting calibration for $TEST_IP (primary=$count_primary secondary=$count_secondary total=$total_calibrate run_secondary=$run_secondary has_sim=$has_sim)" >> "$trace_log"
    for prop in $NET_PROPERTIES_KEYS; do
        case "$prop" in
            "ro.ril.hsupa.category")
                vals="$NET_VAL_HSUPA"
                ;;
            "ro.ril.hsdpa.category")
                vals="$NET_VAL_HSDPA"
                ;;
            *)
                vals=$(get_values_for_prop "$index")
                ;;
        esac
        if [ -z "$vals" ]; then
            log_info "Empty value set for $prop" >> "$trace_log"
            continue
        fi
        current_pct=$(awk -v idx="$index" -v total="$total_calibrate" 'BEGIN{v=30 + int((idx-1)*60/total); if(v<30)v=30; if(v>90)v=90; print v}')
        calibrate_progress_update "$current_pct" "primary" "calibrating $prop"
        log_info "====================== calibrate_network_settings =========================" >> "$trace_log"
        log_info "Calibrating properties: prop: [$prop] val: [$vals] delay: [$delay] at [${CACHE_DIR_cln}/$prop.best]" >> "$trace_log"
        calibrate_property "$prop" "$vals" "$delay" "$CACHE_DIR_cln/$prop.best"
        index=$((index + 1))
    done

    for prop in $NET_PROPERTIES_KEYS; do
        # Read the best value from TMPDIR/*.best files
        local best_file="$CACHE_DIR_cln/$prop.best"
        local best_val="1"
        [ -f "$best_file" ] && best_val=$(cat "$best_file")
        log_info "Exporting properties: [BEST_${prop//./_}=$best_val]" >> "$trace_log"
        export "BEST_${prop//./_}=$best_val"
    done

    # Secondary calibration decision (pre-computed: run_secondary, has_sim).
    # Progress for secondary continues where primary ended.
    local secondary_pct_base secondary_pct_range
    secondary_pct_base=$(awk -v n="$count_primary" -v total="$total_calibrate" 'BEGIN{v=30 + int(n*60/total); if(v>90)v=90; print v}')
    secondary_pct_range=$((90 - secondary_pct_base))

    if [ "$run_secondary" -eq 1 ]; then
        local secondary_label="mobile extended"
        case "$active_iface" in
            wlan*|WLAN*)
                secondary_label="wifi+SIM baseline"
                log_info "WiFi+SIM mode: calibrating LTE/LTEA/5G via WiFi as baseline [detail:${active_iface}]" >> "$trace_log"
                ;;
            rmnet*|RMNET*)
                log_info "Mobile/data mode: extended calibration [detail:${active_iface}]" >> "$trace_log"
                ;;
            *)
                secondary_label="best-effort"
                log_info "Unknown iface+SIM: calibrating LTE/LTEA/5G best-effort [detail:${active_iface:-unknown}]" >> "$trace_log"
                ;;
        esac
        calibrate_progress_update "$secondary_pct_base" "secondary" "running $secondary_label calibration"
        calibrate_secondary_network_settings "$delay" "$CACHE_DIR_cln" "$secondary_pct_base" "$secondary_pct_range"

        # If calibrated via WiFi, mark for daemon recalibration when transport switches to mobile.
        case "$active_iface" in
            wlan*|WLAN*)
                printf '%s\n' "$(date +%s 2>/dev/null || echo 0)" | atomic_write "$CACHE_DIR_cln/calibrate.mobile_pending"
                log_info "Marked mobile recalibration pending (calibrated LTE/LTEA/5G via WiFi)" >> "$trace_log"
                ;;
        esac
    else
        calibrate_progress_update 90 "secondary" "wifi-only: applying safe mobile defaults"
        log_info "WiFi-only (no SIM): applying safe defaults for LTE/LTEA/5G [detail:${active_iface:-unknown}]" >> "$trace_log"
        BEST_ro_ril_lte_category="${BEST_ro_ril_lte_category:-12}"
        BEST_ro_ril_ltea_category="${BEST_ro_ril_ltea_category:-15}"
        BEST_ro_ril_nr5g_category="${BEST_ro_ril_nr5g_category:-2}"
        printf '%s\n' "$BEST_ro_ril_lte_category" | atomic_write "$CACHE_DIR_cln/ro.ril.lte.category.best"
        printf '%s\n' "$BEST_ro_ril_ltea_category" | atomic_write "$CACHE_DIR_cln/ro.ril.ltea.category.best"
        printf '%s\n' "$BEST_ro_ril_nr5g_category" | atomic_write "$CACHE_DIR_cln/ro.ril.nr5g.category.best"
    fi

    echo "cooling" | atomic_write "$CALIBRATE_STATE_RUN"
    log_info "====================== calibrate_network_settings =========================" >> "$trace_log"

    # Persist cache for future runs (provider + transport keyed).
    calibrate_progress_update 94 "finalize" "persisting best values"
    calibrate_cache_save "$provider_name" "$transport_key"

    if calibrate_ml_feature_log_enabled; then
        # Apply chosen best values then measure post-calibration quality for ML label.
        calibrate_apply_best_runtime_values
        final_metrics="$(test_configuration "$delay")"
        final_score="$(extract_scores "$final_metrics")"

        ping_improvement_ms="$(awk -v b="$(printf '%s' "$baseline_metrics" | awk '{print $1}')" -v f="$(printf '%s' "$final_metrics" | awk '{print $1}')" 'BEGIN{if(b==""||f==""||b!~/^[0-9.]+$/||f!~/^[0-9.]+$/){print 0; exit} printf "%.2f", (b-f)}')"
        score_delta="$(awk -v b="$baseline_score" -v f="$final_score" 'BEGIN{if(b==""||f==""||b!~/^[0-9.]+$/||f!~/^[0-9.]+$/){print 0; exit} printf "%.2f", (f-b)}')"
        success_flag="$(awk -v p="$ping_improvement_ms" -v s="$score_delta" 'BEGIN{if((p+0)>0 || (s+0)>=0.5) print 1; else print 0}')"

        calibrate_ml_append_feature "$provider_name" "$transport_key" "$active_iface" "$TEST_IP" "$ml_source" \
            "$baseline_metrics" "$baseline_score" "$final_metrics" "$final_score" "$success_flag" "$ping_improvement_ms" "$score_delta"
    fi

    calibrate_progress_update 100 "done" "calibration finished"

    echo "BEST_ro_ril_hsupa_category=$BEST_ro_ril_hsupa_category"
    echo "BEST_ro_ril_hsdpa_category=$BEST_ro_ril_hsdpa_category"
    echo "BEST_ro_ril_lte_category=$BEST_ro_ril_lte_category"
    echo "BEST_ro_ril_ltea_category=$BEST_ro_ril_ltea_category"
    echo "BEST_ro_ril_nr5g_category=$BEST_ro_ril_nr5g_category"
}

# Description: Slice shared NET_PROPERTIES_VALUES based on PROP_OFFSETS for a given index.
# Usage: get_values_for_prop <index>
get_values_for_prop() {
    local index="$1"
    log_info "====================== get_values_for_prop =========================" >> "$trace_log"
    log_info "index: $index" >> "$trace_log"

    # Store and get the initial offset for the current property (e.g., 0)
    local start=$(echo "$PROP_OFFSETS" | cut -d' ' -f$index)
    log_info "PROP_OFFSETS: $PROP_OFFSETS" >> "$trace_log"
    log_info "start: $start" >> "$trace_log"

    # Store and get the next offset (if it exists) to determine the range of values (e.g., 6)
    local end=$(echo "$PROP_OFFSETS" | cut -d' ' -f$((index + 1)) 2>/dev/null)
    log_info "PROP_OFFSETS: $PROP_OFFSETS" >> "$trace_log"
    log_info "end: $end" >> "$trace_log"

    # Calculate the total number of available values in NET_PROPERTIES_VALUES
    local total=$(echo "$NET_PROPERTIES_VALUES" | wc -w)
    log_info "PROP_OFFSETS: $NET_PROPERTIES_VALUES" >> "$trace_log"
    log_info "end: $total" >> "$trace_log"

    # Extract the values corresponding to the current property
    if [ -z "$end" ]; then
        # If there is no next offset, take all values from the current offset to the end
        echo "$NET_PROPERTIES_VALUES" | cut -d' ' -f$((start + 1))-"$total"
    else
        # If there is a next offset, take the values between the current offset and the next
        # └── that is, take those from: 0 to 6
        echo "$NET_PROPERTIES_VALUES" | cut -d' ' -f$((start + 1))-"$end"
    fi
}

#v4.85
# Description: Iterate candidate values for a property, score them via ping, persist the best.
# Usage: calibrate_property <property> "<candidates>" <delay_seconds> <best_file_path>
calibrate_property() {
    local property="$1"
    local candidates="$2"
    local delay="$3"
    local best_file="$4"
    
    local best_score=-1
    local best_val=$(echo "$candidates" | awk '{print $1}')
    local best_score_seen=""
    local epsilon="0.20"
    local valid_count=0
    local equal_best_count=0
    local attempts=3
    local attempts_raw=""
    local active_iface=""
    local current_prop_val=""
    
    log_info "====================== calibrate_property =========================" >> "$trace_log"
    log_info "Properties: property: $property | candidates: $candidates | delay: $delay | best_file: $best_file" >> "$trace_log"
    log_info "best_val: $best_val" >> "$trace_log"

    current_prop_val="$(getprop "$property" 2>/dev/null | tr -d '\r\n')"
    log_info "current_prop_val: ${current_prop_val:-unknown}" >> "$trace_log"

    # Verify write permissions first
    local write_test="${best_file}.test"
    log_info "write_test: $write_test" >> "$trace_log"
    if ! touch "$write_test" 2>/dev/null; then
        log_error "Cannot write to: $(dirname "$best_file")"
        return 1
    fi
    rm -f "$write_test"

    # Adaptive attempts: mobile path keeps 3, Wi-Fi/default uses 2 for faster install.
    attempts_raw="${CALIBRATE_ATTEMPTS:-$(getprop persist.kitsunping.calibrate_attempts 2>/dev/null | tr -d '\r\n')}"
    attempts="$(uint_or_default "$attempts_raw" "")"
    if [ -z "$attempts" ]; then
        active_iface="$(get_active_default_iface)"
        case "$active_iface" in
            rmnet*) attempts=3 ;;
            *) attempts=2 ;;
        esac
    fi
    [ "$attempts" -lt 1 ] && attempts=1
    [ "$attempts" -gt 4 ] && attempts=4
    log_info "calibrate attempts for $property: $attempts (iface=${active_iface:-unknown})" >> "$trace_log"
    
    for candidate in $candidates; do
        local total_score=0
        
        resetprop "$property" "$candidate" >/dev/null 2>&1
        log_info "using resetprop: property: $property | candidate: $candidate" >> "$trace_log"

        sleep 1
        # Warm-up once per candidate to avoid skewed first sample.
        $PING_BIN -c 3 -W 1 "$TEST_IP" >/dev/null 2>&1
        
        for i in $(seq 1 $attempts); do
            local ping_result=$(test_configuration "$delay")
            log_info "using ping_result: $ping_result" >> "$trace_log"
            local score=$(extract_scores "$ping_result")
            log_info "using score: $score" >> "$trace_log"
            
            total_score=$(awk "BEGIN {print $total_score + $score}")
            log_info "using total_score: $total_score" >> "$trace_log"
            sleep 0.2
        done
        
        local avg_score=$(awk "BEGIN {print $total_score / $attempts}")
        log_info "using avg_score: $avg_score" >> "$trace_log"

        if ! echo "$avg_score" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
            log_warning "Skipping non-numeric avg_score for $property candidate=$candidate: $avg_score" >> "$trace_log"
            continue
        fi

        valid_count=$((valid_count + 1))

        if awk "BEGIN {exit !($avg_score > $best_score + $epsilon)}"; then
            best_score="$avg_score"
            best_val="$candidate"
            best_score_seen="$avg_score"
            equal_best_count=0
            log_info "new best: property=$property candidate=$candidate score=$avg_score" >> "$trace_log"
        elif [ -n "$best_score_seen" ] && awk "BEGIN {d=($avg_score-$best_score_seen); if(d<0)d=-d; exit !(d <= $epsilon)}"; then
            equal_best_count=$((equal_best_count + 1))
            log_info "tie within epsilon: property=$property candidate=$candidate score=$avg_score best=$best_score_seen" >> "$trace_log"
        fi
    done

    if [ "$valid_count" -eq 0 ]; then
        log_warning "No valid scores for $property; keeping current/default value=$best_val" >> "$trace_log"
    fi

    if [ "$equal_best_count" -gt 0 ] && [ -n "$current_prop_val" ]; then
        for c in $candidates; do
            if [ "$c" = "$current_prop_val" ]; then
                log_info "Scores tied for $property; preserving current value=$current_prop_val" >> "$trace_log"
                best_val="$current_prop_val"
                break
            fi
        done
    fi
    
    # Create directory with error checking
    if ! mkdir -p "$(dirname "$best_file")"; then
        log_error "Could not create directory: $(dirname "$best_file")"
        return 1
    fi
    
    # Write file with verification
    if ! printf '%s\n' "$best_val" | atomic_write "$best_file"; then
        log_error "Error writing to: $best_file"
        return 1
    fi

    log_info "Final best for $property: $best_val (score=${best_score:-n/a}, valid_count=$valid_count)" >> "$trace_log"
    
    return 0
}

# Description: Compute quality score from ping metrics (avg RTT, jitter/variance, loss).
# Usage: extract_scores "<avg> <jitter> <loss>"
calculate_percentile_from_series() {
    # Args: "newline-separated numeric series" percentile_int
    local series="$1"
    local pct="$2"

    printf '%s\n' "$series" | awk -v pct="$pct" '
    $1 ~ /^[0-9]+(\.[0-9]+)?$/ { vals[++n]=$1 }
    END {
        if (n == 0) {
            print ""
            exit
        }
        idx = int(((pct * n) + 99) / 100)
        if (idx < 1) idx = 1
        if (idx > n) idx = n
        print vals[idx]
    }'
}

extract_scores() {
    local current_ping=$(echo "$1" | awk '{print $1}')
    local current_jitter=$(echo "$1" | awk '{print $2}')
    local current_loss=$(echo "$1" | awk '{print $3}')
    local current_p90=$(echo "$1" | awk '{print $4}')
    local current_p99=$(echo "$1" | awk '{print $5}')

    # Locale guard: allow decimals written with comma (e.g. 37,182)
    current_ping=$(echo "$current_ping" | tr ',' '.')
    current_jitter=$(echo "$current_jitter" | tr ',' '.')
    current_loss=$(echo "$current_loss" | tr ',' '.')
    current_p90=$(echo "$current_p90" | tr ',' '.')
    current_p99=$(echo "$current_p99" | tr ',' '.')
    log_info "====================== extract_scores =========================" >> "$trace_log"
    log_info "props before verify: current_ping: $current_ping | current_jitter: $current_jitter | current_loss: $current_loss | current_p90: $current_p90 | current_p99: $current_p99" >> "$trace_log"
    
    
    # Validation and defaulting
    [ -z "$current_ping" ] && current_ping="-1"
    [ -z "$current_jitter" ] && current_jitter="-1"
    [ -z "$current_loss" ] && current_loss="100"
    [ -z "$current_p90" ] && current_p90="$current_ping"
    [ -z "$current_p99" ] && current_p99="$current_ping"
    log_info "props after verify: current_ping: $current_ping | current_jitter: $current_jitter | current_loss: $current_loss | current_p90: $current_p90 | current_p99: $current_p99" >> "$trace_log"

    # Score calculation with numeric validation
    if ! echo "$current_ping" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || \
       ! echo "$current_jitter" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || \
       ! echo "$current_loss" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        echo "0"
        return 1
    fi

    if is_granular_latency_enabled; then
        if ! echo "$current_p90" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || \
           ! echo "$current_p99" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
            echo "0"
            return 1
        fi
    fi

    # Safe calculation with awk
    if is_granular_latency_enabled; then
        log_info "extract_scores mode: granular (avg+jitter+loss+p90+p99)" >> "$trace_log"
        echo "$current_ping $current_jitter $current_loss $current_p90 $current_p99" | awk '
        {
            p = $1; j = $2; l = $3; p90 = $4; p99 = $5

            if (p <= 0 || p >= 9999 || l >= 100 || p90 <= 0 || p99 <= 0) {
                print "0"
                exit
            }

            if (p99 < p90) {
                t = p99
                p99 = p90
                p90 = t
            }

            tail = p99 - p90
            base = 100 - (p99 / 2.5)
            score = base - (j * 0.4) - (l * 0.8) - (tail * 0.3)

            if (score < 1) score = 1
            if (score > 100) score = 100

            printf "%.2f", score
        }'
    else
        log_info "extract_scores mode: legacy (avg+jitter+loss)" >> "$trace_log"
        echo "$current_ping $current_jitter $current_loss" | awk '
        {
            p = $1; j = $2; l = $3

            if (p <= 0 || p >= 9999 || l >= 100) {
                print "0"
                exit
            }

            # Simplified formula
            base = 100 - (p / 2)
            score = base - (j * 0.5) - (l * 0.8)

            if (score < 1) score = 1
            if (score > 100) score = 100

            printf "%.2f", score
        }'
    fi
}

# Description: Resolve provider/dns/ping from SIM MCC/MNC JSON or fallback, apply DNS.
# Usage: configure_network
configure_network() {
    local country_code mcc_raw mnc_raw mcc mnc json_file cache_file cache_ok
    local numeric_hint hint_mcc hint_mnc
    local raw provider dns_list ping dns_json

    country_code=$(getprop gsm.sim.operator.iso-country 2>/dev/null | tr '[:upper:]' '[:lower:]')
    [ -z "$country_code" ] && country_code="$(network_hints_iso_country)"
    [ -z "$country_code" ] && country_code="unknow"

    mcc_raw=$(getprop debug.tracing.mcc 2>/dev/null | tr -d '[]')
    mnc_raw=$(getprop debug.tracing.mnc 2>/dev/null | tr -d '[]')
    numeric_hint="$(network_hints_numeric)"
    hint_mcc=""
    hint_mnc=""
    case "$numeric_hint" in
        [0-9][0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9][0-9][0-9])
            hint_mcc=$(printf '%s' "$numeric_hint" | cut -c1-3)
            hint_mnc=$(printf '%s' "$numeric_hint" | cut -c4-)
            ;;
    esac

    if echo "$mcc_raw" | grep -qE '^[0-9]+$'; then
        mcc="$mcc_raw"
    elif echo "$hint_mcc" | grep -qE '^[0-9]{3}$'; then
        mcc="$hint_mcc"
    else
        mcc="000"
    fi

    if echo "$mnc_raw" | grep -qE '^[0-9]+$'; then
        mnc=$(printf "%03d" "$mnc_raw")
    elif echo "$hint_mnc" | grep -qE '^[0-9]{2,3}$'; then
        mnc=$(printf "%03d" "$hint_mnc")
    else
        mnc="000"
    fi

    json_file="$data_dir/countries/${country_code}.json"

    if [ "$mcc" = "000" ] && [ "$mnc" = "000" ]; then
        log_warning "MCC/MNC not detected, using default configuration" | tee -a /sdcard/errors.log
        json_file="$fallback_json"
    fi

    cache_file="$cache_dir/${mcc}_${mnc}.conf"
    log_info "====================== configure_network =========================" >> "$trace_log"
    log_info "country_code: $country_code | mcc: $mcc | mnc: $mnc | json_file: $json_file | cache_file: $cache_file" >> "$trace_log"
    
    if [ -z "$mcc" ] || [ -z "$mnc" ]; then
        log_warning "MCC/MNC not detected, using default configuration" | tee -a /sdcard/errors.log
        mcc="000"
        mnc="000"
        json_file="$fallback_json"
        cache_file="$cache_dir/${mcc}_${mnc}.conf"
    fi

    # Hardcore validations
    [ -f "$jqbin" ] || { log_error "jq not found"; return 1; }
    [ -x "$jqbin" ] || { log_error "jq is not executable"; return 1; }
    [ -f "$json_file" ] || json_file="$fallback_json"
    [ -f "$json_file" ] || { log_error "JSON not found"; return 1; }
    "$jqbin" empty "$json_file" || { log_error "Invalid JSON"; return 1; }
    head -c3 "$json_file" | grep -q $'\xEF\xBB\xBF' && tail -c +4 "$json_file" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file" # prevenir BOM

    if [ -f "$cache_file" ] && \
       grep -q "^PROVIDER=" "$cache_file" && \
       grep -q "^DNS_LIST=" "$cache_file" && \
       grep -q "^PING=" "$cache_file"; then
        cache_ok=1
    else
        cache_ok=0
    fi

    if [ "$cache_ok" -eq 1 ]; then
        . "$cache_file"
    else
        raw=$("$jqbin" -n --slurpfile data "$json_file" \
            --arg mcc "$mcc" --arg mnc "$mnc" '
                ($data[0] // {}) as $root |
                (try ($root.entries // []) catch []) as $ents |
                ($ents[] | select((.mcc // 0) == ($mcc | tonumber) and (.mnc // "") == $mnc)) //
                (try $root.default catch {})
        ')

        log_info "Network configuration obtained (raw): $raw" >> "$trace_log"

        if [ -z "$raw" ] || [ "$raw" = "null" ]; then
            raw=$(cat "$fallback_json")
            log_info "Using fallback_json because raw is empty" >> "$trace_log"
        fi

        if ! echo "$raw" | "$jqbin" -e 'type == "object" and has("provider")' >/dev/null; then
            echo "[ERROR] Invalid JSON or missing 'provider' key" >> "/sdcard/errors.log"
            return 1
        fi

        provider=$(echo "$raw" | "$jqbin" -r '.provider // "Unknown"')
        dns_list=$(echo "$raw" | "$jqbin" -r '.dns[]?' | paste -sd " ")
        ping=$(echo "$raw" | "$jqbin" -r '.ping // "8.8.8.8"')

        log_info "Network configuration obtained (ping): $ping" >> "$trace_log"
        log_info "Network configuration obtained (dns_list): $dns_list" >> "$trace_log"
        log_info "Network configuration obtained (provider): $provider" >> "$trace_log"

        [ -z "$dns_list" ] && dns_list="8.8.8.8 1.1.1.1"
        [ -z "$ping" ] && ping="8.8.8.8"

        cat <<-EOF | atomic_write "$cache_file"
PROVIDER='$provider'
DNS_LIST='$dns_list'
PING='$ping'
EOF
        . "$cache_file"
    fi

            [ -z "$DNS_LIST" ] && DNS_LIST="8.8.8.8 1.1.1.1"
            [ -z "$PING" ] && PING="8.8.8.8"
    # TODO: [PENDING] Add ndc binary compatibility strategy for multiple architectures TODO:
    if command -v ndc >/dev/null 2>&1; then
        for iface in $($ipbin -o link show | awk -F': ' '{print $2}' | grep -E 'rmnet|wlan|eth|ccmni|usb'); do
            log_info "Configuring DNS on interface: $iface" >> "$trace_log"
            ndc resolver setifacedns "$iface" "" $DNS_LIST >/dev/null 2>&1
        done
    else
        local dns1_fallback dns2_fallback setprop_fallback
        setprop_fallback=$(getprop persist.kitsunping.calibrate_dns_setprop_fallback 2>/dev/null | tr -d '\r\n')
        [ -z "$setprop_fallback" ] && setprop_fallback=0

        case "$setprop_fallback" in
            1|true|TRUE|on|ON|yes|YES)
                dns1_fallback=$(printf '%s\n' $DNS_LIST | awk 'NR==1{print; exit}')
                dns2_fallback=$(printf '%s\n' $DNS_LIST | awk 'NR==2{print; exit}')
                [ -z "$dns1_fallback" ] && dns1_fallback="8.8.8.8"
                [ -z "$dns2_fallback" ] && dns2_fallback="1.1.1.1"

                log_warning "ndc not available; applying global DNS fallback via setprop" >> "$trace_log"
                setprop net.dns1 "$dns1_fallback" >/dev/null 2>&1
                setprop net.dns2 "$dns2_fallback" >/dev/null 2>&1
                ;;
            *)
                log_warning "ndc not available; skipping setprop net.dns* fallback (persist.kitsunping.calibrate_dns_setprop_fallback=0)" >> "$trace_log"
                ;;
        esac
    fi

    dns_json=$(printf '%s\n' $DNS_LIST | "$jqbin" -R . | "$jqbin" -s .)
    log_info "dns_json: $dns_json" >> "$trace_log"

    "$jqbin" -n \
      --arg provider "$PROVIDER" \
      --argjson dns "$dns_json" \
      --arg ping "$PING" \
      '{provider: $provider, dns: $dns, ping: $ping}'
}

# Description: Calibrate LTE/LTEA/5G properties when mobile path is active.
# Usage: calibrate_secondary_network_settings <delay_seconds> <cache_dir>
calibrate_secondary_network_settings() {
    local delay="$1"
    local cache_dir="$2"
    local pct_base="${3:-80}"
    local pct_range="${4:-10}"
    local prop vals best_file best_val exp_name
    local sec_index=0 sec_total sec_pct

    log_info "====================== calibrate_secondary_network_settings =========================" >> "$trace_log"

    sec_total=$(printf '%s' "$NET_OTHERS_PROPERTIES_KEYS" | wc -w | tr -d ' ')
    [ -z "$sec_total" ] || [ "$sec_total" -lt 1 ] && sec_total=1

    for prop in $NET_OTHERS_PROPERTIES_KEYS; do
        case "$prop" in
            "ro.ril.lte.category")
                vals="$NET_VAL_LTE"
                ;;
            "ro.ril.ltea.category")
                vals="$NET_VAL_LTEA"
                ;;
            "ro.ril.nr5g.category")
                vals="$NET_VAL_5G"
                ;;
            *)
                vals="9" # Default fallback value
                ;;
        esac
        sec_pct=$(awk -v base="$pct_base" -v idx="$sec_index" -v total="$sec_total" -v range="$pct_range" \
            'BEGIN{v=base + int(idx*range/total); if(v<30)v=30; if(v>90)v=90; print v}')
        calibrate_progress_update "$sec_pct" "secondary" "calibrating $prop"
        log_info "Calibrating $prop with values: $vals" >> "$trace_log"
        calibrate_property "$prop" "$vals" "$delay" "$cache_dir/$prop.best"
        sec_index=$((sec_index + 1))
    done

    # Export results
    for prop in $NET_OTHERS_PROPERTIES_KEYS; do
        best_file="$cache_dir/$prop.best"
        if [ -f "$best_file" ]; then
            best_val=$(cat "$best_file")
            log_info "Best value for $prop: $best_val" >> "$trace_log"
            exp_name=$(echo "$prop" | tr '.' '_')
            export "BEST_${exp_name}=$best_val"
        else
            log_info "Best value for $prop: (not found)" >> "$trace_log"
        fi
    done
}

# Description: Measure connectivity quality via ping for the currently applied candidate.
# Usage: test_configuration <delay_seconds>
test_configuration() {
    log_info "====================== test_configuration =========================" >> "$trace_log"
    local delay="$1"
    log_info "delay: $delay" >> "$trace_log"


    [ -z "${TEST_IP:-}" ] && { echo "9999 9999 100"; return 3; }

    # Execute ping with consistent format
    # Binary -c 10 (10 packets), -i 0.5 (interval 500ms), -W 1 

    ping_count="$(uint_or_default "$ping_count" "5")"
    local output 
    output="$($PING_BIN -c "$ping_count" -i 0.5 -W 1 "$TEST_IP" 2>&1)"
    [ $? -ne 0 ] && { echo "9999 9999 100"; return 2; }

    log_debug "Ping output: $output" >> "$trace_log"

    parse_ping "$output"
}

# Description: Parse ping output to extract avg RTT, jitter (mdev), variance (max-min), and loss.
# Usage: parse_ping "$(ping ... output)"
parse_ping() {
    local ping_output="$1"
    log_info "====================== parse_ping =========================" >> "$trace_log"
    log_info "Raw ping output: $ping_output" >> "$trace_log"

    # Keep outputs consistent with extract_scores(): "<avg_ms> <jitter_ms> <loss_percent>"
    # Defaults represent a failed/invalid measurement.
    if [ -z "$ping_output" ]; then
        echo "9999 9999 100"
        return 1
    fi

    local avg_ping="9999"
    local jitter="9999"
    local packet_loss="100"
    local p90_ping="9999"
    local p99_ping="9999"

    # Extract packet loss percentage (works for: "0% packet loss" / Spanish variants)
    packet_loss=$(echo "$ping_output" | awk '
        /packet loss|perdida|p[eé]rdida/ {
            for (i=1; i<=NF; i++) {
                if ($i ~ /^[0-9]+(\.[0-9]+)?%$/) {
                    gsub(/%/, "", $i)
                    print $i
                    found=1
                    exit
                }
            }
        }
        END {
            if (!found) print "100"
        }
    ')
    packet_loss=$(echo "$packet_loss" | awk '{gsub(/[^0-9.]/, ""); print}')
    [ -z "$packet_loss" ] && packet_loss="100"
    log_info "packet_loss: $packet_loss" >> "$trace_log"

    # Extract RTT stats line (supports multiple ping variants/locales)
    local rtt_line stats
    rtt_line=$(echo "$ping_output" | awk '
        /rtt min\/avg\/max\/mdev/ {print; exit}
        /round-trip min\/avg\/max/ {print; exit}
        /min\/avg\/max\/stddev/ {print; exit}
    ')
    log_info "rtt_line: $rtt_line" >> "$trace_log"

    if [ -n "$rtt_line" ]; then
        stats=$(echo "$rtt_line" | awk -F'=' 'NF>=2 {gsub(/^[ \t]+/, "", $2); print $2}')
        # stats should look like: min/avg/max/mdev ms or min/avg/max/stddev ms
        avg_ping=$(echo "$stats" | awk -F'/' '{print $2}')
        jitter=$(echo "$stats" | awk -F'/' '{print $4}')

        # Locale guard: allow decimals written with comma (37,182)
        avg_ping=$(echo "$avg_ping" | tr ',' '.' | awk '{gsub(/[^0-9.]/, ""); print}')
        jitter=$(echo "$jitter" | tr ',' '.' | awk '{gsub(/[^0-9.]/, ""); print}')

        # Some ping variants output only min/avg/max (no 4th field); treat jitter as 0
        [ -z "$jitter" ] && jitter="0"
        [ -z "$avg_ping" ] && avg_ping="9999"
    fi

    if is_granular_latency_enabled; then
        local samples sample_count sorted_samples
        samples=$(echo "$ping_output" | awk '
            {
                for (i = 1; i <= NF; i++) {
                    if (index($i, "time=") == 1) {
                        v = substr($i, 6)
                        gsub(/,/, ".", v)
                        gsub(/[^0-9.]/, "", v)
                        if (v != "") print v
                    }
                }
            }
        ')

        sorted_samples=$(printf '%s\n' "$samples" | awk '$1 ~ /^[0-9]+(\.[0-9]+)?$/ {print}' | sort -n)
        sample_count=$(printf '%s\n' "$sorted_samples" | awk 'NF{c++} END{print c+0}')

        if [ "$sample_count" -gt 0 ]; then
            p90_ping=$(calculate_percentile_from_series "$sorted_samples" 90)
            p99_ping=$(calculate_percentile_from_series "$sorted_samples" 99)
        else
            p90_ping="$avg_ping"
            p99_ping="$avg_ping"
        fi

        [ -z "$p90_ping" ] && p90_ping="$avg_ping"
        [ -z "$p99_ping" ] && p99_ping="$avg_ping"
        log_info "avg_ping: $avg_ping | jitter: $jitter | packet_loss: $packet_loss | p90: $p90_ping | p99: $p99_ping" >> "$trace_log"
        echo "$avg_ping $jitter $packet_loss $p90_ping $p99_ping"
        return 0
    fi

    log_info "avg_ping: $avg_ping | jitter: $jitter | packet_loss: $packet_loss" >> "$trace_log"

    echo "$avg_ping $jitter $packet_loss"
}