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

    [ -n "${PING_BIN:-}" ] || return 1
    [ -x "$PING_BIN" ] || return 1

    case "$timeout" in ''|*[!0-9]* ) timeout=1;; esac
    "$PING_BIN" -c 1 -W "$timeout" "$target" >/dev/null 2>&1
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
