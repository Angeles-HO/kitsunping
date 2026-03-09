#!/system/bin/sh
# Daemon: log interface and Wi-Fi/mobile transitions
# ============== Roadmap Status ==============
# DONE: Add ping and latency metrics to evaluate connection quality (RTT + latency score + EMA)
# TODO: [PENDING] Add support for multiple Wi-Fi interfaces (requires multi-iface device testing) TODO:
# TODO: [PENDING] Add support for multiple mobile interfaces (requires multi-modem/multi-rmnet testing) TODO:
# DONE: Modularize daemon code into separate function modules
# TODO: [PENDING] Add IPv6 support (currently IPv4-focused path) TODO:
# DONE: Add app notifications/broadcast integration for daemon events
# TODO: [IN_PROGRESS] Add support for richer custom policy rules (external scripts already supported, needs expansion) TODO:
# TODO: [PENDING] Add historical metrics persistence (rotating logs / lightweight DB) TODO:
# TODO: [PENDING] Add trend analysis (pattern detection) TODO:
# DONE: Detect specific app execution and map to profile via target.prop

# ============== Global Vars ==============
SCRIPT_DIR="${0%/*}"
ADDON_DIR="${SCRIPT_DIR%/*}"
MODDIR="${ADDON_DIR%/*}"
TMPDIR="${TMPDIR:-$MODDIR/cache/tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || TMPDIR="/data/local/tmp"
mkdir -p "$TMPDIR" 2>/dev/null || true
export TMPDIR
LOG_DIR="$MODDIR/logs"
LOG_FILE="$LOG_DIR/daemon.log"
POLICY_DIR="$MODDIR/addon/policy"
POLICY_LOG="$LOG_DIR/policy.log"
STATE_FILE="$MODDIR/cache/daemon.state"
PID_FILE="$MODDIR/cache/daemon.pid"
LAST_EVENT_FILE="$MODDIR/cache/daemon.last"
LAST_EVENT_JSON="$MODDIR/cache/event.last.json"
ROUTER_DNI_FILE="$MODDIR/cache/router.dni"
ROUTER_LAST_FILE="$MODDIR/cache/router.last"
ROUTER_PAIRING_CACHE_FILE="$MODDIR/cache/router.pairing.json"
shared_errors="$MODDIR/addon/functions/debug/shared_errors.sh"
POLICY_COMMON_SH="$MODDIR/addon/functions/policy_common.sh"
EXECUTOR_SH="$MODDIR/addon/policy/executor.sh"
APP_EVENT_PROP="persist.kitsuneping.user_event"
APP_EVENT_DATA_PROP="persist.kitsuneping.user_event_data"
# Backward compatibility with older typoed property names.
APP_EVENT_PROP_LEGACY="persist.kitsunping.user_event"
APP_EVENT_DATA_PROP_LEGACY="persist.kitsunping.user_event_data"

# ============== PATH Setup ==============
# Add /data/local/tmp first for wget wrapper, then prepend module binary dirs.
export PATH="/data/local/tmp:$PATH"

# ============== Dev Hot-Reload ==============
# Usage:
#   mkdir -p /data/local/tmp/kitsunping_dev/<relative-path>
#   adb push <file> /data/local/tmp/kitsunping_dev/<relative-path>
#   touch /data/local/tmp/kitsunping_dev/.enabled
#   kill -USR1 $(cat /data/adb/modules/Kitsunping/cache/daemon.pid)
# Disable: rm /data/local/tmp/kitsunping_dev/.enabled
DEV_OVERRIDE_DIR="/data/local/tmp/kitsunping_dev"

_source_or_dev() {
    _sod_path="$1"
    _sod_rel="${_sod_path#$MODDIR/}"
    _sod_override="$DEV_OVERRIDE_DIR/$_sod_rel"
    if [ -f "$DEV_OVERRIDE_DIR/.enabled" ] && [ -f "$_sod_override" ]; then
        printf '[DEV][HOT] override: %s\n' "$_sod_rel" >> "$LOG_FILE" 2>/dev/null || true
        . "$_sod_override"
    elif [ -f "$_sod_path" ]; then
        . "$_sod_path"
    fi
}

_dev_reload_all() {
    printf '[DEV][HOT] reload triggered\n' >> "$LOG_FILE" 2>/dev/null || true
    _source_or_dev "$MODDIR/addon/functions/core.sh"
    _source_or_dev "$POLICY_COMMON_SH"
    _source_or_dev "$MODDIR/addon/functions/utils/env_detect.sh"
    _source_or_dev "$MODDIR/addon/functions/net_math.sh"
    _source_or_dev "$MODDIR/addon/daemon/iface_monitor.sh"
    _source_or_dev "$MODDIR/addon/functions/utils/Kitsutils.sh"
    _source_or_dev "$MODDIR/addon/functions/network_utils.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_utils.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_static.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_events.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_wifi_cycle.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_mobile_cycle.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_app_cycle.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_state_writer.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_transitions.sh"
    _source_or_dev "$MODDIR/lib/time_helpers.sh"
    _source_or_dev "$MODDIR/lib/json_helpers.sh"
    _source_or_dev "$MODDIR/lib/validation.sh"
    _source_or_dev "$MODDIR/lib/lock.sh"
    _source_or_dev "$MODDIR/network/wifi/cycle.sh"
    _source_or_dev "$MODDIR/network/mobile/cycle.sh"
    # Load app submodules explicitly before the orchestrator to avoid missing
    # symbols when cycle.sh cannot source one of its internal dependencies.
    _source_or_dev "$MODDIR/network/app/state_io.sh"
    _source_or_dev "$MODDIR/network/app/pairing_gate.sh"
    _source_or_dev "$MODDIR/network/app/target_engine.sh"
    _source_or_dev "$MODDIR/network/app/router_push.sh"
    _source_or_dev "$MODDIR/network/app/router_channel.sh"
    _source_or_dev "$MODDIR/network/app/cycle.sh"
    _source_or_dev "$MODDIR/core/runtime.sh"
    _source_or_dev "$shared_errors"
    if command -v network__app__event_cycle >/dev/null 2>&1; then
        printf '[DEV][HOT] symbol ok: network__app__event_cycle\n' >> "$LOG_FILE" 2>/dev/null || true
    else
        printf '[DEV][HOT] symbol missing: network__app__event_cycle\n' >> "$LOG_FILE" 2>/dev/null || true
    fi
    if command -v network__app__read_state_field >/dev/null 2>&1; then
        printf '[DEV][HOT] symbol ok: network__app__read_state_field\n' >> "$LOG_FILE" 2>/dev/null || true
    else
        printf '[DEV][HOT] symbol missing: network__app__read_state_field\n' >> "$LOG_FILE" 2>/dev/null || true
    fi
    command -v log_daemon >/dev/null 2>&1 && log_info() { log_daemon "$@"; }
    printf '[DEV][HOT] reload complete\n' >> "$LOG_FILE" 2>/dev/null || true
}

uint_or_default() {
    local raw="$1" def="$2"
    case "$raw" in
        ''|*[!0-9]*) printf '%s' "$def" ;;
        *) printf '%s' "$raw" ;;
    esac
}

# Commands and Binarys (to be detected)
IP_BIN=""
PING_BIN=""
RESET_PROP_BIN=""
JQ_BIN=""
BC_BIN=""

# =================== Events/
# External / trigger events
EV_WIFI_LEFT="WIFI_LEFT"            
EV_WIFI_JOINED="WIFI_JOINED"        
EV_IFACE_CHANGED="IFACE_CHANGED"      
EV_SIGNAL_DEGRADED="SIGNAL_DEGRADED"
EV_USER_REQUESTED_START="user_requested_start"
EV_USER_REQUESTED_CALIBRATE="user_requested_calibrate"
EV_USER_REQUESTED_RESTART="user_requested_restart"
EV_REQUEST_PROFILE="request_profile"
EV_REQUEST_CHANNEL_SCAN="request_channel_scan"
EV_REQUEST_CHANNEL_CHANGE="channel_change_request"
# For pairing router from app
EV_ROUTER_PAIRED="ROUTER_PAIRED"
EV_ROUTER_UNPAIRED="ROUTER_UNPAIRED"
EV_ROUTER_DNI_CHANGED="ROUTER_DNI_CHANGED"
EV_ROUTER_CAPS_DETECTED="ROUTER_CAPS_DETECTED"

# Configurable parameters
DAEMON_INTERVAL="${DAEMON_INTERVAL:-10}" # seconds (default polling interval)
LAST_TS_WIFI_LEFT=0
LAST_TS_WIFI_JOINED=0
LAST_TS_IFACE_CHANGED=0
INTERVAL_DEFAULT=10 # seconds
INTERVAL="$INTERVAL_DEFAULT"
SIGNAL_POLL_INTERVAL=5 # poll signal quality every N loops when on mobile
NET_PROBE_INTERVAL=3 # perform network probe every N loops when on Wi-Fi
interval_prop="$(getprop kitsunping.daemon.interval | tr -d '\r\n')"
signal_poll_prop="$(getprop kitsunping.daemon.signal_poll_interval | tr -d '\r\n')"
net_probe_prop="$(getprop kitsunping.daemon.net_probe_interval | tr -d '\r\n')"
interval_prop="$(uint_or_default "$interval_prop" "")"
signal_poll_prop="$(uint_or_default "$signal_poll_prop" "")"
net_probe_prop="$(uint_or_default "$net_probe_prop" "")"
CONF_ALPHA=$(getprop kitsunping.sigmoid.alpha)
CONF_BETA=$(getprop kitsunping.sigmoid.beta)
CONF_GAMMA=$(getprop kitsunping.sigmoid.gamma)
ROUTER_DEBUG_RAW=$(getprop kitsunping.router.debug)
KITSUNROUTER_ENABLE_RAW="$(getprop persist.kitsunrouter.enable)"
KITSUNROUTER_DEBUG_RAW="$(getprop persist.kitsunrouter.debug)"
ROUTER_EXPERIMENTAL_RAW=$(getprop persist.kitsunping.router.experimental)
ROUTER_EXPERIMENTAL_RAW_2=$(getprop kitsunping.router.experimental)
ROUTER_OPENWRT_RAW=$(getprop persist.kitsunping.router.openwrt_mode)
ROUTER_OPENWRT_RAW_2=$(getprop kitsunping.router.openwrt_mode)
ROUTER_CACHE_TTL_RAW=$(getprop persist.kitsunping.router.cache_ttl)
ROUTER_CACHE_TTL_RAW_2=$(getprop kitsunping.router.cache_ttl)
ROUTER_INFER_WIDTH_RAW=$(getprop persist.kitsunping.router.infer_width)
ROUTER_INFER_WIDTH_RAW_2=$(getprop kitsunping.router.infer_width)
ROUTER_INFER_WIDTH_2G_RAW=$(getprop persist.kitsunping.router.infer_width_2g)
ROUTER_INFER_WIDTH_2G_RAW_2=$(getprop kitsunping.router.infer_width_2g)

# Wifi serction
WIFI_SPEED_THRESHOLD="$(getprop kitsunping.wifi.speed_threshold | tr -d '\r\n')" # Mbps, above this is GOOD, below is LIMBO/BAD
WIFI_SPEED_THRESHOLD="$(uint_or_default "$WIFI_SPEED_THRESHOLD" "75")" # default to 75 Mbps if not set or invalid
# Event emission controls:
# - persist.kitsunping.emit_events: boolean (0/1, false/true) to enable/disable emitting events
# - persist.kitsunping.event_debounce_sec: debounce in seconds (integer > 0)
# Backward-compat: if emit_events is an integer > 1 and event_debounce_sec is unset, treat it as debounce seconds.
EMIT_EVENTS_RAW="$(getprop persist.kitsunping.emit_events)"
EVENT_DEBOUNCE_RAW="$(getprop persist.kitsunping.event_debounce_sec)"
EVENT_DEBOUNCE_RAW_2="$(getprop kitsunping.event.debounce_sec)"

EMIT_EVENTS_RAW="${EMIT_EVENTS_RAW:-1}" # default to enabled
EMIT_EVENTS=1
EVENT_DEBOUNCE_SEC=""

case "${EMIT_EVENTS_RAW:-}" in
    0|false|FALSE|no|NO|off|OFF) EMIT_EVENTS=0 ;;
    1|true|TRUE|yes|YES|on|ON|'') EMIT_EVENTS=1 ;;
    *[!0-9]* ) EMIT_EVENTS=1 ;; # unknown string -> keep enabled, but do not treat as number
    *)
        # numeric
        if [ "$EMIT_EVENTS_RAW" -gt 1 ] && [ -z "$EVENT_DEBOUNCE_RAW" ] && [ -z "$EVENT_DEBOUNCE_RAW_2" ]; then
            EVENT_DEBOUNCE_SEC="$EMIT_EVENTS_RAW"
        fi
        EMIT_EVENTS=1
        ;;
esac

if [ -z "$EVENT_DEBOUNCE_SEC" ]; then
    case "${EVENT_DEBOUNCE_RAW:-$EVENT_DEBOUNCE_RAW_2}" in
        ''|*[!0-9]* ) EVENT_DEBOUNCE_SEC=5 ;;
        *)
            if [ "${EVENT_DEBOUNCE_RAW:-$EVENT_DEBOUNCE_RAW_2}" -gt 0 ]; then
                EVENT_DEBOUNCE_SEC="${EVENT_DEBOUNCE_RAW:-$EVENT_DEBOUNCE_RAW_2}"
            else
                EVENT_DEBOUNCE_SEC=5
            fi
            ;;
    esac
fi

normalize_weight_value() {
    local raw="$1" def="$2"
    awk -v v="$raw" -v d="$def" 'BEGIN { if (v ~ /^-?[0-9]+([.][0-9]+)?$/) printf "%s", v; else printf "%s", d }'
}

LCL_ALPHA="$(normalize_weight_value "${CONF_ALPHA:-}" "0.4")"
LCL_BETA="$(normalize_weight_value "${CONF_BETA:-}" "0.3")"
LCL_GAMMA="$(normalize_weight_value "${CONF_GAMMA:-}" "0.3")"
LCL_DELTA=0.1

ROUTER_DEBUG="${ROUTER_DEBUG:-$ROUTER_DEBUG_RAW}"
case "${ROUTER_DEBUG:-}" in
    1|true|TRUE|yes|YES|on|ON) ROUTER_DEBUG=1 ;;
    *) ROUTER_DEBUG=0 ;;
esac

KITSUNROUTER_ENABLE="${KITSUNROUTER_ENABLE:-$KITSUNROUTER_ENABLE_RAW}"
case "${KITSUNROUTER_ENABLE:-}" in
    1|true|TRUE|yes|YES|on|ON) KITSUNROUTER_ENABLE=1 ;;
    *) KITSUNROUTER_ENABLE=0 ;;
esac

# Prefer persist.kitsunrouter.debug over legacy kitsunping.router.debug when present.
if [ -n "${KITSUNROUTER_DEBUG_RAW:-}" ]; then
    case "${KITSUNROUTER_DEBUG_RAW:-}" in
        1|true|TRUE|yes|YES|on|ON) ROUTER_DEBUG=1 ;;
        *) ROUTER_DEBUG=0 ;;
    esac
fi

ROUTER_EXPERIMENTAL="${ROUTER_EXPERIMENTAL:-${ROUTER_EXPERIMENTAL_RAW:-$ROUTER_EXPERIMENTAL_RAW_2}}"
case "${ROUTER_EXPERIMENTAL:-}" in
    1|true|TRUE|yes|YES|on|ON) ROUTER_EXPERIMENTAL=1 ;;
    *) ROUTER_EXPERIMENTAL=0 ;;
esac

ROUTER_OPENWRT_MODE="${ROUTER_OPENWRT_MODE:-${ROUTER_OPENWRT_RAW:-$ROUTER_OPENWRT_RAW_2}}"
case "${ROUTER_OPENWRT_MODE:-}" in
    1|true|TRUE|yes|YES|on|ON) ROUTER_OPENWRT_MODE=1 ;;
    *) ROUTER_OPENWRT_MODE=0 ;;
esac

ROUTER_CACHE_TTL="${ROUTER_CACHE_TTL:-${ROUTER_CACHE_TTL_RAW:-$ROUTER_CACHE_TTL_RAW_2}}"
case "${ROUTER_CACHE_TTL:-}" in
    ''|*[!0-9]* ) ROUTER_CACHE_TTL=3600 ;;
esac

ROUTER_INFER_WIDTH="${ROUTER_INFER_WIDTH:-${ROUTER_INFER_WIDTH_RAW:-$ROUTER_INFER_WIDTH_RAW_2}}"
case "${ROUTER_INFER_WIDTH:-}" in
    1|true|TRUE|yes|YES|on|ON) ROUTER_INFER_WIDTH=1 ;;
    *) ROUTER_INFER_WIDTH=0 ;;
esac

ROUTER_INFER_WIDTH_2G="${ROUTER_INFER_WIDTH_2G:-${ROUTER_INFER_WIDTH_2G_RAW:-$ROUTER_INFER_WIDTH_2G_RAW_2}}"
case "${ROUTER_INFER_WIDTH_2G:-}" in
    1|true|TRUE|yes|YES|on|ON) ROUTER_INFER_WIDTH_2G=1 ;;
    *) ROUTER_INFER_WIDTH_2G=0 ;;
esac

# Policy file ownership conventions:
# - `cache/policy.request`: written by the daemon to indicate the desired/profile chosen
# - `cache/policy.target`: written atomically by the executor when it accepts an event (target to apply)
# - `cache/policy.current`: written by the executor when a profile has been successfully applied
# This separation keeps the daemon as a decision/originator and the executor as the single-writer
# responsible for applying changes and persisting the target/current state.

# ===== Early init) =====
## Create necessary dirs and files when daemon starts
mkdir -p "$LOG_DIR" \
         "${STATE_FILE%/*}" \
         "${PID_FILE%/*}" \
         "${LAST_EVENT_FILE%/*}" 2>/dev/null
## Clear log files on start
: > "$LOG_FILE" 2>/dev/null
: > "$POLICY_LOG" 2>/dev/null

## Redirect stdout/stderr to log file
exec >> "$LOG_FILE" 2>&1

# ============== Helpers Fallback ==============
## Functions for logging (if Kitsutils is not found)
log_info() { printf '[DAEMON][INFO] %s\n' "$*" >&2; }
log_debug() { printf '[DAEMON][DEBUG] %s\n' "$*" >&2; }
log_warning() { printf '[DAEMON][WARN] %s\n' "$*" >&2; }
log_error() { printf '[DAEMON][ERROR] %s\n' "$*" >&2; }
log_policy() { printf '[POLICY] %s\n' "$*" >&2; }
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Source all modular components (dev hot-reload aware)
_dev_reload_all

# Prepend bundled binary directories once helpers are loaded.
if command -v export_kitsunping_bin_path >/dev/null 2>&1; then
    export_kitsunping_bin_path
fi

# ============= Signal Handling ==============
# Handle TERM/INT signals to cleanup pidfile
trap 'log_info "daemon stopped"; rm -f "$PID_FILE" 2>/dev/null; exit 0' TERM INT
trap '_dev_reload_all; log_info "hot-reload complete (USR1)"' USR1

# ============== Singleton Enforcement ==============
## Ensure only one instance of the daemon is running 
## On TERM or INT, log stop and remove pidfile
## Usage: ensure_singleton
## Ensure singleton instance of daemon 
ensure_singleton() {
    log_info "ensuring singleton daemon instance"

    ## Create pidfile dir if not exists
    if [ ! -d "${PID_FILE%/*}" ]; then
        mkdir -p "${PID_FILE%/*}" 2>/dev/null || log_warning "could not create pidfile dir"
    fi

    ## Check for existing pidfile
    if [ -f "$PID_FILE" ]; then
        ## Check if process is running
        local old_pid 
        ## Read old pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null)
        # If pidfile already contains our own PID (e.g. pre-created by caller), continue.
        if [ -n "$old_pid" ] && [ "$old_pid" = "$$" ]; then
            log_debug "pidfile already set to our PID ($old_pid); continuing"
            else
            ## Check if process with old_pid is running
            if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
                log_warning "daemon already running with PID $old_pid; exiting for no kill/duplicate main process"
                exit 0
            fi
        fi
        ## If not running, cleanup stale pidfile
        rm -f "$PID_FILE" 2>/dev/null
    fi
    ## Write current pid to pidfile
    echo "$$" > "$PID_FILE" 2>/dev/null || log_warning "could not write pidfile"
}

# ============== Command Checks ==============
## Check for required commands and set global vars
## Usage: check_and_detect_commands
## Sets global vars: IP_BIN, PING_BIN, RESET_PROP_BIN
check_and_detect_commands() {
    # Only require what is truly mandatory for daemon logic.
    # Do NOT require 'ip' in PATH because we can use the bundled addon ip.
    check_core_commands awk || { log_error "Missing core commands"; exit 1; }
    detect_ip_binary || { log_error "ip binary not found"; exit 1; }
    detect_ping_binary "$MODDIR/addon/ping" || log_warning "ping binary not found; skipping ping-based checks"

    if command_exists resetprop; then
        RESET_PROP_BIN=$(command -v resetprop 2>/dev/null)
        # log_debug "resetprop resolved to: $RESET_PROP_BIN"
    else
        log_warning "resetprop not found; executor may not apply props"
    fi

    detect_jq_binary
    detect_bc_binary
}

preflight_check_caps() {
    # Check once at startup which optional cmd wifi subcommands are available.
    # Results cached in cache/preflight.state so profile_runner.sh can gate tweaks.
    local caps_file cmd_wifi_low_latency=0 cmd_wifi_hi_perf=0
    caps_file="$MODDIR/cache/preflight.state"
    mkdir -p "$MODDIR/cache" 2>/dev/null || true

    if command -v cmd >/dev/null 2>&1; then
        _caps_out="$(cmd wifi 2>&1)"
        printf '%s' "$_caps_out" | grep -q 'force-low-latency-mode' && cmd_wifi_low_latency=1
        printf '%s' "$_caps_out" | grep -q 'force-hi-perf-mode'      && cmd_wifi_hi_perf=1
    fi

    printf 'cmd_wifi_low_latency=%s\ncmd_wifi_hi_perf=%s\n' \
        "$cmd_wifi_low_latency" "$cmd_wifi_hi_perf" > "$caps_file" 2>/dev/null || true
    log_info "preflight: cmd_wifi_low_latency=$cmd_wifi_low_latency cmd_wifi_hi_perf=$cmd_wifi_hi_perf"
}

apply_boot_custom_profile_once() {
    local boot_profile_raw boot_profile policy_request_file policy_request_priority_file

    boot_profile_raw="$(getprop persist.kitsunping.boot_profile | tr -d '\r\n')"
    boot_profile="$(printf '%s' "$boot_profile_raw" | tr '[:upper:]' '[:lower:]')"

    case "$boot_profile" in
        stable|speed|gaming|benchmark_gaming|benchmark_speed) ;;
        benchmark|benchmarks) boot_profile="benchmark_gaming" ;;
        none|"") return 0 ;;
        *)
            log_warning "boot profile inválido: ${boot_profile_raw:-empty}"
            return 0
            ;;
    esac

    policy_request_file="$MODDIR/cache/policy.request"
    policy_request_priority_file="$MODDIR/cache/policy.request.priority"

    printf '%s' "$boot_profile" > "$policy_request_file" 2>/dev/null || true
    printf '%s' "high" > "$policy_request_priority_file" 2>/dev/null || true

    # L2.5: record boot profile timestamp so the Wi-Fi transport cycle respects
    # WIFI_SWITCH_MIN_HOLD_SEC and does not immediately override the boot profile.
    _boot_ts_file="$MODDIR/cache/policy.boot.ts"
    printf '%s' "$(date +%s 2>/dev/null || echo 0)" > "$_boot_ts_file" 2>/dev/null || true

    if command -v emit_event >/dev/null 2>&1; then
        emit_event "$EV_REQUEST_PROFILE" "source=boot_custom_profile to=$boot_profile from=boot"
    fi
    log_info "boot custom profile aplicado: $boot_profile"
}

# Initial delay to allow system to stabilize
sleep 5
check_and_detect_commands
preflight_check_caps
ensure_singleton
apply_boot_custom_profile_once

# Fallback to env var if prop not set
[ -z "$interval_prop" ] && interval_prop="$DAEMON_INTERVAL"

# Validate interval (must be positive integer)
# is interval_prop == 10, and > 0  then INTERVAL=10
# otherwise keep default
case "$interval_prop" in
    ''|*[!0-9]*) ;;
    *)
        if [ "$interval_prop" -gt 0 ]; then
            INTERVAL="$interval_prop"
        fi
        ;;
esac

case "$signal_poll_prop" in
    ''|*[!0-9]*) ;;
    *)
        if [ "$signal_poll_prop" -gt 0 ]; then
            SIGNAL_POLL_INTERVAL="$signal_poll_prop"
        fi
        ;;
esac

case "$net_probe_prop" in
    ''|*[!0-9]*) ;;
    *)
        if [ "$net_probe_prop" -gt 0 ]; then
            NET_PROBE_INTERVAL="$net_probe_prop"
        fi
        ;;
esac

# Adjust minimum debounce based on interval (prevents spam during micro-outages)
## Ensure debounce >= polling interval (at most one event per loop)
## if interval > EVENT_DEBOUNCE_SEC then EVENT_DEBOUNCE_SEC = interval
case "$EVENT_DEBOUNCE_SEC" in
    ''|*[!0-9]* ) EVENT_DEBOUNCE_SEC=5 ;; 
esac
if [ "$INTERVAL" -gt "$EVENT_DEBOUNCE_SEC" ]; then
    EVENT_DEBOUNCE_SEC="$INTERVAL"
fi


# Resolve Wi-Fi iface independently from current default route.
# Using get_current_iface() here can point to rmnet* when mobile is active,
# which swaps wifi/mobile fields in daemon.state.
WIFI_IFACE="none"
wifi_boot_readout="$(get_wifi_status)"
for kv in $wifi_boot_readout; do
    case "$kv" in
        iface=*) WIFI_IFACE="${kv#iface=}" ;;
    esac
done
if [ -z "$WIFI_IFACE" ]; then
    WIFI_IFACE="none"
fi

last_iface=""
last_wifi_state="unknown"
last_wifi_link=""
last_wifi_ip=0
last_wifi_egress=0
last_wifi_score=0
last_mobile_link=""
last_mobile_ip=0
last_mobile_egress=0
last_mobile_score=0

log_info "daemon start (DAEMON: monitor iface and wifi->mobile transitions)"
log_info "kitsunrouter.enable=$KITSUNROUTER_ENABLE kitsunrouter.debug=$ROUTER_DEBUG"

loop_count=0
signal_loop_count=0
wifi_probe_loop_count=0
wifi_probe_fail_streak=0
wifi_probe_ok=1
last_router_paired="$(get_router_paired_flag)"

if command -v core_daemon_main_loop >/dev/null 2>&1; then
    core_daemon_main_loop
else
    while true; do
        daemon_run_app_event_cycle
        daemon_run_pairing_sync_cycle

        current_iface="$(get_current_iface)"
        [ -z "$current_iface" ] && current_iface="none"

        daemon_run_wifi_cycle
        daemon_run_mobile_cycle
        daemon_run_wifi_transport_cycle
        daemon_run_mobile_transport_cycle
        daemon_run_target_profile_cycle
        daemon_run_router_status_push_cycle

        daemon_run_transition_cycle
        daemon_run_tick_cycle

        daemon_write_state_file
        sleep "$INTERVAL"
    done
fi
