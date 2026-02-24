#!/system/bin/sh
# Shared policy helpers for daemon/executor scripts.

command -v command_exists >/dev/null 2>&1 || command_exists() { command -v "$1" >/dev/null 2>&1; }

command -v atomic_write >/dev/null 2>&1 || atomic_write() {
    local target="$1" tmp
    tmp=$(mktemp "${target}.XXXXXX" 2>/dev/null) || tmp="${target}.$$.$(date +%s).tmp"
    if cat - > "$tmp" 2>/dev/null; then
        mv "$tmp" "$target" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 1
}

command -v now_epoch >/dev/null 2>&1 || now_epoch() {
    local ts src

    ts="$(date +%s 2>/dev/null)"
    case "$ts" in ''|0|*[!0-9]*) ts="" ;; esac

    if [ -z "$ts" ]; then
        ts="$(awk 'BEGIN{print systime()}' 2>/dev/null)"
        case "$ts" in ''|0|*[!0-9]*) ts="" ;; esac
    fi

    if [ -n "$ts" ]; then
        src="epoch"
    elif [ -r /proc/uptime ]; then
        ts="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
        case "$ts" in ''|0|*[!0-9]*) ts=0 ;; esac
        src="uptime"
    else
        ts=0
        src="unknown"
    fi

    NOW_EPOCH_SOURCE="$src"
    printf '%s' "${ts:-0}"
}

command -v is_epoch_like >/dev/null 2>&1 || is_epoch_like() {
    local ts="$1"
    case "$ts" in ''|*[!0-9]*) return 1 ;; esac
    [ "$ts" -ge 1000000000 ]
}

command -v normalize_ts >/dev/null 2>&1 || normalize_ts() {
    local ts="$1"
    case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
    [ "$ts" -gt 0 ] 2>/dev/null || ts=0
    printf '%s' "$ts"
}

command -v epoch_now >/dev/null 2>&1 || epoch_now() {
    local ts fallback_ts
    ts=$(now_epoch)
    case "$ts" in ''|*[!0-9]*) ts=0 ;; esac
    if [ "$ts" -ge 1000000000 ] 2>/dev/null; then
        NOW_EPOCH_SOURCE="epoch"
        printf '%s' "$ts"
        return 0
    fi

    fallback_ts=$(date +%s 2>/dev/null)
    case "$fallback_ts" in ''|*[!0-9]*) fallback_ts=0 ;; esac
    if [ "$fallback_ts" -ge 1000000000 ] 2>/dev/null; then
        NOW_EPOCH_SOURCE="epoch"
        printf '%s' "$fallback_ts"
        return 0
    fi

    NOW_EPOCH_SOURCE="unknown"
    printf '%s' 0
}

command -v pick_event_ts >/dev/null 2>&1 || pick_event_ts() {
    local preferred="$1" env_ts="$2" fallback_ts="$3"
    preferred=$(normalize_ts "$preferred")
    env_ts=$(normalize_ts "$env_ts")
    fallback_ts=$(normalize_ts "$fallback_ts")

    if [ "$preferred" -gt 0 ]; then
        printf '%s' "$preferred"
    elif [ "$env_ts" -gt 0 ]; then
        printf '%s' "$env_ts"
    else
        printf '%s' "$fallback_ts"
    fi
}

command -v pick_score_from_state >/dev/null 2>&1 || pick_score_from_state() {
    local state_file="$1" prefer_transport="${2:-auto}" event_name="${3:-}" event_details="${4:-}"
    local score source transport wifi_state wifi_score mobile_score iface_to

    [ -f "$state_file" ] || return 1

    transport=$(awk -F'=' '/^transport=/{print $2}' "$state_file" | tail -n1)
    wifi_state=$(awk -F'=' '/^wifi.state=/{print $2}' "$state_file" | tail -n1)
    wifi_score=$(awk -F'=' '/^wifi.score=/{print $2}' "$state_file" | tail -n1)
    mobile_score=$(awk -F'=' '/^mobile.score=/{print $2}' "$state_file" | tail -n1)

    case "$wifi_score" in
        ''|*[!0-9.]*) wifi_score="" ;;
    esac
    case "$mobile_score" in
        ''|*[!0-9.]*) mobile_score="" ;;
    esac

    if [ "$prefer_transport" = "auto" ]; then
        case "$event_name" in
            WIFI_JOINED) prefer_transport="wifi" ;;
            WIFI_LEFT|SIGNAL_DEGRADED) prefer_transport="mobile" ;;
            IFACE_CHANGED)
                iface_to=$(printf '%s' "$event_details" | sed -n 's/.*\bto=\([^ ]*\).*/\1/p')
                case "$iface_to" in
                    wlan*|wifi*|wl*) prefer_transport="wifi" ;;
                    rmnet*|ccmni*|pdp*|wwan*) prefer_transport="mobile" ;;
                esac
                ;;
        esac
    fi

    if [ "$prefer_transport" = "auto" ]; then
        case "$transport" in
            wifi|wlan) prefer_transport="wifi" ;;
            mobile|cellular) prefer_transport="mobile" ;;
        esac
    fi

    if [ "$prefer_transport" = "auto" ]; then
        if [ "$wifi_state" = "connected" ]; then
            prefer_transport="wifi"
        else
            prefer_transport="mobile"
        fi
    fi

    if [ "$prefer_transport" = "wifi" ]; then
        if [ "$wifi_state" = "connected" ] && [ -n "$wifi_score" ]; then
            score="$wifi_score"
            source="wifi"
        elif [ -n "$mobile_score" ]; then
            score="$mobile_score"
            source="mobile_fallback"
        elif [ -n "$wifi_score" ]; then
            score="$wifi_score"
            source="wifi_stale_fallback"
        else
            score=""
        fi
    else
        if [ -n "$mobile_score" ]; then
            score="$mobile_score"
            source="mobile"
        elif [ "$wifi_state" = "connected" ] && [ -n "$wifi_score" ]; then
            score="$wifi_score"
            source="wifi_fallback"
        elif [ -n "$wifi_score" ]; then
            score="$wifi_score"
            source="wifi_stale_fallback"
        else
            score=""
        fi
    fi

    [ -n "$score" ] || return 1

    PICK_SCORE_SOURCE="$source"
    PICK_SCORE_PREFER="$prefer_transport"
    PICK_SCORE_TRANSPORT="${transport:-unknown}"
    printf '%s' "$score"
}