#!/system/bin/sh

# Snapshot state loading, parsing, and freshness validation.

KITSUNPINGD_SNAPSHOT_FILE="${KITSUNPINGD_SNAPSHOT_FILE:-${MODDIR:-/data/adb/modules/Kitsunping}/cache/daemon.native.state}"
KITSUNPINGD_SNAPSHOT_MAX_AGE_SEC="${KITSUNPINGD_SNAPSHOT_MAX_AGE_SEC:-25}"
KITSUNPINGD_SNAPSHOT_LOADED=0
KITSUNPINGD_SNAPSHOT_VALID=0

kitsunpingd_snapshot_reset() {
    KITSUNPINGD_SNAPSHOT_LOADED=0
    KITSUNPINGD_SNAPSHOT_VALID=0
    KITSUNPINGD_NATIVE_TS=0
    KITSUNPINGD_NATIVE_IFACE=""
    KITSUNPINGD_NATIVE_WIFI_IFACE=""
    KITSUNPINGD_NATIVE_WIFI_LINK=""
    KITSUNPINGD_NATIVE_WIFI_IP=""
    KITSUNPINGD_NATIVE_WIFI_EGRESS=""
    KITSUNPINGD_NATIVE_WIFI_REASON=""
    KITSUNPINGD_NATIVE_WIFI_RSSI=""
    KITSUNPINGD_NATIVE_WIFI_BSSID=""
    KITSUNPINGD_NATIVE_WIFI_BAND=""
    KITSUNPINGD_NATIVE_WIFI_CHAN=""
    KITSUNPINGD_NATIVE_WIFI_FREQ=""
    KITSUNPINGD_NATIVE_WIFI_WIDTH=""
    KITSUNPINGD_NATIVE_WIFI_WIDTH_SOURCE=""
    KITSUNPINGD_NATIVE_WIFI_WIDTH_CONFIDENCE=""
    KITSUNPINGD_NATIVE_WIFI_STANDARD=""
    KITSUNPINGD_NATIVE_WIFI_SSID=""
    KITSUNPINGD_NATIVE_MOBILE_IFACE=""
    KITSUNPINGD_NATIVE_MOBILE_LINK=""
    KITSUNPINGD_NATIVE_MOBILE_IP=""
    KITSUNPINGD_NATIVE_MOBILE_EGRESS=""
    KITSUNPINGD_NATIVE_MOBILE_RAT=""
    KITSUNPINGD_NATIVE_RSRP_DBM=""
    KITSUNPINGD_NATIVE_RSRP_SCORE=""
    KITSUNPINGD_NATIVE_SINR_DB=""
    KITSUNPINGD_NATIVE_SINR_SCORE=""
    KITSUNPINGD_NATIVE_FOREGROUND_PACKAGE=""
}

kitsunpingd_snapshot_load() {
    local now age line key value
    [ "$KITSUNPINGD_SNAPSHOT_LOADED" -eq 1 ] && [ "$KITSUNPINGD_SNAPSHOT_VALID" -eq 1 ] && return 0
    [ "$KITSUNPINGD_SNAPSHOT_LOADED" -eq 1 ] && return 1
    kitsunpingd_snapshot_reset
    KITSUNPINGD_SNAPSHOT_LOADED=1
    [ -r "$KITSUNPINGD_SNAPSHOT_FILE" ] || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *=*) key=${line%%=*}; value=${line#*=} ;;
            *) continue ;;
        esac
        case "$key" in
            native.ts_epoch) KITSUNPINGD_NATIVE_TS="$value" ;;
            iface) KITSUNPINGD_NATIVE_IFACE="$value" ;;
            wifi.iface) KITSUNPINGD_NATIVE_WIFI_IFACE="$value" ;;
            wifi.link) KITSUNPINGD_NATIVE_WIFI_LINK="$value" ;;
            wifi.ip) KITSUNPINGD_NATIVE_WIFI_IP="$value" ;;
            wifi.egress) KITSUNPINGD_NATIVE_WIFI_EGRESS="$value" ;;
            wifi.reason) KITSUNPINGD_NATIVE_WIFI_REASON="$value" ;;
            wifi.rssi_dbm) KITSUNPINGD_NATIVE_WIFI_RSSI="$value" ;;
            wifi.bssid) KITSUNPINGD_NATIVE_WIFI_BSSID="$value" ;;
            wifi.band) KITSUNPINGD_NATIVE_WIFI_BAND="$value" ;;
            wifi.chan) KITSUNPINGD_NATIVE_WIFI_CHAN="$value" ;;
            wifi.freq) KITSUNPINGD_NATIVE_WIFI_FREQ="$value" ;;
            wifi.width) KITSUNPINGD_NATIVE_WIFI_WIDTH="$value" ;;
            wifi.width_source) KITSUNPINGD_NATIVE_WIFI_WIDTH_SOURCE="$value" ;;
            wifi.width_confidence) KITSUNPINGD_NATIVE_WIFI_WIDTH_CONFIDENCE="$value" ;;
            wifi.standard) KITSUNPINGD_NATIVE_WIFI_STANDARD="$value" ;;
            wifi.ssid) KITSUNPINGD_NATIVE_WIFI_SSID="$value" ;;
            mobile.iface) KITSUNPINGD_NATIVE_MOBILE_IFACE="$value" ;;
            mobile.link) KITSUNPINGD_NATIVE_MOBILE_LINK="$value" ;;
            mobile.ip) KITSUNPINGD_NATIVE_MOBILE_IP="$value" ;;
            mobile.egress) KITSUNPINGD_NATIVE_MOBILE_EGRESS="$value" ;;
            mobile.rat) KITSUNPINGD_NATIVE_MOBILE_RAT="$value" ;;
            rsrp_dbm) KITSUNPINGD_NATIVE_RSRP_DBM="$value" ;;
            rsrp_score) KITSUNPINGD_NATIVE_RSRP_SCORE="$value" ;;
            sinr_db) KITSUNPINGD_NATIVE_SINR_DB="$value" ;;
            sinr_score) KITSUNPINGD_NATIVE_SINR_SCORE="$value" ;;
            app.foreground_package) KITSUNPINGD_NATIVE_FOREGROUND_PACKAGE="$value" ;;
        esac
    done < "$KITSUNPINGD_SNAPSHOT_FILE"

    case "$KITSUNPINGD_NATIVE_TS" in ''|*[!0-9]*) return 1 ;; esac
    now="$(date +%s 2>/dev/null || echo 0)"
    case "$now" in ''|*[!0-9]*) return 1 ;; esac
    age=$((now - KITSUNPINGD_NATIVE_TS))
    [ "$age" -lt 0 ] && age=0
    case "$KITSUNPINGD_SNAPSHOT_MAX_AGE_SEC" in ''|*[!0-9]*|0) KITSUNPINGD_SNAPSHOT_MAX_AGE_SEC=25 ;; esac
    [ "$age" -le "$KITSUNPINGD_SNAPSHOT_MAX_AGE_SEC" ] || return 1
    KITSUNPINGD_SNAPSHOT_VALID=1
    return 0
}