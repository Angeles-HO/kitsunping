#!/system/bin/sh
# Minimal daemon: log interface and Wi-Fi/mobile transitions (MVP, no calibration)
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
STATE_FILE="$MODDIR/cache/daemon.state"
PID_FILE="$MODDIR/cache/daemon.pid"
LAST_EVENT_FILE="$MODDIR/cache/daemon.last"
EVENTS_DIR="$MODDIR/cache/events"
LAST_EVENT_JSON="$MODDIR/cache/event.last.json"
shared_errors="$MODDIR/addon/functions/debug/shared_errors.sh"
EXECUTOR_SH="$MODDIR/addon/policy/executor.sh"
IP_BIN=""
PING_BIN=""
RESET_PROP_BIN=""
JQ_BIN=""
EVENT_WIFI_LEFT="WIFI_LEFT"
EVENT_WIFI_JOINED="WIFI_JOINED"
EVENT_IFACE_CHANGED="IFACE_CHANGED"
EVENT_SIGNAL_DEGRADED="SIGNAL_DEGRADED"
EVENT_DEBOUNCE_SEC=3 # seconds (debounce time for events)
DAEMON_INTERVAL=10 # seconds (default polling interval)
LAST_TS_WIFI_LEFT=0
LAST_TS_WIFI_JOINED=0
LAST_TS_IFACE_CHANGED=0
INTERVAL_DEFAULT=10 # seconds
INTERVAL="$INTERVAL_DEFAULT"
SIGNAL_POLL_INTERVAL=5 # poll signal quality every N loops when on mobile
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

# Source modular components (if installed)
if [ -f "$MODDIR/addon/functions/core.sh" ]; then
    . "$MODDIR/addon/functions/core.sh"
fi
if [ -f "$MODDIR/addon/functions/net_math.sh" ]; then
    . "$MODDIR/addon/functions/net_math.sh"
fi
if [ -f "$MODDIR/addon/daemon/iface_monitor.sh" ]; then
    . "$MODDIR/addon/daemon/iface_monitor.sh"
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
## Usage: write_event_json "event_name" timestamp "details"
## e.g., write_event_json "WIFI_LEFT" 1620000000 "iface=wlan0 link=DOWN ip=0 egress=0 reason=link_down"
write_event_json() {
    local name="$1" ts="$2" details jsonfile="$LAST_EVENT_JSON"
    details="$(json_escape "$3")"

    cat <<EOF | atomic_write "$jsonfile"
{"event":"$name","ts":$ts,"details":"$details","iface":"$current_iface","wifi_state":"$wifi_state","wifi_score":$wifi_score}
EOF
}

## Source shared_error.sh if exists (for better logging)
if [ -f "$shared_errors" ]; then . "$shared_errors"
    ## Override log_info with log_daemon if available
    command -v log_daemon >/dev/null 2>&1 && log_info() { log_daemon "$@";  } 
else
    log_warning "Shared_errors no encontrado: $shared_errors (usando logger interno)"
fi

# ============== Singleton Enforcement ==============
## Ensure only one instance of the daemon is running 
## On TERM or INT, log stop and remove pidfile
## Usage: ensure_singleton
trap 'log_info "daemon stopped"; rm -f "$PID_FILE" 2>/dev/null; exit 0' TERM INT

## Ensure singleton instance of daemon 
ensure_singleton() {
    ## Create pidfile dir if not exists
    mkdir -p "${PID_FILE%/*}" 2>/dev/null

    ## Check for existing pidfile
    if [ -f "$PID_FILE" ]; then
        ## Check if process is running
        local old_pid 
        ## Read old pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null)
        ## Check if process with old_pid is running
        if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
            log_warning "daemon already running with PID $old_pid; exiting for no conflict/duplication"
            exit 0
        fi
        ## Cleanup stale pidfile
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
    date +%s 2>/dev/null || busybox date +%s 2>/dev/null || awk 'BEGIN{print systime()}' 2>/dev/null || echo 0 
}
# ============== Command Checks ==============
## Check for required commands and set global vars
## Usage: check_and_detect_commands
## Sets global vars: IP_BIN, PING_BIN, RESET_PROP_BIN
check_and_detect_commands() {
    # Detect ip
    if command_exists ip; then
        IP_BIN=$(command -v ip 2>/dev/null)
    elif [ -x "$MODDIR/addon/ip/ip" ]; then
        IP_BIN="$MODDIR/addon/ip/ip"
    fi

    # Validate ip binary found
    if [ -z "$IP_BIN" ]; then
        log_error "ip binary not found"
        exit 1
    fi

    # Detect ping binary 
    if command_exists ping; then
        PING_BIN=$(command -v ping 2>/dev/null)
    elif command_exists busybox; then
        local bb
        bb=$(command -v busybox 2>/dev/null)
        PING_BIN="$bb ping"
    elif [ -x "/system/bin/ping" ]; then
        PING_BIN="/system/bin/ping"
    fi
 
    # Log detected binaries
    if [ -z "$PING_BIN" ]; then
        log_warning "ping binary not found; skipping ping-based checks"
    else
        log_debug "PING_BIN resolved to: $PING_BIN"
    fi

    # Detect resetprop binary
    if command_exists resetprop; then
        RESET_PROP_BIN=$(command -v resetprop 2>/dev/null)
        log_debug "resetprop resolved to: $RESET_PROP_BIN"
    fi

    # Detect jq (prefer bundled)
    if [ -x "$MODDIR/addon/jq/arm64/jq" ]; then
        JQ_BIN="$MODDIR/addon/jq/arm64/jq"
    elif command_exists jq; then
        JQ_BIN=$(command -v jq 2>/dev/null)
    fi
    [ -n "$JQ_BIN" ] && log_debug "jq resolved to: $JQ_BIN" || log_warning "jq not found; falling back to awk for signal parsing"

    # Detect bc (prefer bundled in addon if present)
    BC_BIN=""
    if command_exists bc; then
        BC_BIN=$(command -v bc 2>/dev/null)
    elif [ -x "$MODDIR/addon/bc/arm64/bc" ]; then
        BC_BIN="$MODDIR/addon/bc/arm64/bc"
    fi
    if [ -n "$BC_BIN" ]; then
        log_debug "bc resolved to: $BC_BIN"
    else
        log_warning "bc not found; using tier fallbacks for sigmoid scoring"
    fi

    log_debug "IP_BIN resolved to: $IP_BIN"
}

# ============== Main Functions ==============
## Determine if event should be emitted based on debounce time
## Usage: should_emit_event "event_name"
## Returns 0 (true) if event should be emitted, 1 (false) otherwise
should_emit_event() {
    # Check last emitted timestamp for event
    local name="$1" now last_var last_ts diff
    now=$(now_epoch)

    # If no name provided, do not emit
    [ -z "$name" ] && return 1 

    # If now is 0 (error), do not emit
    [ "$now" -eq 0 ] && return 1

    # Check last emitted timestamp
    last_var="LAST_TS_${name}"

    # Get last timestamp value
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
    # Local vars
    local name="$1" details="$2" now
    now=$(now_epoch) # Get current epoch time

    # Validate event name
    [ -z "$name" ] && log_warning "emit_event called with empty name" && return 1

    # Check debounce and emit event 
    if should_emit_event "$name"; then
        # Emit event
        log_info "EVENT $name ts=$now $details" # Log event
        write_event_json "$name" "$now" "$details" # Write event to JSON
        # Write last event to LAST_EVENT_FILE
        printf '%s %s %s\n' "$name" "$now" "$details" | atomic_write "$LAST_EVENT_FILE"
        # Execute policy executor script if exists and is executable
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
        log_debug "EVENT debounce $name"
    fi
}

# Initial delay to allow system to stabilize
sleep 10
check_and_detect_commands
ensure_singleton

# Configure interval from system.prop or environment variable e. g., kitsunping.daemon.interval = 10 seconds
interval_prop="$(getprop kitsunping.daemon.interval 2>/dev/null)"

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

get_default_iface() {
    # Some Android devices do not list 0.0.0.0/0; prioritize route get and use show default as fallback
    local via_default

    via_default=$("$IP_BIN" route get 8.8.8.8 2>/dev/null | awk '/dev/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
    if [ -n "$via_default" ]; then
        echo "$via_default"
        return
    fi

    "$IP_BIN" route show default 2>/dev/null | awk '/dev/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

get_wifi_status() {
    local wifi_iface="${1:-$WIFI_IFACE}" link_state="DOWN" link_up=0 has_ip=0 def_route=0 dhcp_ip reason

    link_state=$("$IP_BIN" link show "$wifi_iface" 2>/dev/null | awk '/state/ {print $9; exit}')
    [ "$link_state" = "UP" ] && link_up=1

    if "$IP_BIN" addr show "$wifi_iface" 2>/dev/null | grep -q "inet "; then
        has_ip=1
    fi

    dhcp_ip=$(getprop dhcp.${wifi_iface}.ipaddress 2>/dev/null)
    [ -n "$dhcp_ip" ] && has_ip=1

    if "$IP_BIN" route get 8.8.8.8 2>/dev/null | grep -q "dev $wifi_iface"; then
        def_route=1
    fi

    reason="link_down"
    if [ $link_up -eq 1 ]; then
        if [ $has_ip -eq 1 ]; then
            if [ $def_route -eq 1 ]; then
                reason="usable_route"
            else
                reason="no_egress"
            fi
        else
            reason="no_ip"
        fi
    fi

    echo "iface=$wifi_iface link=$link_state ip=$has_ip egress=$def_route reason=$reason"
}

get_mobile_status() {
    local iface="$1" link_state="DOWN" link_up=0 has_ip=0 def_route=0 reason

    [ -z "$iface" ] && iface="none"
    [ "$iface" = "none" ] && { echo "iface=none link=DOWN ip=0 egress=0 reason=not_found"; return; }

    link_state=$("$IP_BIN" link show "$iface" 2>/dev/null | awk '/state/ {print $9; exit}')
    [ "$link_state" = "UP" ] && link_up=1

    if "$IP_BIN" addr show "$iface" 2>/dev/null | grep -q "inet "; then
        has_ip=1
    fi

    if "$IP_BIN" route get 8.8.8.8 2>/dev/null | grep -q "dev $iface"; then
        def_route=1
    fi

    reason="link_down"
    if [ $link_up -eq 1 ]; then
        if [ $has_ip -eq 1 ]; then
            if [ $def_route -eq 1 ]; then
                reason="usable_route"
            else
                reason="no_egress"
            fi
        else
            reason="no_ip"
        fi
    fi

    echo "iface=$iface link=$link_state ip=$has_ip egress=$def_route reason=$reason"
}

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
[ -z "$WIFI_IFACE" ] && WIFI_IFACE="wlan0"

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

log_info "daemon start (MVP: monitor iface and wifi->mobile transitions)"

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
                # shellcheck disable=SC1090
                . "$POLICY_DIR/decide_profile.sh"
                # call pick_profile(wifi_state, iface, details, wifi_details, last_event)
                policy_choice=$(pick_profile "$wifi_state" "$WIFI_IFACE" "$wifi_reason" "$wifi_details" "${LAST_EVENT_FILE}")
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

            if echo "$signal_score" | grep -Eq '^[0-9]+$'; then
                if [ "$signal_score" -lt 40 ]; then
                    log_info "Poor signal detected ($signal_score), enabling conservative mode"
                    emit_event "$EVENT_SIGNAL_DEGRADED" "score=$signal_score iface=$mobile_iface"
                fi
            else
                log_debug "signal_score unavailable in signal_info"
            fi
        fi
    else
        signal_loop_count=0
    fi

    wifi_details="link=$wifi_link ip=$wifi_ip egress=$wifi_egress reason=$wifi_reason"

    if [ "$current_iface" != "$last_iface" ]; then
        log_info "iface_changed: $last_iface -> $current_iface"
        emit_event "$EVENT_IFACE_CHANGED" "from=$last_iface to=$current_iface"
        last_iface="$current_iface"
    fi

    if [ "$wifi_state" != "$last_wifi_state" ]; then
        log_info "wifi_state_changed: $last_wifi_state -> $wifi_state ($wifi_details)"
        if [ "$last_wifi_state" = "connected" ] && [ "$wifi_state" = "disconnected" ]; then
            log_info "event: wifi_left -> assume mobile priority"
            emit_event "$EVENT_WIFI_LEFT" "iface=$current_iface $wifi_details"
        elif [ "$last_wifi_state" = "disconnected" ] && [ "$wifi_state" = "connected" ]; then
            emit_event "$EVENT_WIFI_JOINED" "iface=$current_iface $wifi_details"
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
