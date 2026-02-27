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

    cat <<EOF | atomic_write "$STATE_FILE"
iface=$current_iface
transport=$transport
wifi.iface=$WIFI_IFACE
wifi.state=$wifi_state
wifi.link=$wifi_link
wifi.ip=$wifi_ip
wifi.egress=$wifi_egress
wifi.score=$out_wifi_score
wifi.reason=$wifi_path_reason
wifi.quality=$wifi_quality_reason
wifi.rssi_dbm=$out_wifi_rssi
wifi.latency_ms=${wifi_latency_ms:--}
wifi.latency_ema_ms=${wifi_latency_ema_ms:--}
wifi.latency_score=$out_wifi_latency_score
wifi.probe_ok=$wifi_probe_ok
wifi.bssid=${wifi_bssid:-}
wifi.band=${wifi_band:-}
wifi.chan=${wifi_chan:-}
wifi.freq=${wifi_freq:-}
wifi.width=${wifi_width:-}
wifi.width_source=${wifi_width_source:-}
wifi.width_confidence=${wifi_width_confidence:-}
wifi.ssid=${wifi_ssid:-}
mobile.iface=$mobile_iface
mobile.link=$mobile_link
mobile.ip=$mobile_ip
mobile.egress=$mobile_egress
mobile.score=$out_mobile_score
mobile.reason=$mobile_reason
rsrp_dbm=$out_rsrp
rsrp_score=$out_rsrp_score
sinr_db=$out_sinr
sinr_score=$out_sinr_score
composite_score=$out_composite
composite_ema=$out_composite_ema
lownet.offset=$lownet_offset
profile=${profile:-unknown}
EOF
}
