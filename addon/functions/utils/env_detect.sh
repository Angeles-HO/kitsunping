#!/system/bin/sh
# Shared environment/binary detection helpers for Kitsunping
# NOTE: This file is sourced by many entrypoints. When sourced, $0 points to the
# caller script, not this file. So do not derive MODDIR assuming a fixed layout.

if [ -z "${MODDIR:-}" ] || [ ! -d "${MODDIR:-/}" ]; then
    case "$0" in
        */addon/*) MODDIR="${0%%/addon/*}" ;;
        *) MODDIR="${0%/*}" ;;
    esac
fi

: "${NEWMODPATH:=${MODDIR}}"

# Resolve preferred ABI folder name used by bundled binaries.
# Returns: arm64|arm
kp_detect_abi() {
    local abi arch
    abi="$(getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r\n')"
    case "$abi" in
        arm64-v8a|aarch64*) echo "arm64"; return 0 ;;
        armeabi-v7a|armeabi*|arm*) echo "arm"; return 0 ;;
    esac

    arch="$(uname -m 2>/dev/null | tr -d '\r\n')"
    case "$arch" in
        aarch64|arm64*) echo "arm64" ;;
        arm*|armv7*) echo "arm" ;;
        *) echo "arm64" ;;
    esac
}

# Build ordered PATH fragment for module tools.
# Keeps backward compatibility with current layout and allows future addon/bin/*.
kp_build_bin_path() {
    local base abi p
    base="$(_kp_base_dir)"
    abi="$(kp_detect_abi)"

    p=""
    for d in \
        "$base/addon/bin/$abi" \
        "$base/addon/bin/common" \
        "$base/addon/ip" \
        "$base/addon/ping" \
        "$base/addon/iw" \
        "$base/addon/jq/$abi" \
        "$base/addon/jq/arm64" \
        "$base/addon/jq/arm" \
        "$base/addon/bc/$abi" \
        "$base/addon/bc/arm64" \
        "$base/addon/bc/arm"
    do
        [ -d "$d" ] || continue
        case ":$p:" in
            *":$d:"*) ;;
            *) p="${p:+$p:}$d" ;;
        esac
    done

    printf '%s' "$p"
}

# Export module binary directories to PATH once (idempotent).
export_kitsunping_bin_path() {
    local kp_path d
    kp_path="$(kp_build_bin_path)"
    [ -n "$kp_path" ] || return 0

    for d in $(printf '%s' "$kp_path" | tr ':' ' '); do
        case ":$PATH:" in
            *":$d:"*) ;;
            *) PATH="$d:$PATH" ;;
        esac
    done

    export PATH
    return 0
}

# Fallback loggers if not already defined
command -v log_info >/dev/null 2>&1 || log_info() { printf '[INFO] %s\n' "$*" >&2; }
command -v log_debug >/dev/null 2>&1 || log_debug() { printf '[DEBUG] %s\n' "$*" >&2; }
command -v log_warning >/dev/null 2>&1 || log_warning() { printf '[WARN] %s\n' "$*" >&2; }
command -v log_error >/dev/null 2>&1 || log_error() { printf '[ERROR] %s\n' "$*" >&2; }
command -v command_exists >/dev/null 2>&1 || command_exists() { command -v "$1" >/dev/null 2>&1; }

# Resolve addon dir (works for MODDIR or NEWMODPATH contexts)
_kp_base_dir() {
    if [ -n "${MODDIR:-}" ] && [ -d "${MODDIR:-/}" ]; then
        printf '%s' "$MODDIR"
        return 0
    fi
    if [ -n "${NEWMODPATH:-}" ] && [ -d "${NEWMODPATH:-/}" ]; then
        printf '%s' "$NEWMODPATH"
        return 0
    fi

    # Last resort guesses (match current module id casing)
    if [ -d /data/adb/modules/Kitsunping ]; then
        printf '%s' /data/adb/modules/Kitsunping
        return 0
    fi
    if [ -d /data/adb/modules_update/Kitsunping ]; then
        printf '%s' /data/adb/modules_update/Kitsunping
        return 0
    fi

    printf '%s' /data/adb/modules/Kitsunping
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
    local base addon_ip addon_bin_ip
    unset IP_BIN
    base=$(_kp_base_dir)
    addon_ip="$base/addon/ip/ip"
    addon_bin_ip="$base/addon/bin/$(kp_detect_abi)/ip"
    if command_exists ip; then
        IP_BIN=$(command -v ip 2>/dev/null)
    elif [ -x "$addon_bin_ip" ]; then
        IP_BIN="$addon_bin_ip"
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
    local extra="$1" c base addon_ping addon_bin_ping
    base=$(_kp_base_dir)
    addon_ping="$base/addon/ping/ping"
    addon_bin_ping="$base/addon/bin/$(kp_detect_abi)/ping"

    export_kitsunping_bin_path

    # First try system path
    if c="$(command -v ping 2>/dev/null)" && [ -x "$c" ]; then
        PING_BIN="$c"
    fi

    # Next try common locations
    if [ -z "$PING_BIN" ]; then
        for c in \
            "$addon_bin_ping" \
            "$addon_ping" \
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

    local loop_target probe_target
    loop_target="${PING_LOOP_TARGET:-127.0.0.1}"
    probe_target="${PING_PROBE_TARGET:-8.8.8.8}"

    if ! "$PING_BIN" -c 1 -W 1 "$loop_target" >/dev/null 2>&1; then
        log_error "Ping missing CAP_NET_RAW or blocked locally: $PING_BIN (loopback $loop_target failed)"

        if command -v getenforce >/dev/null 2>&1 &&
           getenforce | grep -q Enforcing; then
            log_warning "SELinux enforcing may block ping (CAP_NET_RAW); consider 'setenforce 0' or patching sepolicy"
        fi

        if command -v setcap >/dev/null 2>&1; then
            log_info "You can try: setcap cap_net_raw+ep $PING_BIN"
        fi
        if command -v restorecon >/dev/null 2>&1; then
            log_info "Ensure context is correct: restorecon -RF $(dirname "$PING_BIN")"
        fi

        return 1
    fi

    if ! "$PING_BIN" -c 1 -W 1 "$probe_target" >/dev/null 2>&1; then
        log_warning "Ping connectivity check failed for $probe_target; network or DNS may be unavailable"
        return 1
    fi

    return 0
}

check_and_prepare_ping() {
    # 0 = OK, 1 = ping binary not found, 2 = ping not functional
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
    local base abi addon_jq addon_jq_arm addon_bin_jq
    base=$(_kp_base_dir)
    abi="$(kp_detect_abi)"
    addon_jq="$base/addon/jq/$abi/jq"
    addon_jq_arm="$base/addon/jq/arm64/jq"
    addon_bin_jq="$base/addon/bin/$abi/jq"
    JQ_BIN=""
    export_kitsunping_bin_path
    if [ -x "$addon_bin_jq" ]; then
        JQ_BIN="$addon_bin_jq"
    elif [ -x "$addon_jq" ]; then
        JQ_BIN="$addon_jq"
    elif [ -x "$addon_jq_arm" ]; then
        JQ_BIN="$addon_jq_arm"
    elif command_exists jq; then
        JQ_BIN=$(command -v jq 2>/dev/null)
    fi
    [ -n "$JQ_BIN" ] || log_warning "jq not found; falling back to awk where possible"
    export JQ_BIN
    return 0
}

# Detect bc binary; prefer bundled addon bc.
detect_bc_binary() {
    local base abi addon_bc addon_bc_arm64 addon_bin_bc
    base=$(_kp_base_dir)
    abi="$(kp_detect_abi)"
    addon_bc="$base/addon/bc/$abi/bc"
    addon_bc_arm64="$base/addon/bc/arm64/bc"
    addon_bin_bc="$base/addon/bin/$abi/bc"
    BC_BIN=""
    export_kitsunping_bin_path
    if command_exists bc; then
        BC_BIN=$(command -v bc 2>/dev/null)
    elif [ -x "$addon_bin_bc" ]; then
        BC_BIN="$addon_bin_bc"
    elif [ -x "$addon_bc" ]; then
        BC_BIN="$addon_bc"
    elif [ -x "$addon_bc_arm64" ]; then
        BC_BIN="$addon_bc_arm64"
    fi
    [ -n "$BC_BIN" ] || log_warning "bc not found; using fallback scoring"
    export BC_BIN
    return 0
}
