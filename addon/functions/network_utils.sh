#!/system/bin/sh

# Network utility functions

# Return codes
PING_USABLE=0       # Can be used for metrics (C=true)
PING_RESPONDS=1     # responds but without useful metrics (A=true, B=false)
PING_NO_RESP=2      # no response / error (A=false)

# Configurables (can be exported from the environment)
PING_COUNT=${PING_COUNT:-3}
PING_TIMEOUT=${PING_TIMEOUT:-2}
MIN_OK_REPLIES=${MIN_OK_REPLIES:-2}

# Get Wi-Fi status with more detailed reason codes
# Returns: iface=IFACE link=STATE ip=HAS_IP egress=DEF_ROUTE reason=REASON
# Usage: get_wifi_status [IFACE]
# Reason codes:
# - link_down: interface is down
# - no_ip: interface is up but has no IP address
# - no_default_route: interface is up with IP but not default route
# - usable_route: interface is up with IP and is default route
get_wifi_status() {
    # vars
    local wifi_iface="${1:-$WIFI_IFACE}" link_state="DOWN" link_up=0 has_ip=0 def_route=0 reason

    # detect wifi interface if not specified
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
    if [ $link_up -eq 1 ]; then
        if [ $has_ip -eq 1 ]; then
            if [ $def_route -eq 1 ]; then
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

# get_mobile_status:
#   Pure diagnostic function. Does not detect or select interfaces.
#   The caller must pass the interface name (e.g., rmnet_data0).
#
# Returns: iface=IFACE link=STATE ip=HAS_IP egress=DEF_ROUTE reason=REASON
# Reason codes:
# - link_down: interface is down
# - no_ip: interface is up but has no IP address
# - no_default_route: interface is up with IP but not default route
# - usable_route: interface is up with IP and is default route
get_mobile_status() {
    # Vars
    local iface="$1" link_state="DOWN" link_up=0 has_ip=0 def_route=0 reason

    # If iface is empty/none, exit fast (diagnostic only; no autodetect)
    if [ -z "$iface" ] || [ "$iface" = "none" ]; then
        echo "iface=none link=DOWN ip=0 egress=0 reason=link_down"
        return 0
    fi

    # Query link state
    link_state=$("$IP_BIN" link show "$iface" 2>/dev/null | awk '/state/ {print $9; exit}')
    [ "$link_state" = "UP" ] && link_up=1

    # Check for IP address
    if "$IP_BIN" addr show "$iface" 2>/dev/null | grep -q "inet "; then
        has_ip=1
    fi

    # Check for default route
    if "$IP_BIN" route get 8.8.8.8 2>/dev/null | grep -q "dev $iface"; then
        def_route=1
    fi

    # This section determines the reason code in if cases
    reason="link_down" # Default reason
    if [ $link_up -eq 1 ]; then # Interface is up
        if [ $has_ip -eq 1 ]; then # Has IP address
            if [ $def_route -eq 1 ]; then # Is default route
                reason="usable_route"
            else
                reason="no_default_route"
            fi
        else
            reason="no_ip"
        fi
    fi

    # Output result
    echo "iface=$iface link=${link_state:-DOWN} ip=$has_ip egress=$def_route reason=$reason"
}

# get_current_iface:
#   Resolves which interface is currently active according to routing policy.
#
# Output: interface name (e.g., wlan0, rmnet_data0) or "" if none found.
# Usage: get_current_iface
get_current_iface() {
    local via_route
    via_route=$("$IP_BIN" route get 8.8.8.8 2>/dev/null | awk '/dev/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    if [ -n "$via_route" ]; then
        echo "$via_route"
        return
    fi
    echo ""
}

# Get Wi-Fi RSSI in dBm (best-effort)
# Usage: get_wifi_rssi_dbm [IFACE]
# Output: integer RSSI (e.g., -55) or empty if unavailable
get_wifi_rssi_dbm() {
    local wifi_iface="${1:-$WIFI_IFACE}" rssi=""

    # Fast path: kernel wireless stats (if present)
    if [ -r /proc/net/wireless ]; then
        rssi=$(awk -v dev="${wifi_iface}:" '$1==dev {print $4; exit}' /proc/net/wireless 2>/dev/null)
        rssi=$(printf '%s' "$rssi" | awk '{gsub(/[^0-9-]/,"",$0); if($0!="") print $0; }')

        # Some kernels/drivers expose signal level as an unsigned byte (0..255)
        # or as a positive magnitude (e.g., 54 meaning -54). Normalize to dBm-like negative values.
        if printf '%s' "$rssi" | grep -Eq '^[0-9]+$'; then
            if [ "$rssi" -ge 128 ] && [ "$rssi" -le 255 ]; then
                # 8-bit two's complement (e.g., 198 -> -58)
                rssi=$((rssi - 256))
            elif [ "$rssi" -gt 0 ] && [ "$rssi" -le 127 ]; then
                rssi=$(( -1 * rssi ))
            fi
        fi
    fi

    # Fallback: dumpsys wifi (heavier)
    if [ -z "$rssi" ] && command_exists dumpsys; then
        rssi=$(dumpsys wifi 2>/dev/null | awk '
            /rssi=/ {
                if (match($0, /rssi=-?[0-9]+/)) {
                    s=substr($0, RSTART, RLENGTH)
                    sub(/rssi=/, "", s)
                    print s
                    exit
                }
            }
            /RSSI:/ {
                if (match($0, /RSSI:[[:space:]]*-?[0-9]+/)) {
                    s=substr($0, RSTART, RLENGTH)
                    sub(/RSSI:[[:space:]]*/, "", s)
                    print s
                    exit
                }
            }
        ')
        rssi=$(printf '%s' "$rssi" | awk '{gsub(/[^0-9-]/,"",$0); if($0!="") print $0; }')
    fi

    printf '%s' "$rssi"
}


# | State       | Description (for calibration / metrics)                         |
# | ------------ | ------------------------------------------------------------------ |
# | FULL_OK      | Ping target usable (with RTT stats) +  more a 1 DNS usable also |
# | DNS_ONLY_OK  | Ping target not usable, but at least 1 DNS is usable            |
# | PING_ONLY_OK | Ping target usable, but DNS not usable                             |
# | UNUSABLE     | Nothing is usable for metrics (no RTT stats)                    |
# test_ping_target
# Divide 3 concepts (A/B/C) into a single clear decision.
#
# A) Reachability: Is there an ICMP response (or at least some response output)?
# B) Metric capability: Does the output include statistics (rtt min/avg/max...)?
# C) Usability for calibration: depends on B, NOT on A.
#
# Return codes:
# 0 →  for metrics (C=true)
# 1 → responds but without metrics (A=true, B=false, C=false)
# 2 → no response / error (A=false, B=false, C=false)
#
# Side effects:
# - PROBE_LAST_OUTPUT  with the complete output of the ping (to parse avg/jitter/loss if needed)
test_ping_target() {
    local target="$1" out rc count timeout min_ok replies

    PROBE_LAST_OUTPUT=""
    PROBE_RTT_MS="9999"
    PROBE_LOSS_PCT="100"

    [ -z "$target" ] && return $PING_NO_RESP
    [ -z "${PING_BIN:-}" ] && return $PING_NO_RESP
    [ ! -x "$PING_BIN" ] && return $PING_NO_RESP

    count="${PING_COUNT:-3}"
    timeout="${PING_TIMEOUT:-2}"
    min_ok="${MIN_OK_REPLIES:-2}"

    case "$count" in ''|*[!0-9]* ) count=3;; esac
    case "$timeout" in ''|*[!0-9]* ) timeout=2;; esac
    case "$min_ok" in ''|*[!0-9]* ) min_ok=2;; esac
    [ "$count" -lt 1 ] && count=3
    [ "$timeout" -lt 1 ] && timeout=2
    [ "$min_ok" -lt 1 ] && min_ok=1
    [ "$min_ok" -gt "$count" ] && min_ok="$count"

    out=$("$PING_BIN" -c "$count" -W "$timeout" "$target" 2>&1)
    rc=$?
    PROBE_LAST_OUTPUT="$out"

    # Parse replies received from summary when available; fallback to counting reply lines.
    replies=$(echo "$out" | awk '
        /packets transmitted|paquetes transmitidos/ {
            for (i=1; i<=NF; i++) {
                if ($i ~ /^received,?$/ || $i ~ /^recibidos,?$/) {
                    if ($(i-1) ~ /^[0-9]+$/) { print $(i-1); exit }
                    if ($(i-2) ~ /^[0-9]+$/) { print $(i-2); exit }
                }
            }
        }
    ')
    if [ -z "$replies" ]; then
        replies=$(echo "$out" | grep -Eci '(bytes from|icmp_seq=|ttl=|time=)')
    fi
    case "$replies" in ''|*[!0-9]* ) replies=0;; esac

    # Parse packet loss percent
    PROBE_LOSS_PCT=$(echo "$out" | awk '
        /packet loss|perdida|p[eé]rdida/ {
            for (i=1; i<=NF; i++) {
                if ($i ~ /^[0-9]+(\.[0-9]+)?%$/) {
                    gsub(/%/, "", $i)
                    print $i
                    found=1
                    exit
                }
                # Locale guard: allow comma decimals like 0,5%
                if ($i ~ /^[0-9]+(,[0-9]+)?%$/) {
                    gsub(/,/, ".", $i)
                    gsub(/%/, "", $i)
                    print $i
                    found=1
                    exit
                }
            }
        }
        END { if (!found) print "100" }
    ' | awk '{gsub(/[^0-9.]/, ""); print}')
    [ -z "$PROBE_LOSS_PCT" ] && PROBE_LOSS_PCT="100"

    # Parse avg RTT (ms) from stats line
    PROBE_RTT_MS=$(echo "$out" | awk -F'=' '
        /rtt min\/avg\/max\/mdev/ || /round-trip min\/avg\/max/ || /min\/avg\/max\/stddev/ {
            if (NF < 2) next
            s=$2
            gsub(/^[ \t]+/, "", s)
            split(s, a, "/")
            r=a[2]
            gsub(/,/, ".", r)
            gsub(/[^0-9.]/, "", r)
            if (r != "") { print r; exit }
        }
    ')
    [ -z "$PROBE_RTT_MS" ] && PROBE_RTT_MS="9999"

    # B) Metric capability + quality gate: require enough replies.
    # Usabilidad (C) depende de B, no de A.
    if echo "$out" | grep -Eqi '(rtt min/avg/max|round-trip min/avg/max|min/avg/max/stddev)' && \
       [ "$replies" -ge "$min_ok" ]; then
        return $PING_USABLE
    fi

    # A) Reachability: any reply counts, even if no stats or not enough replies.
    if [ "$replies" -ge 1 ] || [ $rc -eq 0 ]; then
        return $PING_RESPONDS
    fi

    return $PING_NO_RESP
}

test_dns_ip() {
    local dns1="$1" dns2="$2" ping_ip="$3"
    local dns_usable=0 ping_usable=0

    # DNS servers: only count if usable for metrics (C depends on B)
    if [ -n "$dns1" ]; then
        test_ping_target "$dns1"
        case $? in
            0) dns_usable=$((dns_usable + 1)) ;;
            1) : ;; # reachability without metrics → not useful for calibration
            2) : ;;
        esac
    fi

    if [ -n "$dns2" ]; then
        test_ping_target "$dns2"
        case $? in
            0) dns_usable=$((dns_usable + 1)) ;;
            1) : ;;
            2) : ;;
        esac
    fi

    if [ -n "$ping_ip" ]; then
        test_ping_target "$ping_ip"
        [ $? -eq 0 ] && ping_usable=1
    fi

    # Determine overall status
    if [ $ping_usable -eq 1 ] && [ $dns_usable -ge 1 ]; then
        return 0  # FULL_OK
    elif [ $ping_usable -eq 0 ] && [ $dns_usable -ge 1 ]; then
        return 2  # DNS_ONLY_OK
    elif [ $ping_usable -eq 1 ] && [ $dns_usable -eq 0 ]; then
        return 3  # PING_ONLY_OK
    else
        return 1  # UNUSABLE
    fi
}