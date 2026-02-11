#!/system/bin/sh
# Core helper functions (safe: define only if missing)
# NOTE: This file is frequently *sourced* by other scripts. Do not derive paths
# from $0 unconditionally (when sourced, $0 is the caller).

# Resolve module root without clobbering existing values.
if [ -z "${MODDIR:-}" ] || [ ! -d "${MODDIR:-/}" ]; then
    case "$0" in
        */addon/*) MODDIR="${0%%/addon/*}" ;;
        *) MODDIR="${0%/*}" ;;
    esac
fi

: "${NEWMODPATH:=${MODDIR}}"
: "${ADDON_DIR:=${MODDIR}/addon}"

# logging helpers: define only if not already present
command -v log_info >/dev/null 2>&1 || log_info() { printf '[DAEMON][INFO] %s\n' "$*" >&2; }
command -v log_debug >/dev/null 2>&1 || log_debug() { printf '[DAEMON][DEBUG] %s\n' "$*" >&2; }
command -v log_warning >/dev/null 2>&1 || log_warning() { printf '[DAEMON][WARN] %s\n' "$*" >&2; }
command -v log_error >/dev/null 2>&1 || log_error() { printf '[DAEMON][ERROR] %s\n' "$*" >&2; }
command -v log_policy >/dev/null 2>&1 || log_policy() { printf '[POLICY] %s\n' "$*" >&2; }

# function existence helper for portability
command -v command_exists >/dev/null 2>&1 || command_exists() { command -v "$1" >/dev/null 2>&1; }

# JSON escape helper
command -v json_escape >/dev/null 2>&1 || json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}

# Atomic write helper
command -v atomic_write >/dev/null 2>&1 || atomic_write() {
    local target="$1" tmp
    tmp=$(mktemp "${target}.XXXXXX") || tmp="${target}.$$.$(date +%s).tmp"
    if cat - > "$tmp" 2>/dev/null; then
        mv "$tmp" "$target" 2>/dev/null || rm -f "$tmp"
    else
        rm -f "$tmp"
        return 1
    fi
}

# Epoch helper
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

# portable rounding helper
command -v to_int >/dev/null 2>&1 || to_int() {
    local v
    v="${1:-0}"
    printf '%s' "$(printf '%s' "$v" | awk '{ if ($0=="" ) {print 0; exit} if ($0+0==$0) { if($0>=0) printf("%d", ($0+0.5)); else printf("%d", ($0-0.5)); } else {print 0} }')"
}

# Source Kitsutils for shared utilities (optional)
if [ -f "$MODDIR/addon/functions/utils/Kitsutils.sh" ]; then
    . "$MODDIR/addon/functions/utils/Kitsutils.sh"
fi
