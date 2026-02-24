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

POLICY_COMMON_SH="${ADDON_DIR}/functions/policy_common.sh"
if [ -f "$POLICY_COMMON_SH" ]; then
    . "$POLICY_COMMON_SH"
fi

# logging helpers: define only if not already present
command -v log_info >/dev/null 2>&1 || log_info() { printf '[DAEMON][INFO] %s\n' "$*" >&2; }
command -v log_debug >/dev/null 2>&1 || log_debug() { printf '[DAEMON][DEBUG] %s\n' "$*" >&2; }
command -v log_warning >/dev/null 2>&1 || log_warning() { printf '[DAEMON][WARN] %s\n' "$*" >&2; }
command -v log_error >/dev/null 2>&1 || log_error() { printf '[DAEMON][ERROR] %s\n' "$*" >&2; }
command -v log_policy >/dev/null 2>&1 || log_policy() { printf '[POLICY] %s\n' "$*" >&2; }

command -v heavy_load_prop_name >/dev/null 2>&1 || heavy_load_prop_name() {
    printf '%s' "${HEAVY_LOAD_PROP:-kitsunping.heavy_load}"
}

command -v is_uint >/dev/null 2>&1 || is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

command -v heavy_load_read >/dev/null 2>&1 || heavy_load_read() {
    local prop_name raw
    prop_name="$(heavy_load_prop_name)"
    raw="$(getprop "$prop_name" 2>/dev/null | tr -d '\r\n')"
    is_uint "$raw" || raw=0
    [ "$raw" -lt 0 ] 2>/dev/null && raw=0
    printf '%s' "$raw"
}

command -v heavy_load_write >/dev/null 2>&1 || heavy_load_write() {
    local value="$1" prop_name
    prop_name="$(heavy_load_prop_name)"
    is_uint "$value" || value=0
    [ "$value" -lt 0 ] 2>/dev/null && value=0
    if command -v setprop >/dev/null 2>&1; then
        setprop "$prop_name" "$value" >/dev/null 2>&1 || true
    elif command -v resetprop >/dev/null 2>&1; then
        resetprop "$prop_name" "$value" >/dev/null 2>&1 || true
    fi
    printf '%s' "$value"
}

command -v heavy_load_begin >/dev/null 2>&1 || heavy_load_begin() {
    local current next
    current="$(heavy_load_read)"
    is_uint "$current" || current=0
    next=$((current + 1))
    heavy_load_write "$next" >/dev/null
    printf '%s' "$next"
}

command -v heavy_load_end >/dev/null 2>&1 || heavy_load_end() {
    local current next
    current="$(heavy_load_read)"
    is_uint "$current" || current=0
    next=$((current - 1))
    [ "$next" -lt 0 ] && next=0
    heavy_load_write "$next" >/dev/null
    printf '%s' "$next"
}

command -v calibration_priority_prop_name >/dev/null 2>&1 || calibration_priority_prop_name() {
    printf '%s' "${CALIBRATION_PRIORITY_PROP:-kitsunping.calibration.priority}"
}

command -v calibration_priority_read >/dev/null 2>&1 || calibration_priority_read() {
    local prop_name raw
    prop_name="$(calibration_priority_prop_name)"
    raw="$(getprop "$prop_name" 2>/dev/null | tr -d '\r\n')"
    case "$raw" in
        1|true|TRUE|yes|YES|on|ON) printf '%s' 1 ;;
        *) printf '%s' 0 ;;
    esac
}

command -v calibration_priority_write >/dev/null 2>&1 || calibration_priority_write() {
    local value="$1" prop_name
    prop_name="$(calibration_priority_prop_name)"
    case "$value" in
        1|true|TRUE|yes|YES|on|ON) value=1 ;;
        *) value=0 ;;
    esac
    if command -v setprop >/dev/null 2>&1; then
        setprop "$prop_name" "$value" >/dev/null 2>&1 || true
    elif command -v resetprop >/dev/null 2>&1; then
        resetprop "$prop_name" "$value" >/dev/null 2>&1 || true
    fi
    printf '%s' "$value"
}

command -v heavy_activity_lock_dir >/dev/null 2>&1 || heavy_activity_lock_dir() {
    printf '%s' "${HEAVY_ACTIVITY_LOCK_DIR:-$MODDIR/cache/heavy_activity.lock}"
}

command -v heavy_activity_lock_acquire >/dev/null 2>&1 || heavy_activity_lock_acquire() {
    local lock_dir pidfile old_pid
    lock_dir="$(heavy_activity_lock_dir)"
    pidfile="$lock_dir/pid"

    if mkdir "$lock_dir" 2>/dev/null; then
        echo "$$" > "$pidfile" 2>/dev/null || true
        return 0
    fi

    if [ -f "$pidfile" ]; then
        old_pid="$(cat "$pidfile" 2>/dev/null)"
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            return 1
        fi
    fi

    rm -rf "$lock_dir" 2>/dev/null || true
    if mkdir "$lock_dir" 2>/dev/null; then
        echo "$$" > "$pidfile" 2>/dev/null || true
        return 0
    fi
    return 1
}

command -v heavy_activity_lock_release >/dev/null 2>&1 || heavy_activity_lock_release() {
    local lock_dir
    lock_dir="$(heavy_activity_lock_dir)"
    rm -rf "$lock_dir" 2>/dev/null || true
}

# JSON escape helper
command -v json_escape >/dev/null 2>&1 || json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
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
