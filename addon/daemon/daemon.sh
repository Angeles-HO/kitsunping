#!/system/bin/sh
# Minimal daemon: log interface and Wi-Fi/mobile transitions
# ============== TODO Sec ==============
# - TODO: agregar métricas de ping y latencia para evaluar calidad de conexión
# - TODO: agregar soporte para múltiples interfaces Wi-Fi (si el dispositivo lo soporta)
# - TODO: agregar soporte para múltiples interfaces móviles (si el dispositivo lo soporta)
# - TODO: Modularizar más el código (separar funciones en archivos separados)
# - TODO: agregar soporte para IPv6 (actualmente solo IPv4)
# - TODO: agregar soporte para notificaciones a la aplicación (broadcast intents)
# - TODO: agregar soporte para reglas de política personalizadas (scripts externos)
# - TODO: agregar soporte para métricas históricas (logs rotativos, base de datos ligera)
# - TODO: agregar soporte para análisis de tendencias (detección de patrones)
# - TODO: Posibilidad de detectar la ejecucion de una aplicación especifica y ajustar el comportamiento de la red en consecuencia: com.example.app="<prfile_name>" 

# ============== Global Vars ==============
SCRIPT_DIR="${0%/*}"
ADDON_DIR="${SCRIPT_DIR%/daemon}"
MODDIR="${ADDON_DIR%/addon}"
LOG_DIR="$MODDIR/logs"
LOG_FILE="$LOG_DIR/daemon.log"
POLICY_DIR="$MODDIR/addon/policy"
POLICY_LOG="$LOG_DIR/policy.log"
GENERAL_DAEMON_LOG="$LOG_DIR/general_daemon.log"
STATE_FILE="$MODDIR/cache/daemon.state"
PID_FILE="$MODDIR/cache/daemon.pid"
LAST_EVENT_FILE="$MODDIR/cache/daemon.last"
EVENTS_DIR="$MODDIR/cache/events"
LAST_EVENT_JSON="$MODDIR/cache/event.last.json"
shared_errors="$MODDIR/addon/functions/debug/shared_errors.sh"
EXECUTOR_SH="$MODDIR/addon/policy/executor.sh"
DEBUG_MODE="$(getprop persist.kitsunping.debug)"
DEBUG_MODE="${DEBUG_MODE:-0}"
# Commands (to be detected)
IP_BIN=""
PING_BIN=""
RESET_PROP_BIN=""
JQ_BIN=""
BC_BIN=""

# Validate EVENT_DEBOUNCE_SEC
EVENT_DEBOUNCE_SEC="${EVENT_DEBOUNCE_SEC:-5}"

# =================== Events/
# External / trigger events
EV_WIFI_LEFT="WIFI_LEFT"            
EV_WIFI_JOINED="WIFI_JOINED"        
EV_IFACE_CHANGED="IFACE_CHANGED"      
EV_SIGNAL_DEGRADED="SIGNAL_DEGRADED"
EV_TIMER_WAKE="TIMER_WAKE"
EV_WAKE="WAKE"

# Internal / state events
ST_SLEEPING="SLEEPING"
ST_AWAKE="AWAKE"
ST_EVALUATING="EVALUATING"
ST_CALIBRATING="CALIBRATING"
ST_SUSPENDED="SUSPENDED"

# Network quality states
NET_NONE="NONE"
NET_GOOD="GOOD"
NET_LIMBO="LIMBO"
NET_BAD="BAD"

# Configurable parameters
EVENT_DEBOUNCE_SEC=3 # seconds (debounce time for events)
DAEMON_INTERVAL="${DAEMON_INTERVAL:-10}" # seconds (default polling interval)
LAST_TS_WIFI_LEFT=0
LAST_TS_WIFI_JOINED=0
LAST_TS_IFACE_CHANGED=0
INTERVAL_DEFAULT=10 # seconds
INTERVAL="$INTERVAL_DEFAULT"
SIGNAL_POLL_INTERVAL=5 # poll signal quality every N loops when on mobile
interval_prop="$(getprop kitsunping.daemon.interval)"
CONF_ALPHA=$(getprop kitsunping.sigmoid.alpha)
CONF_BETA=$(getprop kitsunping.sigmoid.beta)
CONF_GAMMA=$(getprop kitsunping.sigmoid.gamma)
LCL_ALPHA=${CONF_ALPHA:-0.4}
LCL_BETA=${CONF_BETA:-0.3}
LCL_GAMMA=${CONF_GAMMA:-0.3}
LCL_DELTA=0.1

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
         "${LAST_EVENT_FILE%/*}" \
         "$EVENTS_DIR" 2>/dev/null
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

# Lightweight tracking log that survives restarts.
# - Always logs INFO/WARN/ERROR events.
# - Logs DEBUG only when DEBUG_MODE=1.
_general_ts() {
    # Prefer ISO timestamp if available
    date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$(now_epoch)"
}

trace_general() {
    # Usage: trace_general LEVEL MESSAGE...
    # LEVEL: INFO|WARN|ERROR|DEBUG|STATE|EVENT
    local level="$1"; shift
    local msg="$*"

    [ -z "$level" ] && level="INFO"
    [ -z "$msg" ] && msg="(empty)"

    if [ "$level" = "DEBUG" ] && [ "${DEBUG_MODE:-0}" != "1" ]; then
        return 0
    fi

    printf '[%s][%s][pid=%s] %s\n' "$(_general_ts)" "$level" "$$" "$msg" >> "$GENERAL_DAEMON_LOG" 2>/dev/null || true
}


# Source modular components (if installed)
if [ -f "$MODDIR/addon/functions/core.sh" ]; then
    . "$MODDIR/addon/functions/core.sh"
fi
if [ -f "$MODDIR/addon/functions/utils/env_detect.sh" ]; then
    . "$MODDIR/addon/functions/utils/env_detect.sh"
fi
if [ -f "$MODDIR/addon/functions/net_math.sh" ]; then
    . "$MODDIR/addon/functions/net_math.sh"
fi
if [ -f "$MODDIR/addon/daemon/iface_monitor.sh" ]; then
    . "$MODDIR/addon/daemon/iface_monitor.sh"
fi

# Source Kitsutils for shared utilities
if [ -f "$MODDIR/addon/functions/utils/Kitsutils.sh" ]; then
    . "$MODDIR/addon/functions/utils/Kitsutils.sh"
fi

# Ensure network_utils.sh is sourced for shared functions
if [ -f "$MODDIR/addon/functions/network_utils.sh" ]; then
    . "$MODDIR/addon/functions/network_utils.sh"
fi

if [ -f "$shared_errors" ]; then 
    . "$shared_errors"
    command -v log_daemon >/dev/null 2>&1 && log_info() { log_daemon "$@";  } 
else
    log_warning "Shared_errors no encontrado: $shared_errors (usando logger interno)"
fi


# ============= Event Writing And Regex ==============
## JSON escape helper
## Usage: json_escape "string to escape" 
## e.g., json_escape 'He said "Hello\nWorld"' -> He said \"Hello\nWorld\"   
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}

## Atomic write helper, (to avoid partial writes)
## Usage: atomic_write target_file < data_to_write 
## (on success, moves temp file to target; on failure, removes temp file)
atomic_write() {
    local target="$1" tmp

    ## Create temp file in same dir as target (same filesystem → atomic mv)
    tmp=$(mktemp "${target}.XXXXXX") || \
        tmp="${target}.$$.$(date +%s).tmp"

    if cat - > "$tmp" 2>/dev/null; then
        mv "$tmp" "$target" 2>/dev/null || rm -f "$tmp"
    else
        rm -f "$tmp"
        return 1
    fi
}

## Write event to JSON file
## Usage: write_event_json $1 = "event_name" $2 = "timestamp" $3 = "details"
## e.g., write_event_json "WIFI_LEFT" 1620000000 "iface=wlan0 link=DOWN ip=0 egress=0 reason=link_down"
write_event_json() {
    local name="$1" ts="$2" details jsonfile="$LAST_EVENT_JSON"
    local details
    details="$(json_escape "$3")"

    cat <<EOF | atomic_write "$jsonfile"
{"event":"$name","ts":$ts,"details":"$details","iface":"$current_iface","wifi_state":"$wifi_state","wifi_score":$wifi_score}
EOF
}

# ============= Signal Handling ==============
# Handle TERM/INT signals to cleanup pidfile
trap 'trace_general INFO "daemon stopped"; log_info "daemon stopped"; rm -f "$PID_FILE" 2>/dev/null; exit 0' TERM INT

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
        ## Check if process with old_pid is running
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            log_warning "daemon already running with PID $old_pid; exiting for no kill/duplicate main process"
            exit 0
        fi

        ## If not running, cleanup stale pidfile
        rm -f "$PID_FILE" 2>/dev/null
    fi
    ## Write current pid to pidfile
    echo "$$" > "$PID_FILE" 2>/dev/null || log_warning "could not write pidfile"
}

## Get current epoch time in seconds
## Usage: now_epoch 
## Results in stdout: epoch seconds (e.g., 1620000000)
now_epoch() {
    # Try toybox/GNU date, fallback to busybox, then POSIX awk systime
    date +%s 2>/dev/null 2>/dev/null || awk 'BEGIN{print systime()}' 2>/dev/null || echo 0 
}

# ============== Command Checks ==============
## Check for required commands and set global vars
## Usage: check_and_detect_commands
## Sets global vars: IP_BIN, PING_BIN, RESET_PROP_BIN
check_and_detect_commands() {
    check_core_commands ip resetprop awk || { log_error "Missing core commands"; exit 1; }
    detect_ip_binary || { log_error "ip binary not found"; exit 1; }
    detect_ping_binary "$MODDIR/addon/ping" || log_warning "ping binary not found; skipping ping-based checks"

    if command_exists resetprop; then
        RESET_PROP_BIN=$(command -v resetprop 2>/dev/null)
        # log_debug "resetprop resolved to: $RESET_PROP_BIN"
    fi

    detect_jq_binary
    detect_bc_binary
}

# ============== Main Functions ==============
## Determine if event should be emitted based on debounce time
## Usage: should_emit_event "event_name"
## Returns 0 (true) if event should be emitted, 1 (false) otherwise
should_emit_event() {
    local name="$1" now last_var last_ts diff
    now=$(now_epoch)

    # Validate event name
    case "$name" in
        WIFI_*|IFACE_*|SIGNAL_*|TIMER_*|WAKE|PROFILE_*)
            ;;
        *)
            log_error "Invalid event name: $name"
            trace_general WARN "invalid_event_name name=$name"
            return 1
            ;;
    esac

    # If no name provided, do not emit
    [ -z "$name" ] && return 1

    # If now is 0 (error), log and do not emit
    [ "$now" -eq 0 ] && log_error "now_epoch failed" && return 1

    # Check last emitted timestamp
    last_var="LAST_TS_${name}"
    eval "last_ts=\${${last_var}:-0}"

    # Calculate time difference since last event
    diff=$((now - last_ts))

    # If difference is less than debounce, do not emit
    if [ "$diff" -lt "$EVENT_DEBOUNCE_SEC" ]; then
        return 1
    fi

    # Update last emitted timestamp
    eval "${last_var}=$now"
    return 0
}
## NOTE: event names must be trusted constants (used in eval)

## Emit event if debounce allows
## Usage: emit_event "event_name" "details"
## e.g., emit_event "WIFI_LEFT" "iface=wlan0 link=DOWN ip=0 egress=0 reason=link_down"
emit_event() {
    local name="$1" details="$2" now
    now=$(now_epoch)

    [ -z "$name" ] && log_warning "emit_event called with empty name" && return 1

    if should_emit_event "$name"; then
        EVENT_SEQ=$((EVENT_SEQ + 1))
        export EVENT_SEQ

        log_info "EVENT #$EVENT_SEQ $name ts=$now $details"
        trace_general EVENT "#$EVENT_SEQ name=$name ts=$now details=$details"
        write_event_json "$name" "$now" "$details"

        if ! printf '%s %s %s\n' "$name" "$now" "$details" | atomic_write "$LAST_EVENT_FILE"; then
            log_error "Failed to write LAST_EVENT_FILE"
        fi

        if [ -x "$EXECUTOR_SH" ]; then
            EVENT_NAME="$name" \
            EVENT_TS="$now" \
            EVENT_DETAILS="$details" \
            LOG_DIR="$LOG_DIR" \
            POLICY_LOG="$POLICY_LOG" \
            "$EXECUTOR_SH" >> "$POLICY_LOG" 2>&1 &
        else
            log_error "EXECUTOR not executable: $EXECUTOR_SH"
        fi
        # TODO: send broadcast to APK with action com.kitsunping.ACTION_UPDATE including 'event' and 'ts'
    else
        log_debug "EVENT suppressed by debounce: $name"
        trace_general DEBUG "event_suppressed name=$name"
    fi
}

# Initial delay to allow system to stabilize
sleep 5
check_and_detect_commands
ensure_singleton

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

# Adjust minimum debounce based on interval (prevents spam during micro-outages)
## Ensure debounce >= polling interval (at most one event per loop)
## if interval > EVENT_DEBOUNCE_SEC then EVENT_DEBOUNCE_SEC = interval
if [ "$INTERVAL" -gt "$EVENT_DEBOUNCE_SEC" ]; then
    EVENT_DEBOUNCE_SEC="$INTERVAL"
fi


get_score() {
    local link_state="$1" has_ip="$2" egress="$3" score=0
    [ "$link_state" = "UP" ] && score=$((score + 20))
    [ "$has_ip" -eq 1 ] && score=$((score + 30))
    [ "$egress" -eq 1 ] && score=$((score + 50))
    [ "$link_state" = "UP" ] && [ "$has_ip" -eq 0 ] && score=$((score - 10))
    echo "$score"
}

get_reason_from_score() {
    local score="$1"
    if [ "$score" -ge 80 ]; then
        echo "good"
    elif [ "$score" -ge 40 ]; then
        echo "degraded"
    else
        echo "bad"
    fi
}

WIFI_IFACE="$(getprop wifi.interface 2>/dev/null)"
[ -z "$WIFI_IFACE" ] && WIFI_IFACE="wlan0" && echo "WIFI_IFACE not found; defaulting to wlan0"

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
trace_general INFO "daemon start" 

loop_count=0
signal_loop_count=0

while true; do
    current_iface="$(get_default_iface)"
    [ -z "$current_iface" ] && current_iface="none"

    wifi_readout="$(get_wifi_status "$WIFI_IFACE")"
    wifi_link="DOWN"; wifi_ip=0; wifi_egress=0; wifi_reason="link_down"
    for kv in $wifi_readout; do
        case "$kv" in
            link=*) wifi_link="${kv#link=}" ;;
            ip=*) wifi_ip="${kv#ip=}" ;;
            egress=*) wifi_egress="${kv#egress=}" ;;
            reason=*) wifi_reason="${kv#reason=}" ;;
        esac
    done
    wifi_state="disconnected"
    [ "$wifi_link" = "UP" ] && [ "$wifi_ip" -eq 1 ] && wifi_state="connected"
    if [ "$wifi_link" != "$last_wifi_link" ] || [ "$wifi_ip" -ne "$last_wifi_ip" ] || [ "$wifi_egress" -ne "$last_wifi_egress" ]; then
        wifi_score="$(get_score "$wifi_link" "$wifi_ip" "$wifi_egress")"
        last_wifi_link="$wifi_link"
        last_wifi_ip="$wifi_ip"
        last_wifi_egress="$wifi_egress"
        last_wifi_score="$wifi_score"
    else
        wifi_score="$last_wifi_score"
    fi
    wifi_reason="$(get_reason_from_score "$wifi_score")"

    mobile_iface="none"
    [ "$current_iface" != "$WIFI_IFACE" ] && [ "$current_iface" != "none" ] && mobile_iface="$current_iface"
    mobile_readout="$(get_mobile_status "$mobile_iface")"
    mobile_link="DOWN"; mobile_ip=0; mobile_egress=0; mobile_reason="link_down"
    for kv in $mobile_readout; do
        case "$kv" in
            iface=*) mobile_iface="${kv#iface=}" ;;
            link=*) mobile_link="${kv#link=}" ;;
            ip=*) mobile_ip="${kv#ip=}" ;;
            egress=*) mobile_egress="${kv#egress=}" ;;
            reason=*) mobile_reason="${kv#reason=}" ;;
        esac
    done
    if [ "$mobile_link" != "$last_mobile_link" ] || [ "$mobile_ip" -ne "$last_mobile_ip" ] || [ "$mobile_egress" -ne "$last_mobile_egress" ]; then
        mobile_score="$(get_score "$mobile_link" "$mobile_ip" "$mobile_egress")"
        last_mobile_link="$mobile_link"
        last_mobile_ip="$mobile_ip"
        last_mobile_egress="$mobile_egress"
        last_mobile_score="$mobile_score"
    else
        mobile_score="$last_mobile_score"
    fi
    mobile_reason="$(get_reason_from_score "$mobile_score")"

    transport="none"
    if [ "$wifi_egress" -eq 1 ]; then
        transport="wifi"
    elif [ "$mobile_egress" -eq 1 ]; then
        transport="mobile"
    fi

    # General tracking line (STATE)
    trace_general STATE "iface=$current_iface transport=$transport wifi.state=$wifi_state wifi.score=$wifi_score mobile.iface=$mobile_iface mobile.score=$mobile_score"

    # Poll radio signal only when mobile is the active/egress path; throttle by SIGNAL_POLL_INTERVAL
    if [ "$transport" = "mobile" ]; then
        signal_loop_count=$((signal_loop_count + 1))
        if [ "$signal_loop_count" -ge "$SIGNAL_POLL_INTERVAL" ]; then
            signal_loop_count=0
            signal_info=$(get_signal_quality)
            echo "$signal_info" | atomic_write "$MODDIR/cache/signal_quality.json"

            # Extract quality_score, rsrp and sinr
            signal_score=""
            rsrp=""
            sinr=""
            if [ -n "$JQ_BIN" ]; then
                signal_score=$(echo "$signal_info" | "$JQ_BIN" -r 'try .quality_score // empty' 2>/dev/null)
                rsrp=$(echo "$signal_info" | "$JQ_BIN" -r 'try .rsrp_dbm // empty' 2>/dev/null)
                sinr=$(echo "$signal_info" | "$JQ_BIN" -r 'try .sinr_db // empty' 2>/dev/null)
            else
                signal_score=$(echo "$signal_info" | awk -F: '/quality_score/ {gsub(/[^0-9-\.]/,"",$2); print $2; exit}')
                rsrp=$(echo "$signal_info" | awk -F: '/rsrp_dbm/ {gsub(/[^0-9-\.]/,"",$2); print $2; exit}')
                sinr=$(echo "$signal_info" | awk -F: '/sinr_db/ {gsub(/[^0-9-\.]/,"",$2); print $2; exit}')
            fi

            # Compute component scores (cached)
            rsrp_score=0
            sinr_score=0
            if [ -n "$rsrp" ]; then
                rsrp_score=$(score_rsrp_cached "$rsrp")
            fi
            if [ -n "$sinr" ]; then
                sinr_score=$(score_sinr_cached "$sinr")
            fi

            # Hard penalty when SINR is negative to reflect unstable radio
            if printf '%s' "$sinr" | grep -Eq '^-?[0-9]+$' && [ "$sinr" -lt 0 ]; then
                log_debug "SINR negative (${sinr} dB), applying penalty to sinr_score=${sinr_score}"
                sinr_score=$(awk -v s="$sinr_score" 'BEGIN{p=s-10; if(p<0)p=0; printf "%.2f", p}')
            fi

            # Performance proxy: use mobile_score (0..100) as initial Performance_score
            performance_score="$mobile_score"

            # Jitter penalty (placeholder for future metric)
            jitter_penalty=0

            # Composite weights (alpha+beta+gamma == 1)
            # can implemement tis logic later in config: getprop kitsunping.daemon.sigmoid.*=x.x <-- verifi if is "" and use static || static values
            LCL_ALPHA=0.4; LCL_BETA=0.3; LCL_GAMMA=0.3; LCL_DELTA=0.1

            composite=$(awk -v a="$LCL_ALPHA" -v b="$LCL_BETA" -v c="$LCL_GAMMA" -v r="$rsrp_score" -v s="$sinr_score" -v p="$performance_score" -v d="$LCL_DELTA" -v j="$jitter_penalty" 'BEGIN{v=a*r + b*s + c*p - d*j; if(v<0) v=0; if(v>100) v=100; printf "%.2f", v }')

            # Smooth composite with EMA
            composite_ema_val=$(composite_ema "$composite")

            # Decide profile using EMA value
            profile=$(decide_profile "$composite_ema_val")

            # Allow policy script to override/select profile if available
            if [ -f "$POLICY_DIR/decide_profile.sh" ]; then
                # Execute policy script in a subshell to avoid polluting daemon variables
                # (prevents decide_profile.sh from clobbering mobile_reason, etc.)
                policy_choice=$(
                    ( . "$POLICY_DIR/decide_profile.sh" && pick_profile "$wifi_state" "$WIFI_IFACE" "$wifi_reason" "$wifi_details" "${LAST_EVENT_FILE}" ) 2>/dev/null
                )
                # if policy returns non-empty, prefer it
                [ -n "$policy_choice" ] && profile="$policy_choice"
                # policy target will be handled by executor (PROFILE_CHANGED event)
            fi  

            # Persist desired profile request (daemon is NOT the applier)
            # The executor is responsible for writing `cache/policy.target` and `cache/policy.current`. 
            POLICY_REQUEST_FILE="$MODDIR/cache/policy.request"
            prev_profile=""
            [ -f "$POLICY_REQUEST_FILE" ] && prev_profile=$(cat "$POLICY_REQUEST_FILE" 2>/dev/null || echo "")
            if [ "$profile" != "$prev_profile" ]; then
                printf '%s' "$profile" > "$POLICY_REQUEST_FILE" 2>/dev/null || true
                emit_event "PROFILE_CHANGED" "from=$prev_profile to=$profile composite=$composite ema=$composite_ema_val rsrp=$rsrp rsrp_score=$rsrp_score sinr=$sinr sinr_score=$sinr_score"
            fi

            degraded_reason=""

            # Use composite to catch SINR-driven degradations; fallback to raw quality_score
            if printf '%s' "$composite" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
                if awk -v v="$composite" 'BEGIN{exit !(v>0 && v<40)}'; then
                    degraded_reason="composite"
                fi
            fi

            if [ -z "$degraded_reason" ] && echo "$signal_score" | grep -Eq '^[0-9]+$'; then
                if [ "$signal_score" -gt 0 ] && [ "$signal_score" -lt 40 ]; then
                    degraded_reason="rsrp"
                fi
            fi

            if [ -n "$degraded_reason" ]; then
                log_info "Poor signal detected ($degraded_reason) comp=$composite rsrp=$rsrp sinr=$sinr"
                emit_event "$EV_SIGNAL_DEGRADED" "reason=$degraded_reason comp=$composite rsrp=$rsrp sinr=$sinr iface=$mobile_iface"
            else
                log_debug "signal ok comp=$composite ema=$composite_ema_val rsrp_score=$rsrp_score sinr_score=$sinr_score"
            fi
        fi
    else
        signal_loop_count=0
    fi

    wifi_details="link=$wifi_link ip=$wifi_ip egress=$wifi_egress reason=$wifi_reason"

    if [ "$current_iface" != "$last_iface" ]; then
        log_info "iface_changed: $last_iface -> $current_iface"
        emit_event "$EV_IFACE_CHANGED" "from=$last_iface to=$current_iface"
        last_iface="$current_iface"
    fi

    if [ "$wifi_state" != "$last_wifi_state" ]; then
        log_info "wifi_state_changed: $last_wifi_state -> $wifi_state ($wifi_details)"
        if [ "$last_wifi_state" = "connected" ] && [ "$wifi_state" = "disconnected" ]; then
            log_info "event: wifi_left -> assume mobile priority"
            emit_event "$EV_WIFI_LEFT" "iface=$current_iface $wifi_details"
        elif [ "$last_wifi_state" = "disconnected" ] && [ "$wifi_state" = "connected" ]; then
            emit_event "$EV_WIFI_JOINED" "iface=$current_iface $wifi_details"
        fi
        last_wifi_state="$wifi_state"
    fi

    loop_count=$((loop_count + 1))
    if [ $loop_count -ge 6 ] || [ "$current_iface" = "none" ]; then
        log_debug "tick iface=$current_iface wifi=$wifi_state ($wifi_details)"
        loop_count=0
    fi

    cat <<EOF | atomic_write "$STATE_FILE"
iface=$current_iface
transport=$transport
wifi.iface=$WIFI_IFACE
wifi.state=$wifi_state
wifi.link=$wifi_link
wifi.ip=$wifi_ip
wifi.egress=$wifi_egress
wifi.score=$wifi_score
wifi.reason=$wifi_reason
mobile.iface=$mobile_iface
mobile.link=$mobile_link
mobile.ip=$mobile_ip
mobile.egress=$mobile_egress
mobile.score=$mobile_score
mobile.reason=$mobile_reason
rsrp_dbm=${rsrp:--}
rsrp_score=${rsrp_score:-0}
sinr_db=${sinr:--}
sinr_score=${sinr_score:-0}
composite_score=${composite:-0}
composite_ema=${composite_ema_val:-0}
profile=${profile:-unknown}
EOF
    sleep "$INTERVAL"
done
