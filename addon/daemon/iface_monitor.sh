#!/system/bin/sh
# Network interrogators: get_signal_quality, get_wifi_status, get_mobile_status, get_default_iface

get_default_iface() {
    local via_default
    via_default=$("$IP_BIN" route get 8.8.8.8 2>/dev/null | awk '/dev/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    if [ -n "$via_default" ]; then
        echo "$via_default"
        return
    fi
    "$IP_BIN" route show default 2>/dev/null | awk '/dev/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

get_wifi_status() {
    local wifi_iface="${1:-$WIFI_IFACE}" link_state="DOWN" link_up=0 has_ip=0 def_route=0 dhcp_ip reason

    link_state=$("$IP_BIN" link show "$wifi_iface" 2>/dev/null | awk '/state/ {print $9; exit}')
    [ "$link_state" = "UP" ] && link_up=1

    if "$IP_BIN" addr show "$wifi_iface" 2>/dev/null | grep -q "inet "; then
        has_ip=1
    fi

    dhcp_ip=$(getprop dhcp.${wifi_iface}.ipaddress 2>/dev/null)
    [ -n "$dhcp_ip" ] && has_ip=1

    if "$IP_BIN" route get 8.8.8.8 2>/dev/null | grep -q "dev $wifi_iface"; then
        def_route=1
    fi

    reason="link_down"
    if [ $link_up -eq 1 ]; then
        if [ $has_ip -eq 1 ]; then
            if [ $def_route -eq 1 ]; then
                reason="usable_route"
            else
                reason="no_egress"
            fi
        else
            reason="no_ip"
        fi
    fi

    echo "iface=$wifi_iface link=$link_state ip=$has_ip egress=$def_route reason=$reason"
}

get_mobile_status() {
    local iface="$1" link_state="DOWN" link_up=0 has_ip=0 def_route=0 reason

    [ -z "$iface" ] && iface="none"
    [ "$iface" = "none" ] && { echo "iface=none link=DOWN ip=0 egress=0 reason=not_found"; return; }

    link_state=$("$IP_BIN" link show "$iface" 2>/dev/null | awk '/state/ {print $9; exit}')
    [ "$link_state" = "UP" ] && link_up=1

    if "$IP_BIN" addr show "$iface" 2>/dev/null | grep -q "inet "; then
        has_ip=1
    fi

    if "$IP_BIN" route get 8.8.8.8 2>/dev/null | grep -q "dev $iface"; then
        def_route=1
    fi

    reason="link_down"
    if [ $link_up -eq 1 ]; then
        if [ $has_ip -eq 1 ]; then
            if [ $def_route -eq 1 ]; then
                reason="usable_route"
            else
                reason="no_egress"
            fi
        else
            reason="no_ip"
        fi
    fi

    echo "iface=$iface link=$link_state ip=$has_ip egress=$def_route reason=$reason"
}

get_signal_quality() {
    local dump tech rsrp="" rssi="" asu="" sinr="" quality_score=0 ts

    ts=$(date +%s 2>/dev/null || echo 0)

    if ! command_exists dumpsys; then
        printf '{"error":"dumpsys not available","quality_score":0,"timestamp":%s}\n' "$ts"
        return 1
    fi

    dump=$(dumpsys telephony.registry 2>/dev/null)
    if [ -z "$dump" ]; then
        printf '{"error":"dumpsys empty","quality_score":0,"timestamp":%s}\n' "$ts"
        return 1
    fi
 
    tech=$(printf '%s' "$dump" | grep "mDataConnectionTech" | head -1 | awk -F'=' '{print $2}' | tr -d '[:space:]')

    case "$tech" in
        *LTE*|*NR*)
            local signal_line
            signal_line=$(printf '%s' "$dump" | grep "mLteSignalStrength" | head -1)
            if [ -n "$signal_line" ]; then
                rsrp=$(echo "$signal_line" | awk '{print $(NF-2)}')
                sinr=$(echo "$signal_line" | awk '{print $(NF-1)}')
            fi
            ;;
        *WCDMA*|*HSPAP*|*HSDPA*|*HSUPA*)
            local signal_line
            signal_line=$(printf '%s' "$dump" | grep "mSignalStrength" | head -1)
            if [ -n "$signal_line" ]; then
                rssi=$(echo "$signal_line" | awk '{print $3}')
                [ "$rssi" = "-1" ] && rssi=$(echo "$signal_line" | awk '{print $4}')
            fi
            ;;
        *GSM*|*EDGE*|*GPRS*)
            local signal_line
            signal_line=$(printf '%s' "$dump" | grep "mSignalStrength" | head -1)
            if [ -n "$signal_line" ]; then
                asu=$(echo "$signal_line" | awk '{print $2}')
                if echo "$asu" | grep -Eq '^[0-9]+$' && [ "$asu" -ne 99 ]; then
                    rssi=$(( -113 + (2 * asu) ))
                fi
            fi
            ;;
    esac

    if [ -n "$rsrp" ] && echo "$rsrp" | grep -Eq '^-?[0-9]+$' && [ "$rsrp" -ne -1 ] && [ "$rsrp" -ne 2147483647 ]; then
        if   [ "$rsrp" -ge -85 ];  then quality_score=100
        elif [ "$rsrp" -ge -95 ];  then quality_score=80
        elif [ "$rsrp" -ge -105 ]; then quality_score=60
        elif [ "$rsrp" -ge -115 ]; then quality_score=40
        else                            quality_score=20
        fi
    elif [ -n "$rssi" ] && echo "$rssi" | grep -Eq '^-?[0-9]+$' && [ "$rssi" -ne -1 ]; then
        if   [ "$rssi" -ge -70 ];  then quality_score=100
        elif [ "$rssi" -ge -85 ];  then quality_score=75
        elif [ "$rssi" -ge -100 ]; then quality_score=50
        elif [ "$rssi" -ge -110 ]; then quality_score=25
        else                             quality_score=10
        fi
    fi

    cat <<EOF
{
  "technology": "${tech:-unknown}",
  "rsrp_dbm": "${rsrp:--}",
  "rssi_dbm": "${rssi:--}",
  "sinr_db": "${sinr:--}",
  "asu": "${asu:--}",
  "quality_score": $quality_score,
  "timestamp": $ts
}
EOF
}
