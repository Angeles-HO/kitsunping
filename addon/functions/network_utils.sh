#!/system/bin/sh

# Network utility functions

# Return codes (para que el código sea legible)
PING_USABLE=0       # usable para métricas (C=true)
PING_RESPONDS=1     # responde pero sin métricas útiles (A=true, B=false)
PING_NO_RESP=2      # no responde / error (A=false)

# Configurables (se pueden exportar desde el entorno)
PING_COUNT=${PING_COUNT:-3}
PING_TIMEOUT=${PING_TIMEOUT:-2}
MIN_OK_REPLIES=${MIN_OK_REPLIES:-2}

# Get Wi-Fi status
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
        reason="link_up"
    fi

    echo "iface=$wifi_iface link=$link_state ip=$has_ip egress=$def_route reason=$reason"
}

# Get mobile network status
get_mobile_status() {
    local iface="$1" link_state="DOWN" link_up=0 has_ip=0 def_route=0 reason

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
        reason="link_up"
    fi

    echo "iface=$iface link=$link_state ip=$has_ip egress=$def_route reason=$reason"
}

# Get default network interface
get_default_iface() {
    local via_default
    via_default=$("$IP_BIN" route get 8.8.8.8 2>/dev/null | awk '/dev/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    if [ -n "$via_default" ]; then
        echo "$via_default"
        return
    fi
    "$IP_BIN" route show default 2>/dev/null | awk '/dev/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}


# | Estado       | Significado (para calibración / métricas)                         |
# | ------------ | ------------------------------------------------------------------ |
# | FULL_OK      | Ping target usable (con RTT stats) + al menos 1 DNS usable también |
# | DNS_ONLY_OK  | Ping target no usable, pero al menos 1 DNS sí es usable            |
# | PING_ONLY_OK | Ping target usable, pero DNS no usable                             |
# | UNUSABLE     | Nada es usable para métricas (no hay RTT stats)                    |
# test_ping_target
# Separa 3 conceptos (A/B/C) en una sola decisión clara.
#
# A) Reachability: ¿hay respuesta ICMP (o al menos salida de respuesta)?
# B) Metric capability: ¿la salida trae estadísticas (rtt min/avg/max...)?
# C) Usabilidad para calibración: depende de B, NO de A.
#
# Return codes:
# 0 → usable para métricas (C=true)
# 1 → responde pero sin métricas (A=true, B=false, C=false)
# 2 → no responde / error (A=false, B=false, C=false)
#
# Side effects:
# - PROBE_LAST_OUTPUT queda con la salida completa del ping (para parsear avg/jitter/loss si hace falta)
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

    # DNS servers: solo cuentan si son usables para métricas (C depende de B)
    if [ -n "$dns1" ]; then
        test_ping_target "$dns1"
        case $? in
            0) dns_usable=$((dns_usable + 1)) ;;
            1) : ;; # reachability sin métricas → no sirve para calibración
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