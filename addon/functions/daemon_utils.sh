#!/system/bin/sh

# Daemon helper utilities extracted from daemon.sh to keep the main loop lean.

# Compute a base connectivity score from link/IP/egress.
# Usage: get_score LINK_STATE HAS_IP EGRESS
get_score() {
    local link_state="$1" has_ip="$2" egress="$3" score=0

    case "$has_ip" in ''|*[!0-9]* ) has_ip=0;; esac
    case "$egress" in ''|*[!0-9]* ) egress=0;; esac

    [ "$link_state" = "UP" ] && score=$((score + 20))
    [ "$has_ip" -eq 1 ] && score=$((score + 30))
    [ "$egress" -eq 1 ] && score=$((score + 50))
    [ "$link_state" = "UP" ] && [ "$has_ip" -eq 0 ] && score=$((score - 10))

    echo "$score"
}

# Map Wi-Fi RSSI (dBm) to a 0-100 score (best-effort).
# Usage: score_wifi_rssi RSSI_DBM
score_wifi_rssi() {
    local rssi_raw="$1" rssi score
    rssi=$(printf '%s' "${rssi_raw:-}" | awk '{gsub(/[^0-9-]/,"",$0); print $0}')
    case "$rssi" in ''|*[!0-9-]* ) echo ""; return 0;; esac

    if   [ "$rssi" -ge -55 ]; then score=100
    elif [ "$rssi" -ge -65 ]; then score=85
    elif [ "$rssi" -ge -72 ]; then score=70
    elif [ "$rssi" -ge -80 ]; then score=50
    elif [ "$rssi" -ge -87 ]; then score=30
    else score=10
    fi

    echo "$score"
}

# Lightweight connectivity probe (returns 0 if OK, 1 if fail/unavailable).
# Uses PING_BIN if available.
# Env:
#   NET_PROBE_TARGET, NET_PROBE_TIMEOUT
tests_network() {
    local target="${NET_PROBE_TARGET:-8.8.8.8}" timeout="${NET_PROBE_TIMEOUT:-1}"
    local ping_out rc

    NET_LAST_RTT_MS=""

    [ -n "${PING_BIN:-}" ] || return 1
    [ -x "$PING_BIN" ] || return 1

    case "$timeout" in ''|*[!0-9]* ) timeout=1;; esac
    ping_out="$($PING_BIN -c 1 -W "$timeout" "$target" 2>/dev/null || true)"
    rc=$?

    if [ "$rc" -eq 0 ]; then
        NET_LAST_RTT_MS="$(printf '%s\n' "$ping_out" | awk '
            match($0,/time=([0-9]+([.][0-9]+)?)/,a) {
                v=a[1]+0
                if (v < 0) v=0
                printf "%d", (v+0.5)
                exit
            }
        ')"
    fi

    return "$rc"
}

# Map Wi-Fi RTT (ms) to a 0-100 quality score.
# Usage: score_wifi_latency RTT_MS
score_wifi_latency() {
    local rtt_raw="$1" rtt score
    rtt=$(printf '%s' "${rtt_raw:-}" | awk '{gsub(/[^0-9]/,"",$0); print $0}')
    case "$rtt" in ''|*[!0-9]* ) echo ""; return 0;; esac

    if   [ "$rtt" -le 20 ]; then score=100
    elif [ "$rtt" -le 40 ]; then score=90
    elif [ "$rtt" -le 60 ]; then score=80
    elif [ "$rtt" -le 90 ]; then score=65
    elif [ "$rtt" -le 120 ]; then score=50
    elif [ "$rtt" -le 180 ]; then score=35
    elif [ "$rtt" -le 250 ]; then score=20
    else score=10
    fi

    echo "$score"
}

# Human-readable reason from score.
# Usage: get_reason_from_score SCORE
get_reason_from_score() {
    local score="$1"
    case "$score" in ''|*[!0-9]* ) score=0;; esac

    if [ "$score" -ge 80 ]; then
        echo "good"
    elif [ "$score" -ge 40 ]; then
        echo "degraded"
    else
        echo "bad"
    fi
}
