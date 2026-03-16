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
LINK_CONTEXT_FILE="$MODDIR/cache/link_context.state"
ROUTER_DNI_FILE="$MODDIR/cache/router.dni"
ROUTER_LAST_FILE="$MODDIR/cache/router.last"
ROUTER_PAIRING_CACHE_FILE="$MODDIR/cache/router.pairing.json"
shared_errors="$MODDIR/addon/functions/debug/shared_errors.sh"
POLICY_COMMON_SH="$MODDIR/addon/functions/policy_common.sh"
EXECUTOR_CANONICAL_SH="$MODDIR/policy/executor/executor.sh"
EXECUTOR_COMPAT_SH="$MODDIR/addon/policy/executor.sh"
if [ -f "$EXECUTOR_CANONICAL_SH" ]; then
    EXECUTOR_SH="$EXECUTOR_CANONICAL_SH"
else
    # Keep legacy wrapper as compatibility fallback for old package layouts.
    EXECUTOR_SH="$EXECUTOR_COMPAT_SH"
fi
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
    _source_or_dev "$MODDIR/addon/functions/daemon_bootstrap.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_config.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_state_writer.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_adaptive_sampling.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_transitions.sh"
    _source_or_dev "$MODDIR/lib/time_helpers.sh"
    _source_or_dev "$MODDIR/lib/json_helpers.sh"
    _source_or_dev "$MODDIR/lib/validation.sh"
    _source_or_dev "$MODDIR/lib/lock.sh"
    _source_or_dev "$MODDIR/addon/functions/daemon_failsafe.sh"
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

# Configurable runtime parameters are loaded by daemon_config.sh.

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

if command -v daemon_load_runtime_config >/dev/null 2>&1; then
    daemon_load_runtime_config
else
    DAEMON_INTERVAL="${DAEMON_INTERVAL:-10}"
    LAST_TS_WIFI_LEFT=0
    LAST_TS_WIFI_JOINED=0
    LAST_TS_IFACE_CHANGED=0
    INTERVAL_DEFAULT=10
    INTERVAL="$INTERVAL_DEFAULT"
    SIGNAL_POLL_INTERVAL=5
    NET_PROBE_INTERVAL=3
    EVENT_DEBOUNCE_SEC=5
    ROUTER_DEBUG=0
    KITSUNROUTER_ENABLE=0
    ROUTER_EXPERIMENTAL=0
    ROUTER_OPENWRT_MODE=0
    ROUTER_CACHE_TTL=3600
    ROUTER_INFER_WIDTH=0
    ROUTER_INFER_WIDTH_2G=0
    WIFI_SPEED_THRESHOLD=75
    DAEMON_CONFIG_INTERVAL_PROP=""
    DAEMON_CONFIG_SIGNAL_POLL_PROP=""
    DAEMON_CONFIG_NET_PROBE_PROP=""
fi

# Restore persistent link context counters/state before entering runtime loops.
if command -v daemon_link_context_load >/dev/null 2>&1; then
    daemon_link_context_load
fi

# Initialize failsafe: detect state corruption and enable safe_mode if needed
if command -v daemon_init_safe_mode >/dev/null 2>&1; then
    daemon_init_safe_mode
    daemon_write_rescue_instructions
    daemon_safe_mode_log_status
fi

# Prepend bundled binary directories once helpers are loaded.
if command -v export_kitsunping_bin_path >/dev/null 2>&1; then
    export_kitsunping_bin_path
fi

# ============= Signal Handling ==============
# Handle TERM/INT signals to cleanup pidfile
trap 'log_info "daemon stopped"; rm -f "$PID_FILE" 2>/dev/null; exit 0' TERM INT
trap '_dev_reload_all; log_info "hot-reload complete (USR1)"' USR1

# Bootstrap helpers and startup sequence are loaded by daemon_bootstrap.sh.

if command -v daemon_run_bootstrap_init >/dev/null 2>&1; then
    daemon_run_bootstrap_init
else
    sleep 5
fi

interval_prop="$DAEMON_CONFIG_INTERVAL_PROP"
signal_poll_prop="$DAEMON_CONFIG_SIGNAL_POLL_PROP"
net_probe_prop="$DAEMON_CONFIG_NET_PROBE_PROP"

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

if command -v daemon_adaptive_sampling_init >/dev/null 2>&1; then
    daemon_adaptive_sampling_init
else
    ADAPTIVE_SAMPLING_ENABLE=0
    ADAPTIVE_BASE_SEC=30
    ADAPTIVE_DEGRADED_SEC=8
    ADAPTIVE_BAD_STREAK=2
    ADAPTIVE_GOOD_STREAK=3
    DAEMON_SAMPLE_MODE="fixed"
    DAEMON_SAMPLE_REASON="module_missing"
    DAEMON_SAMPLE_INTERVAL_SEC="$INTERVAL"
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

# Preserve wifi transition continuity across daemon restarts.
case "${link_last_wifi_state:-}" in
    connected|disconnected|unknown)
        last_wifi_state="$link_last_wifi_state"
        ;;
esac

log_info "daemon start (DAEMON: monitor iface and wifi->mobile transitions)"
log_info "kitsunrouter.enable=$KITSUNROUTER_ENABLE kitsunrouter.debug=$ROUTER_DEBUG"
log_info "adaptive_sampling=$ADAPTIVE_SAMPLING_ENABLE base=${ADAPTIVE_BASE_SEC}s degraded=${ADAPTIVE_DEGRADED_SEC}s streak_bad=$ADAPTIVE_BAD_STREAK streak_good=$ADAPTIVE_GOOD_STREAK"

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
        # Check if rescue was requested and perform recovery before cycles
        if command -v daemon_check_rescue_request >/dev/null 2>&1 && daemon_check_rescue_request; then
            if command -v daemon_perform_rescue >/dev/null 2>&1; then
                daemon_perform_rescue
            fi
        fi

        # Skip non-critical cycles if in safe_mode (app and policy triggers)
        if ! daemon_safe_mode_skip_cycle app; then
            daemon_run_app_event_cycle
        fi
        
        daemon_run_pairing_sync_cycle

        current_iface="$(get_current_iface)"
        [ -z "$current_iface" ] && current_iface="none"

        daemon_run_wifi_cycle
        daemon_run_mobile_cycle
        daemon_run_wifi_transport_cycle
        daemon_run_mobile_transport_cycle
        
        if ! daemon_safe_mode_skip_cycle policy_check; then
            daemon_run_target_profile_cycle
        fi
        
        daemon_run_router_status_push_cycle

        daemon_run_transition_cycle
        daemon_run_tick_cycle

        daemon_write_state_file
        
        if command -v daemon_sampling_pick_interval >/dev/null 2>&1; then
            interval_candidate="$(daemon_sampling_pick_interval "$INTERVAL")"
        else
            interval_candidate="$INTERVAL"
        fi

        # Adjust sleep interval in safe_mode (degrade polling frequency)
        INTERVAL_ADJUSTED="$(daemon_safe_mode_adjust_sleep "$interval_candidate")"
        if [ "$INTERVAL_ADJUSTED" != "${DAEMON_SAMPLE_LAST_LOGGED_INTERVAL:-}" ] || [ "$DAEMON_SAMPLE_MODE" != "${DAEMON_SAMPLE_LAST_LOGGED_MODE:-}" ]; then
            log_info "sampling mode=$DAEMON_SAMPLE_MODE interval=${INTERVAL_ADJUSTED}s reason=${DAEMON_SAMPLE_REASON:-na}"
            DAEMON_SAMPLE_LAST_LOGGED_INTERVAL="$INTERVAL_ADJUSTED"
            DAEMON_SAMPLE_LAST_LOGGED_MODE="$DAEMON_SAMPLE_MODE"
        fi
        sleep "$INTERVAL_ADJUSTED"
    done
fi
