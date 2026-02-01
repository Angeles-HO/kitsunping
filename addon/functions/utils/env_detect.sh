#!/system/bin/sh
# Shared environment/binary detection helpers for Kitsunping

# Fallback loggers if not already defined
command -v log_info >/dev/null 2>&1 || log_info() { printf '[INFO] %s\n' "$*" >&2; }
command -v log_debug >/dev/null 2>&1 || log_debug() { printf '[DEBUG] %s\n' "$*" >&2; }
command -v log_warning >/dev/null 2>&1 || log_warning() { printf '[WARN] %s\n' "$*" >&2; }
command -v log_error >/dev/null 2>&1 || log_error() { printf '[ERROR] %s\n' "$*" >&2; }
command -v command_exists >/dev/null 2>&1 || command_exists() { command -v "$1" >/dev/null 2>&1; }

# Resolve addon dir (works for MODDIR or NEWMODPATH contexts)
_kp_base_dir() {
    if [ -n "$MODDIR" ]; then
        printf '%s' "$MODDIR"
    elif [ -n "$NEWMODPATH" ]; then
        printf '%s' "$NEWMODPATH"
    else
        printf '/data/adb/modules/kitsunping'
    fi
}

# Check required commands exist. Accepts a list; defaults to ip ndc resetprop awk.
check_core_commands() {
    local missing=0 cmd
    if [ $# -eq 0 ]; then
        set -- ip ndc resetprop awk
    fi
    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            log_error "Required command '$cmd' not found"
            missing=$((missing + 1))
        fi
    done
    [ $missing -eq 0 ] || return 1
    return 0
}

# Detect ip binary; prefer system, fallback to bundled addon ip.
detect_ip_binary() {
    local base addon_ip
    unset IP_BIN
    base=$(_kp_base_dir)
    addon_ip="$base/addon/ip/ip"
    if command_exists ip; then
        IP_BIN=$(command -v ip 2>/dev/null)
    elif [ -x "$addon_ip" ]; then
        IP_BIN="$addon_ip"
    fi
    if [ -z "$IP_BIN" ]; then
        log_error "ip binary not found"
        return 1
    fi
    # log_debug "IP_BIN resolved to: $IP_BIN" 
    export IP_BIN
    return 0
}

# Detect ping binary; optional extra path (file or dir) as $1.
detect_ping_binary() {
    local extra="$1" c

    # First try system path
    if c="$(command -v ping 2>/dev/null)" && [ -x "$c" ]; then
        PING_BIN="$c"
    fi

    # Next try common locations
    if [ -z "$PING_BIN" ]; then
        for c in \
            /data/adb/modules_update/Kitsunping/addon/ping/ping \
            /system/bin/ping \
            /system/xbin/ping \
            /vendor/bin/ping \
            /data/adb/modules/Kitsunping/addon/ping/ping \
            /data/data/com.termux/files/usr/bin/ping
        do
            [ -x "$c" ] && { PING_BIN="$c"; break; }
        done
    fi

    # Finally try extra path if provided
    if [ -z "$PING_BIN" ] && [ -n "$extra" ]; then
        [ -x "$extra" ] && PING_BIN="$extra"
        [ -x "$extra/ping" ] && PING_BIN="$extra/ping"
    fi

    [ -z "$PING_BIN" ] && {
        log_error "Ping binary not found"
        return 1
    }

    export PING_BIN
    return 0
}


# Add debug logs to identify the issue with ping functionality
ping_is_functional() {
    [ -z "$PING_BIN" ] && return 1

    if ! "$PING_BIN" -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "Ping found but not functional: $PING_BIN"

        if command -v getenforce >/dev/null 2>&1 &&
           getenforce | grep -q Enforcing; then
            log_warning "SELinux enforcing may block ping (CAP_NET_RAW)"
        fi

        return 1
    fi

    return 0
}

check_and_prepare_ping() {
    detect_ping_binary "$1" || return 1
    ping_is_functional || return 2
    # log_debug "Ping OK: $PING_BIN"
    return 0
}

# Detect if daemon is running (pidfile or process name).
# Return 0 if running, 1 if not.
is_daemon_running() {
    local pidfile old_pid base
    base=$(_kp_base_dir)
    for pidfile in "$base/cache/daemon.pid" "${MODDIR:-}/cache/daemon.pid" "${NEWMODPATH:-}/cache/daemon.pid"; do
        if [ -f "$pidfile" ]; then
            old_pid=$(cat "$pidfile" 2>/dev/null)
            if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
                return 0
            fi
        fi
    done
    if pgrep -f '[k]itsunping' >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Detect installation/runin context where daemon may be absent.
# Return 0 if install context, 1 if daemon likely running.
is_install_context() {
    if is_daemon_running; then
        return 1
    fi
    return 0
}

# Detect jq binary; prefer bundled addon jq.
detect_jq_binary() {
    local base addon_jq
    base=$(_kp_base_dir)
    addon_jq="$base/addon/jq/arm64/jq"
    JQ_BIN=""
    if [ -x "$addon_jq" ]; then
        JQ_BIN="$addon_jq"
    elif command_exists jq; then
        JQ_BIN=$(command -v jq 2>/dev/null)
    fi
    [ -n "$JQ_BIN" ] || log_warning "jq not found; falling back to awk where possible"
    export JQ_BIN
    return 0
}

# Detect bc binary; prefer bundled addon bc.
detect_bc_binary() {
    local base addon_bc
    base=$(_kp_base_dir)
    addon_bc="$base/addon/bc/arm64/bc"
    BC_BIN=""
    if command_exists bc; then
        BC_BIN=$(command -v bc 2>/dev/null)
    elif [ -x "$addon_bc" ]; then
        BC_BIN="$addon_bc"
    fi
    [ -n "$BC_BIN" ] || log_warning "bc not found; using fallback scoring"
    export BC_BIN
    return 0
}
