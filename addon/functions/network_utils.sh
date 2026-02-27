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

    # If iface is missing/none or doesn't look like Wi-Fi, try auto-detect.
    # This prevents accidental assignment of mobile ifaces (rmnet/ccmni/...) as Wi-Fi.
    case "$wifi_iface" in
        ''|none|NONE) wifi_iface="" ;;
        wl*|wifi*) ;;
        *) wifi_iface="" ;;
    esac

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

# =============================
# Extended Wi-Fi info helpers
# =============================
WIFI_INFO_CACHE_FILE="${MODDIR}/cache/wifi.info"
IW_CHECK_INTERVAL="${IW_CHECK_INTERVAL:-120}"
IW_BIN=""
IW_USABLE=""
IW_LAST_CHECK=0
WIFI_INFO_SOURCE=""
WIFI_RAW_IW_OUT=""
WIFI_RAW_DUMPSYS_OUT=""

resolve_iw_binary() {
    if [ -n "$IW_BIN" ] && [ -x "$IW_BIN" ]; then
        return 0
    fi

    if [ -n "${MODDIR:-}" ] && [ -x "$MODDIR/addon/iw/iw" ]; then
        IW_BIN="$MODDIR/addon/iw/iw"
        return 0
    fi

    if [ -n "${ADDON_DIR:-}" ] && [ -x "$ADDON_DIR/iw/iw" ]; then
        IW_BIN="$ADDON_DIR/iw/iw"
        return 0
    fi

    if [ -x "/data/adb/modules/Kitsunping/addon/iw/iw" ]; then
        IW_BIN="/data/adb/modules/Kitsunping/addon/iw/iw"
        return 0
    fi

    if command -v iw >/dev/null 2>&1; then
        IW_BIN="$(command -v iw 2>/dev/null)"
        return 0
    fi

    return 1
}

normalize_pipe_list() {
    local s="$1"
    case "$s" in
        *'{'*|*'}'*|*'='*)
            printf '%s' ""
            return 0
            ;;
    esac
    s=$(printf '%s' "$s" | tr ',' ' ' | tr 'A-Z' 'a-z')
    s=$(printf '%s' "$s" | awk '{gsub(/[[:space:]]+/, " "); gsub(/^ | $/, ""); print}')
    [ -z "$s" ] && return 0
    printf '%s' "$s" | awk '{for (i=1;i<=NF;i++) {gsub(/[^a-z0-9._:+-]/, "", $i); if ($i != "") print $i}}' | LC_ALL=C sort -u | \
        awk 'NR==1{printf "%s", $0; next} {printf "|%s", $0} END{print ""}'
}

sanitize_kv_value() {
    local v="$1"
    v=$(printf '%s' "$v" | tr '\r\n\t' '   ')
    v=$(printf '%s' "$v" | awk '{gsub(/[[:space:]]+/, " "); gsub(/^ | $/, ""); print}')
    v=$(printf '%s' "$v" | tr ' ' '_')
    v=$(printf '%s' "$v" | tr -cd '[:alnum:]_.:+@-')
    printf '%s' "$v"
}

normalize_freq_mhz() {
    local f="$1"
    printf '%s' "$f" | awk '{gsub(/[^0-9.]/, ""); if ($0=="") exit; printf "%d", $0+0.5 }'
}

derive_band_from_freq() {
    local f="$1"
    case "$f" in ''|*[!0-9]* ) echo ""; return 0;; esac
    if [ "$f" -ge 2400 ] && [ "$f" -le 2484 ]; then
        echo "2g"
    elif [ "$f" -ge 5150 ] && [ "$f" -le 5850 ]; then
        echo "5g"
    elif [ "$f" -ge 5925 ] && [ "$f" -le 7125 ]; then
        echo "6g"
    else
        echo "unknown"
    fi
}

channel_from_freq() {
    local f="$1" ch=""
    case "$f" in ''|*[!0-9]* ) echo ""; return 0;; esac
    if [ "$f" -ge 2412 ] && [ "$f" -le 2472 ]; then
        ch=$(( (f - 2407) / 5 ))
    elif [ "$f" -eq 2484 ]; then
        ch=14
    elif [ "$f" -ge 5000 ] && [ "$f" -le 5895 ]; then
        ch=$(( (f - 5000) / 5 ))
    elif [ "$f" -ge 5955 ] && [ "$f" -le 7115 ]; then
        ch=$(( (f - 5950) / 5 ))
    fi
    printf '%s' "$ch"
}

iw_is_usable() {
    local now out delta
    resolve_iw_binary || return 1
    now=$(now_epoch)
    case "$now" in ''|*[!0-9]* ) now=0 ;; esac
    delta=$((now - IW_LAST_CHECK))
    if [ -n "$IW_USABLE" ] && [ "$delta" -lt "$IW_CHECK_INTERVAL" ]; then
        [ "$IW_USABLE" -eq 1 ] && return 0 || return 1
    fi
    out=$($IW_BIN dev 2>&1 | awk 'NR==1 {print; exit}')
    IW_LAST_CHECK="$now"
    if printf '%s' "$out" | grep -qi 'Failed to connect to generic netlink'; then
        IW_USABLE=0
        return 1
    fi
    IW_USABLE=1
    return 0
} 

infer_wifi_width_mhz() {
    local band="$1" width="$2" link_speed="$3" inferred_width="" width_source="" width_confidence=""

    if [ -n "$width" ]; then
        printf '%s|%s|%s' "$width" "explicit" "high"
        return 0
    fi

    if [ "${ROUTER_INFER_WIDTH:-0}" -ne 1 ]; then
        printf '%s|%s|%s' "" "" "" 
        return 0
    fi

    if [ "$band" != "5g" ]; then
        printf '%s|%s|%s' "" "" ""
        return 0
    fi

    if ! printf '%s' "$link_speed" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
        printf '%s|%s|%s' "" "" ""
        return 0
    fi

    if awk "BEGIN{exit !($link_speed > 900)}"; then
        inferred_width="160"
        width_source="inferred"
        width_confidence="medium"
    elif awk "BEGIN{exit !($link_speed > 600)}"; then
        inferred_width="80"
        width_source="inferred"
        width_confidence="low"
    fi

    printf '%s|%s|%s' "$inferred_width" "$width_source" "$width_confidence"
}

parse_iw_link_info_text() {
    local out="$1" bssid ssid freq signal rx_rate tx_rate link_speed caps band chan width width_source width_confidence width_guess kv
    if [ -z "$out" ]; then
        out=$(cat 2>/dev/null)
    fi
    [ -z "$out" ] && return 1
    if printf '%s' "$out" | grep -qi 'Not connected'; then
        return 1
    fi

    bssid=$(printf '%s' "$out" | awk '/Connected to/ {print $3; exit}')
    ssid=$(printf '%s' "$out" | awk -F': ' '/SSID:/ {print $2; exit}')
    freq=$(printf '%s' "$out" | awk '/freq:/ {print $2; exit}')
    signal=$(printf '%s' "$out" | awk '/signal:/ {print $2; exit}')
    rx_rate=$(printf '%s' "$out" | awk -F': ' '/rx bitrate:/ {print $2; exit}')
    tx_rate=$(printf '%s' "$out" | awk -F': ' '/tx bitrate:/ {print $2; exit}')
    caps=$(printf '%s' "$out" | awk -F': ' '/bss flags:/ {print $2; exit}')
    width=$(printf '%s' "$out" | grep -Eo 'width:[[:space:]]*[0-9]+' | awk '{print $2; exit}')
    if [ -z "$width" ]; then
        width=$(printf '%s' "$out" | awk '/bitrate:/ {for (i=1;i<=NF;i++) if ($i ~ /MHz/) {gsub(/[^0-9]/, "", $i); if ($i!="") {print $i; exit}}}')
    fi

    freq=$(normalize_freq_mhz "$freq")
    signal=$(printf '%s' "$signal" | awk '{gsub(/[^0-9-]/, ""); print}')
    rx_rate=$(printf '%s' "$rx_rate" | awk '{print $1; exit}')
    tx_rate=$(printf '%s' "$tx_rate" | awk '{print $1; exit}')
    caps=$(normalize_pipe_list "$caps")
    ssid=$(sanitize_kv_value "$ssid")

    if printf '%s' "$rx_rate" | grep -Eq '^[0-9]+([.][0-9]+)?$' && printf '%s' "$tx_rate" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
        link_speed=$(awk -v rx="$rx_rate" -v tx="$tx_rate" 'BEGIN{if(rx>tx) printf "%.1f", rx; else printf "%.1f", tx}')
    elif printf '%s' "$rx_rate" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
        link_speed="$rx_rate"
    elif printf '%s' "$tx_rate" | grep -Eq '^[0-9]+([.][0-9]+)?$'; then
        link_speed="$tx_rate"
    else
        link_speed=""
    fi

    band=""
    chan=""
    if [ -n "$freq" ]; then
        band=$(derive_band_from_freq "$freq")
        chan=$(channel_from_freq "$freq")
    fi

    width_guess=$(infer_wifi_width_mhz "$band" "$width" "$link_speed")
    width=$(printf '%s' "$width_guess" | awk -F'|' '{print $1}')
    width_source=$(printf '%s' "$width_guess" | awk -F'|' '{print $2}')
    width_confidence=$(printf '%s' "$width_guess" | awk -F'|' '{print $3}')

    kv=""
    [ -n "$bssid" ] && kv="$kv bssid=$bssid"
    [ -n "$ssid" ] && kv="$kv ssid=$ssid"
    [ -n "$freq" ] && kv="$kv freq=$freq"
    [ -n "$band" ] && kv="$kv band=$band"
    [ -n "$chan" ] && kv="$kv chan=$chan"
    [ -n "$signal" ] && kv="$kv signal_dbm=$signal"
    [ -n "$width" ] && kv="$kv width=$width"
    [ -n "$width_source" ] && kv="$kv width_source=$width_source"
    [ -n "$width_confidence" ] && kv="$kv width_confidence=$width_confidence"
    [ -n "$link_speed" ] && kv="$kv link_speed=$link_speed"
    [ -n "$rx_rate" ] && kv="$kv rx_rate=$rx_rate"
    [ -n "$tx_rate" ] && kv="$kv tx_rate=$tx_rate"
    [ -n "$caps" ] && kv="$kv caps=$caps"

    printf '%s' "${kv# }"
}

parse_iw_link_info() {
    local wifi_iface="$1" out
    [ -z "$wifi_iface" ] && return 1
    resolve_iw_binary || return 1
    out=$($IW_BIN dev "$wifi_iface" link 2>/dev/null)
    if [ "${ROUTER_DEBUG:-0}" = "1" ]; then
        WIFI_RAW_IW_OUT="$out"
    fi
    parse_iw_link_info_text "$out"
}

parse_dumpsys_wifi_info_text() {
    local out="$1" bssid ssid freq caps link_speed band chan width width_source width_confidence width_guess kv
    if [ -z "$out" ]; then
        out=$(cat 2>/dev/null)
    fi
    [ -z "$out" ] && return 1

    bssid=$(printf '%s\n' "$out" | grep -Eio '([0-9a-f]{2}:){5}[0-9a-f]{2}' | head -n1 | tr 'A-F' 'a-f')
    ssid=$(printf '%s\n' "$out" | sed -nE 's/.*(SSID:|SSID=|ssid=)[[:space:]]*"?([^",]+)"?.*/\2/p' | head -n1)
    freq=$(printf '%s\n' "$out" | sed -nE 's/.*(freq|frequency)[=:][[:space:]]*([0-9]+(\.[0-9]+)?).*/\2/p' | head -n1)
    link_speed=$(printf '%s\n' "$out" | sed -nE 's/.*(linkSpeed|link speed)[=:][[:space:]]*([0-9]+(\.[0-9]+)?).*/\2/p' | head -n1)
    width=$(printf '%s\n' "$out" | sed -nE 's/.*(channelWidth|channel width)[=:][[:space:]]*([0-9]+).*/\2/p' | head -n1)

    caps=$(printf '%s' "$out" | awk '
        /\[.*\]/ {
            s=$0
            if (s ~ /capab|Capabilities|capability|capabilities/ || s ~ /\[HT|\[VHT|\[HE|\[ESS|\[WPA/) {
                sub(/^[^\[]*/, "", s)
                gsub(/\[/, "", s)
                gsub(/\]/, " ", s)
                gsub(/[[:space:]]+/, " ", s)
                gsub(/^ | $/, "", s)
                print s
                exit
            }
        }
    ')

    freq=$(normalize_freq_mhz "$freq")
    caps=$(normalize_pipe_list "$caps")
    ssid=$(sanitize_kv_value "$ssid")

    band=""
    chan=""
    if [ -n "$freq" ]; then
        band=$(derive_band_from_freq "$freq")
        chan=$(channel_from_freq "$freq")
    fi

    width_guess=$(infer_wifi_width_mhz "$band" "$width" "$link_speed")
    width=$(printf '%s' "$width_guess" | awk -F'|' '{print $1}')
    width_source=$(printf '%s' "$width_guess" | awk -F'|' '{print $2}')
    width_confidence=$(printf '%s' "$width_guess" | awk -F'|' '{print $3}')

    kv=""
    [ -n "$bssid" ] && kv="$kv bssid=$bssid"
    [ -n "$ssid" ] && kv="$kv ssid=$ssid"
    [ -n "$freq" ] && kv="$kv freq=$freq"
    [ -n "$band" ] && kv="$kv band=$band"
    [ -n "$chan" ] && kv="$kv chan=$chan"
    [ -n "$link_speed" ] && kv="$kv link_speed=$link_speed"
    [ -n "$width" ] && kv="$kv width=$width"
    [ -n "$width_source" ] && kv="$kv width_source=$width_source"
    [ -n "$width_confidence" ] && kv="$kv width_confidence=$width_confidence"
    [ -n "$caps" ] && kv="$kv caps=$caps"

    printf '%s' "${kv# }"
}

parse_dumpsys_wifi_info() {
    local out
    command_exists dumpsys || return 1
    out=$(dumpsys wifi 2>/dev/null)
    if [ "${ROUTER_DEBUG:-0}" = "1" ]; then
        WIFI_RAW_DUMPSYS_OUT="$out"
    fi
    parse_dumpsys_wifi_info_text "$out"
}

parse_ip_neigh_wifi_info() {
    local wifi_iface="$1" gw mac kv
    [ -z "$wifi_iface" ] && return 1
    [ -z "${IP_BIN:-}" ] && return 1

    gw=$("$IP_BIN" route show default 2>/dev/null | awk -v dev="$wifi_iface" '$0 ~ ("dev " dev) {for (i=1;i<=NF;i++) if ($i=="via") {print $(i+1); exit}}')
    [ -z "$gw" ] && return 1

    mac=$("$IP_BIN" neigh show "$gw" dev "$wifi_iface" 2>/dev/null | awk '{print $5; exit}')
    if ! printf '%s' "$mac" | grep -Eqi '^([0-9a-f]{2}:){5}[0-9a-f]{2}$'; then
        return 1
    fi

    kv="bssid=$(printf '%s' "$mac" | tr 'A-F' 'a-f')"
    printf '%s' "$kv"
}

wifi_cache_write() {
    local cache_file="${WIFI_INFO_CACHE_FILE}" new_val="$1" cur_val=""
    [ -z "$new_val" ] && return 1
    [ -f "$cache_file" ] && cur_val=$(cat "$cache_file" 2>/dev/null | tr -d '\r\n')
    [ "$cur_val" = "$new_val" ] && return 0
    if command_exists atomic_write; then
        printf '%s\n' "$new_val" | atomic_write "$cache_file"
    else
        printf '%s\n' "$new_val" > "$cache_file" 2>/dev/null
    fi
}

# Get extended Wi-Fi info with caching
# Usage: get_wifi_extended_info [IFACE]
# Output: key=value list (caps uses value=a|b)
get_wifi_extended_info() {
    local wifi_iface="${1:-$WIFI_IFACE}" info=""

    WIFI_INFO_SOURCE=""

    if iw_is_usable; then
        info=$(parse_iw_link_info "$wifi_iface")
        [ -n "$info" ] && WIFI_INFO_SOURCE="iw"
    fi

    if [ -z "$info" ]; then
        info=$(parse_dumpsys_wifi_info)
        [ -n "$info" ] && WIFI_INFO_SOURCE="dumpsys"
    fi

    if [ -z "$info" ]; then
        info=$(parse_ip_neigh_wifi_info "$wifi_iface")
        [ -n "$info" ] && WIFI_INFO_SOURCE="ip-neigh"
    fi

    [ -n "$info" ] && wifi_cache_write "$info"
    printf '%s' "$info"
}

# Attempt to detect router vendor from BSSID OUI

detect_router_vendor() {
    local bssid="$1" oui="" bssid_lc o1 o2 o3

    case "$bssid" in
        [0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:*) ;;
        *) printf '%s' "unknown"; return 0 ;;
    esac

    bssid_lc=$(printf '%s' "$bssid" | tr '[:upper:]' '[:lower:]')
    IFS=: read -r o1 o2 o3 _rest <<EOF
$bssid_lc
EOF
    oui="${o1}:${o2}:${o3}"

    case "$oui" in
        00:26:75|28:e3:1f|e8:94:f6) printf '%s' "gl-inet" ;;
        b4:fb:e4) printf '%s' "asus" ;;
        *) printf '%s' "unknown" ;;
    esac
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