#!/system/bin/sh

# Native snapshot readers. Loading, parsing, and freshness validation live in
# snapshot_loader.sh; public helpers in network_utils.sh select reader or
# legacy fallback collector.
KITSUNPINGD_SNAPSHOT_LOADER_FILE="${KITSUNPINGD_SNAPSHOT_LOADER_FILE:-${KITSUNPINGD_SNAPSHOT_BRIDGE_FILE%/*}/snapshot_loader.sh}"

[ -r "$KITSUNPINGD_SNAPSHOT_LOADER_FILE" ] && . "$KITSUNPINGD_SNAPSHOT_LOADER_FILE"

kitsunpingd_native_iface_is_valid() {
    case "$1" in
        none) return 0 ;;
        ''|*[![:alnum:]_.:-]*) return 1 ;;
        *) return 0 ;;
    esac
}

kitsunpingd_native_link_is_valid() {
    case "$1" in
        UP|DOWN|UNKNOWN) return 0 ;;
        *) return 1 ;;
    esac
}

kitsunpingd_native_flag_is_valid() {
    case "$1" in
        0|1) return 0 ;;
        *) return 1 ;;
    esac
}

get_native_wifi_status() {
    local wifi_iface wifi_link wifi_ip wifi_egress wifi_reason
    kitsunpingd_snapshot_load || return 1
    wifi_iface="${KITSUNPINGD_NATIVE_WIFI_IFACE:-none}"
    [ -n "$wifi_iface" ] || wifi_iface="none"
    wifi_link="${KITSUNPINGD_NATIVE_WIFI_LINK:-DOWN}"
    wifi_ip="${KITSUNPINGD_NATIVE_WIFI_IP:-0}"
    wifi_egress="${KITSUNPINGD_NATIVE_WIFI_EGRESS:-0}"
    kitsunpingd_native_iface_is_valid "$wifi_iface" || return 1
    kitsunpingd_native_link_is_valid "$wifi_link" || return 1
    kitsunpingd_native_flag_is_valid "$wifi_ip" || return 1
    kitsunpingd_native_flag_is_valid "$wifi_egress" || return 1

    wifi_reason="link_down"
    if [ "$wifi_link" = "UP" ]; then
        if [ "$wifi_ip" = "1" ]; then
            if [ "$wifi_egress" = "1" ]; then
                wifi_reason="usable_route"
            else
                wifi_reason="no_default_route"
            fi
        else
            wifi_reason="no_ip"
        fi
    fi
    printf 'iface=%s link=%s ip=%s egress=%s reason=%s\n' \
        "$wifi_iface" "$wifi_link" "$wifi_ip" "$wifi_egress" "$wifi_reason"
}

get_native_mobile_status() {
    local iface="$1" native_iface native_link native_ip native_egress native_reason
    kitsunpingd_snapshot_load || return 1
    native_iface="${KITSUNPINGD_NATIVE_MOBILE_IFACE:-none}"
    [ -n "$native_iface" ] || native_iface="none"
    native_link="${KITSUNPINGD_NATIVE_MOBILE_LINK:-DOWN}"
    native_ip="${KITSUNPINGD_NATIVE_MOBILE_IP:-0}"
    native_egress="${KITSUNPINGD_NATIVE_MOBILE_EGRESS:-0}"
    kitsunpingd_native_iface_is_valid "$native_iface" || return 1
    kitsunpingd_native_link_is_valid "$native_link" || return 1
    kitsunpingd_native_flag_is_valid "$native_ip" || return 1
    kitsunpingd_native_flag_is_valid "$native_egress" || return 1
    if [ "$iface" != "$native_iface" ]; then
        if [ -n "$iface" ] && [ "$iface" != "none" ]; then
            return 1
        fi
        [ "$native_iface" = "none" ] || return 1
    fi

    native_reason="link_down"
    if [ "$native_link" = "UP" ]; then
        if [ "$native_ip" = "1" ]; then
            if [ "$native_egress" = "1" ]; then
                native_reason="usable_route"
            else
                native_reason="no_default_route"
            fi
        else
            native_reason="no_ip"
        fi
    fi
    printf 'iface=%s link=%s ip=%s egress=%s reason=%s\n' \
        "$native_iface" "$native_link" "$native_ip" "$native_egress" \
        "$native_reason"
}

get_native_current_iface() {
    kitsunpingd_snapshot_reset
    kitsunpingd_snapshot_load || return 1
    kitsunpingd_native_iface_is_valid "${KITSUNPINGD_NATIVE_IFACE:-none}" || return 1
    [ "${KITSUNPINGD_NATIVE_IFACE:-none}" = "none" ] || printf '%s' "$KITSUNPINGD_NATIVE_IFACE"
}

get_native_wifi_rssi_dbm() {
    kitsunpingd_snapshot_load || return 1
    case "${KITSUNPINGD_NATIVE_WIFI_RSSI:-}" in
        ''|-) return 1 ;;
        *) printf '%s' "$KITSUNPINGD_NATIVE_WIFI_RSSI" ;;
    esac
}

get_native_mobile_signal_quality() {
    local rsrp sinr rsrp_score sinr_score technology

    kitsunpingd_snapshot_load || return 1
    [ "${KITSUNPINGD_NATIVE_MOBILE_EGRESS:-0}" = "1" ] || return 1
    rsrp="${KITSUNPINGD_NATIVE_RSRP_DBM:--}"
    sinr="${KITSUNPINGD_NATIVE_SINR_DB:--}"
    case "$rsrp" in -|'') ;; *[!0-9-]*) return 1 ;; esac
    case "$sinr" in -|'') ;; *[!0-9-]*) return 1 ;; esac
    [ "$rsrp" != "-" ] || [ "$sinr" != "-" ] || return 1

    rsrp_score="${KITSUNPINGD_NATIVE_RSRP_SCORE:-0}"
    sinr_score="${KITSUNPINGD_NATIVE_SINR_SCORE:-0}"
    case "$rsrp_score" in *[!0-9]*|'') rsrp_score=0 ;; esac
    case "$sinr_score" in *[!0-9]*|'') sinr_score=0 ;; esac
    technology="${KITSUNPINGD_NATIVE_MOBILE_RAT:-unknown}"
    case "$technology" in *[!A-Za-z0-9_-]*|'') technology=unknown ;; esac

    printf '{"technology":"%s","rsrp_dbm":"%s","rssi_dbm":"-","sinr_db":"%s","asu":"-","quality_score":%s,"rsrp_score":%s,"sinr_score":%s,"source":"kitsunpingd"}\n' \
        "$technology" "$rsrp" "$sinr" "$rsrp_score" "$rsrp_score" "$sinr_score"
}

get_native_wifi_extended_info() {
    local wifi_iface="$1" info="" native_iface

    kitsunpingd_snapshot_load || return 1
    native_iface="${KITSUNPINGD_NATIVE_WIFI_IFACE:-}"
    [ -n "$native_iface" ] || return 1
    [ "$wifi_iface" = "$native_iface" ] || return 1
    [ -n "${KITSUNPINGD_NATIVE_WIFI_BSSID:-}" ] || [ -n "${KITSUNPINGD_NATIVE_WIFI_SSID:-}" ] || return 1

    [ -n "${KITSUNPINGD_NATIVE_WIFI_BSSID:-}" ] && info="$info bssid=$KITSUNPINGD_NATIVE_WIFI_BSSID"
    [ -n "${KITSUNPINGD_NATIVE_WIFI_SSID:-}" ] && info="$info ssid=$KITSUNPINGD_NATIVE_WIFI_SSID"
    [ -n "${KITSUNPINGD_NATIVE_WIFI_FREQ:-}" ] && info="$info freq=$KITSUNPINGD_NATIVE_WIFI_FREQ"
    [ -n "${KITSUNPINGD_NATIVE_WIFI_BAND:-}" ] && info="$info band=$KITSUNPINGD_NATIVE_WIFI_BAND"
    [ -n "${KITSUNPINGD_NATIVE_WIFI_CHAN:-}" ] && info="$info chan=$KITSUNPINGD_NATIVE_WIFI_CHAN"
    [ -n "${KITSUNPINGD_NATIVE_WIFI_WIDTH:-}" ] && info="$info width=$KITSUNPINGD_NATIVE_WIFI_WIDTH"
    [ -n "${KITSUNPINGD_NATIVE_WIFI_WIDTH_SOURCE:-}" ] && info="$info width_source=$KITSUNPINGD_NATIVE_WIFI_WIDTH_SOURCE"
    [ -n "${KITSUNPINGD_NATIVE_WIFI_WIDTH_CONFIDENCE:-}" ] && info="$info width_confidence=$KITSUNPINGD_NATIVE_WIFI_WIDTH_CONFIDENCE"
    [ -n "${KITSUNPINGD_NATIVE_WIFI_STANDARD:-}" ] && info="$info wifi_standard=$KITSUNPINGD_NATIVE_WIFI_STANDARD"
    [ -n "${KITSUNPINGD_NATIVE_WIFI_RSSI:-}" ] && [ "$KITSUNPINGD_NATIVE_WIFI_RSSI" != "-" ] && info="$info signal_dbm=$KITSUNPINGD_NATIVE_WIFI_RSSI"
    printf '%s' "${info# }"
}

get_native_foreground_package() {
    local package

    kitsunpingd_snapshot_load || return 1
    package="${KITSUNPINGD_NATIVE_FOREGROUND_PACKAGE:-}"
    case "$package" in
        *.*|*_* ) ;;
        *) return 1 ;;
    esac
    case "$package" in
        *[![:alnum:]_.]*|.*|*.|*..*) return 1 ;;
    esac
    printf '%s' "$package"
}