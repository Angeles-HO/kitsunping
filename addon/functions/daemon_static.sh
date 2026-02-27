#!/system/bin/sh

# Static/shared daemon helpers extracted from daemon.sh.
# Keep functions side-effect free and safe to source multiple times.

command -v json_escape >/dev/null 2>&1 || json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}

command -v atomic_write >/dev/null 2>&1 || atomic_write() {
    local target="$1" tmp

    tmp=$(mktemp "${target}.XXXXXX" 2>/dev/null) || \
        tmp="${target}.$$.$(date +%s).tmp"

    if cat - > "$tmp" 2>/dev/null; then
        mv "$tmp" "$target" 2>/dev/null || rm -f "$tmp"
    else
        rm -f "$tmp"
        return 1
    fi
}

command -v now_epoch >/dev/null 2>&1 || now_epoch() {
    date +%s 2>/dev/null || awk 'BEGIN{print systime()}' 2>/dev/null || echo 0
}

command -v build_router_signature >/dev/null 2>&1 || build_router_signature() {
    local bssid="$1" band="$2" chan="$3" freq="$4" width="$5" caps="$6" caps_norm
    caps_norm=$(printf '%s' "$caps" | tr '|' ',')
    printf '%s|%s|%s|%s|%s|%s' "${bssid:-}" "${band:-}" "${chan:-}" "${freq:-}" "${width:-}" "${caps_norm:-}"
}

command -v router_dni_short >/dev/null 2>&1 || router_dni_short() {
    local sig="$1" cksum_out
    if command_exists cksum; then
        cksum_out=$(printf '%s' "$sig" | cksum 2>/dev/null | awk '{print $1; exit}')
        [ -n "$cksum_out" ] && { printf '%s' "$cksum_out"; return 0; }
    fi
    printf '%s' "$sig"
}

command -v should_emit_router_caps >/dev/null 2>&1 || should_emit_router_caps() {
    local vendor="$1" caps="$2"
    [ "$vendor" = "gl-inet" ] && printf '%s' "$caps" | grep -E "(vht|he|beamforming|mu-mimo)" >/dev/null 2>&1
}

command -v router_debug_trunc >/dev/null 2>&1 || router_debug_trunc() {
    printf '%s' "$1" | awk '{print substr($0, 1, 800)}'
}

command -v router_debug_log >/dev/null 2>&1 || router_debug_log() {
    [ "${ROUTER_DEBUG:-0}" -eq 1 ] || return 0
    log_debug "$*"
}
