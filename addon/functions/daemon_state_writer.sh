daemon_read_lownet_offset() {
    local candidate raw
    for candidate in \
        "/data/local/tmp/lownet.test" \
        "${MODDIR:-/data/adb/modules/Kitsunping}/cache/lownet.test" \
        "/debug_ramdisk/.magisk/modules/Kitsunping/cache/lownet.test" \
        "/data/adb/modules/Kitsunping/cache/lownet.test"
    do
        [ -f "$candidate" ] || continue
        raw="$(tr -d '\r\n[:space:]' < "$candidate" 2>/dev/null)"
        case "$raw" in
            ''|*[!0-9]*) continue ;;
        esac
        printf '%s' "$raw"
        return 0
    done
    printf '%s' 0
}

daemon_subtract_score() {
    local value="$1" offset="$2"
    awk -v v="$value" -v o="$offset" 'BEGIN {
        if (v == "" || v == "-") { print v; exit }
        n = v - o
        if (n < 0) n = 0
        if (n > 100) n = 100
        printf "%.0f", n
    }'
}

daemon_subtract_score_float() {
    local value="$1" offset="$2"
    awk -v v="$value" -v o="$offset" 'BEGIN {
        if (v == "" || v == "-") { print v; exit }
        n = v - o
        if (n < 0) n = 0
        if (n > 100) n = 100
        printf "%.2f", n
    }'
}

daemon_subtract_numeric() {
    local value="$1" offset="$2"
    awk -v v="$value" -v o="$offset" 'BEGIN {
        if (v == "" || v == "-") { print v; exit }
        n = v - o
        printf "%.0f", n
    }'
}

daemon_write_state_file() {
    local lownet_offset
    local out_wifi_score out_mobile_score out_composite out_composite_ema
    local out_wifi_rssi out_rsrp out_sinr out_wifi_latency_score out_rsrp_score out_sinr_score
    local target_state target_state_reason target_state_ts

    lownet_offset="$(daemon_read_lownet_offset)"

    out_wifi_score="$wifi_score"
    out_mobile_score="$mobile_score"
    out_composite="$composite"
    out_composite_ema="$composite_ema_val"
    out_wifi_rssi="${wifi_rssi_dbm:--}"
    out_rsrp="${rsrp:--}"
    out_sinr="${sinr:--}"
    out_wifi_latency_score="${wifi_latency_score:--}"
    out_rsrp_score="${rsrp_score:-0}"
    out_sinr_score="${sinr_score:-0}"

    target_state="$(cat "$MODDIR/cache/target.state" 2>/dev/null || echo "IDLE")"
    target_state_reason="$(cat "$MODDIR/cache/target.state.reason" 2>/dev/null || echo "")"
    target_state_ts="$(cat "$MODDIR/cache/target.state.ts" 2>/dev/null || echo "0")"

    case "$lownet_offset" in
        ''|0) ;;
        *[!0-9]*) lownet_offset=0 ;;
        *)
            out_wifi_score="$(daemon_subtract_score "$out_wifi_score" "$lownet_offset")"
            out_mobile_score="$(daemon_subtract_score "$out_mobile_score" "$lownet_offset")"
            out_composite="$(daemon_subtract_score "$out_composite" "$lownet_offset")"
            out_composite_ema="$(daemon_subtract_score_float "$out_composite_ema" "$lownet_offset")"
            out_wifi_latency_score="$(daemon_subtract_score "$out_wifi_latency_score" "$lownet_offset")"
            out_rsrp_score="$(daemon_subtract_score "$out_rsrp_score" "$lownet_offset")"
            out_sinr_score="$(daemon_subtract_score "$out_sinr_score" "$lownet_offset")"
            out_wifi_rssi="$(daemon_subtract_numeric "$out_wifi_rssi" "$lownet_offset")"
            out_rsrp="$(daemon_subtract_numeric "$out_rsrp" "$lownet_offset")"
            out_sinr="$(daemon_subtract_numeric "$out_sinr" "$lownet_offset")"
            ;;
    esac

    {
        printf 'iface=%s\n' "$current_iface"
        printf 'transport=%s\n' "$transport"
        printf 'wifi.iface=%s\n' "$WIFI_IFACE"
        printf 'wifi.state=%s\n' "$wifi_state"
        printf 'wifi.link=%s\n' "$wifi_link"
        printf 'wifi.ip=%s\n' "$wifi_ip"
        printf 'wifi.egress=%s\n' "$wifi_egress"
        printf 'wifi.score=%s\n' "$out_wifi_score"
        printf 'wifi.reason=%s\n' "$wifi_path_reason"
        printf 'wifi.quality=%s\n' "$wifi_quality_reason"
        printf 'wifi.rssi_dbm=%s\n' "$out_wifi_rssi"
        printf 'wifi.latency_ms=%s\n' "${wifi_latency_ms:--}"
        printf 'wifi.latency_ema_ms=%s\n' "${wifi_latency_ema_ms:--}"
        printf 'wifi.latency_p95_ms=%s\n' "${wifi_latency_p95_ms:-}"
        printf 'wifi.latency_p99_ms=%s\n' "${wifi_latency_p99_ms:-}"
        printf 'wifi.latency_score=%s\n' "$out_wifi_latency_score"
        printf 'wifi.jitter_ms=%s\n' "${wifi_jitter_ms:--}"
        printf 'wifi.jitter_p95_ms=%s\n' "${wifi_jitter_p95_ms:--}"
        printf 'wifi.jitter_p99_ms=%s\n' "${wifi_jitter_p99_ms:--}"
        printf 'wifi.jitter_score=%s\n' "${wifi_jitter_score:--}"
        printf 'wifi.loss_pct=%s\n' "${wifi_loss_pct:--}"
        printf 'wifi.loss_trend_pct=%s\n' "${wifi_loss_trend_pct:--}"
        printf 'wifi.loss_score=%s\n' "${wifi_loss_score:--}"
        printf 'wifi.probe_ok=%s\n' "$wifi_probe_ok"
        printf 'wifi.bssid=%s\n' "${wifi_bssid:-}"
        printf 'wifi.band=%s\n' "${wifi_band:-}"
        printf 'wifi.chan=%s\n' "${wifi_chan:-}"
        printf 'wifi.freq=%s\n' "${wifi_freq:-}"
        printf 'wifi.width=%s\n' "${wifi_width:-}"
        printf 'wifi.width_source=%s\n' "${wifi_width_source:-}"
        printf 'wifi.width_confidence=%s\n' "${wifi_width_confidence:-}"
        printf 'wifi.ssid=%s\n' "${wifi_ssid:-}"
        printf 'mobile.iface=%s\n' "$mobile_iface"
        printf 'mobile.link=%s\n' "$mobile_link"
        printf 'mobile.ip=%s\n' "$mobile_ip"
        printf 'mobile.egress=%s\n' "$mobile_egress"
        printf 'mobile.score=%s\n' "$out_mobile_score"
        printf 'mobile.reason=%s\n' "$mobile_reason"
        printf 'rsrp_dbm=%s\n' "$out_rsrp"
        printf 'rsrp_score=%s\n' "$out_rsrp_score"
        printf 'sinr_db=%s\n' "$out_sinr"
        printf 'sinr_score=%s\n' "$out_sinr_score"
        printf 'composite_score=%s\n' "$out_composite"
        printf 'composite_ema=%s\n' "$out_composite_ema"
        printf 'lownet.offset=%s\n' "$lownet_offset"
        printf 'profile=%s\n' "${profile:-unknown}"
        printf 'target.state=%s\n' "${target_state:-IDLE}"
        printf 'target.state.reason=%s\n' "${target_state_reason:-}"
        printf 'target.state.ts=%s\n' "${target_state_ts:-0}"
    } | atomic_write "$STATE_FILE"
}
