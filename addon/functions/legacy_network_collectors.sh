#!/system/bin/sh

# Legacy fallback collectors for network_utils.sh. They are intentionally kept
# separate from the snapshot bridge so they can be retired as a unit once the
# native sidecar is authoritative for all supported runtime paths.

legacy_get_wifi_status() {
    local wifi_iface="${1:-${WIFI_IFACE:-}}" link_state="DOWN" link_up=0 has_ip=0 def_route=0 reason

    case "$wifi_iface" in
        ''|none|NONE) wifi_iface="" ;;
        wl*|wifi*) ;;
        *) wifi_iface="" ;;
    esac

    if [ -z "$wifi_iface" ]; then
        wifi_iface=$("$IP_BIN" link show | awk -F: '/wl|wifi/ {gsub(/ /,"",$2); print $2; exit}')
        [ -z "$wifi_iface" ] && wifi_iface="none"
    fi

    link_state=$("$IP_BIN" link show "$wifi_iface" 2>/dev/null | awk '/state/ {print $9; exit}')
    [ "$link_state" = "UP" ] && link_up=1

    if "$IP_BIN" addr show "$wifi_iface" 2>/dev/null | grep -q "inet "; then
        has_ip=1
    fi

    if "$IP_BIN" route get 8.8.8.8 2>/dev/null | grep -q "dev $wifi_iface"; then
        def_route=1
    fi

    reason="link_down"
    if [ "$link_up" -eq 1 ]; then
        if [ "$has_ip" -eq 1 ]; then
            if [ "$def_route" -eq 1 ]; then
                reason="usable_route"
            else
                reason="no_default_route"
            fi
        else
            reason="no_ip"
        fi
    fi

    echo "iface=$wifi_iface link=$link_state ip=$has_ip egress=$def_route reason=$reason"
}

legacy_get_mobile_status() {
    local iface="$1" link_state="DOWN" link_up=0 has_ip=0 def_route=0 reason

    if [ -z "$iface" ] || [ "$iface" = "none" ]; then
        echo "iface=none link=DOWN ip=0 egress=0 reason=link_down"
        return 0
    fi

    link_state=$("$IP_BIN" link show "$iface" 2>/dev/null | awk '/state/ {print $9; exit}')
    [ "$link_state" = "UP" ] && link_up=1

    if "$IP_BIN" addr show "$iface" 2>/dev/null | grep -q "inet "; then
        has_ip=1
    fi

    if "$IP_BIN" route get 8.8.8.8 2>/dev/null | grep -q "dev $iface"; then
        def_route=1
    fi

    reason="link_down"
    if [ "$link_up" -eq 1 ]; then
        if [ "$has_ip" -eq 1 ]; then
            if [ "$def_route" -eq 1 ]; then
                reason="usable_route"
            else
                reason="no_default_route"
            fi
        else
            reason="no_ip"
        fi
    fi

    echo "iface=$iface link=${link_state:-DOWN} ip=$has_ip egress=$def_route reason=$reason"
}

legacy_get_current_iface() {
    local via_route

    via_route=$("$IP_BIN" route get 8.8.8.8 2>/dev/null | awk '/dev/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    if [ -n "$via_route" ]; then
        echo "$via_route"
        return
    fi
    echo ""
}