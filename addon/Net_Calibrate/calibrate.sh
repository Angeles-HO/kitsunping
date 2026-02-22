#!/system/bin/sh
# Net Calibrate.sh Script
# Version: 4.89
# Description: This script calibrates network properties for optimal performance.
# Status: re open - 4/02/2026

# Global variables
# NOTE: This script is commonly *sourced* by executor.sh. When sourced, $0 is the
# caller, so prefer caller-provided NEWMODPATH/MODDIR and avoid clobbering them.
if [ -z "${NEWMODPATH:-}" ] || [ ! -d "${NEWMODPATH:-/}" ]; then
    if [ -n "${MODDIR:-}" ] && [ -d "${MODDIR:-/}" ]; then
        NEWMODPATH="$MODDIR"
    else
        # Best-effort derive module root from caller path.
        _caller_dir="${0%/*}"
        case "$_caller_dir" in
            */addon/Net_Calibrate) NEWMODPATH="${_caller_dir%%/addon/Net_Calibrate}" ;;
            */addon/*) NEWMODPATH="${_caller_dir%%/addon/*}" ;;
            */addon) NEWMODPATH="${_caller_dir%%/addon}" ;;
            *) NEWMODPATH="${_caller_dir%/*}" ;;
        esac
    fi
fi

: "${MODDIR:=$NEWMODPATH}"

# Keep legacy variable names for internal references.
SCRIPT_DIR="$NEWMODPATH/addon/Net_Calibrate"
ADDON_DIR="$NEWMODPATH/addon"
NET_PROPERTIES_KEYS="ro.ril.hsupa.category ro.ril.hsdpa.category" # Priority, for [upload and download] WIFI
NET_OTHERS_PROPERTIES_KEYS="ro.ril.lte.category ro.ril.ltea.category ro.ril.nr5g.category" # Priority, for [LTE, LTEA, 5G] Data
NET_VAL_HSUPA="10 12 14 16 18 20 22 24 26" # Testing values for higher upload
NET_VAL_HSDPA="10 12 14 16 18 20 22 24 26" # Testing values for higher download
NET_VAL_LTE="5 6 7 8 9 10 11 12" # Testing values for LTE data technology
NET_VAL_LTEA="6 8 10 12 14 16 18 20 22" # Testing values for LTEA data technology
NET_VAL_5G="1 2 3 4 5" # Testing values for 5G data technology

# Logs Variables
NETMETER_FILE="$NEWMODPATH/logs/calibrate.log"
trace_log="/sdcard/trace_log.log"

# Binarys Variables
jqbin="$NEWMODPATH/addon/jq/arm64/jq"
ipbin="$NEWMODPATH/addon/ip/ip" 
pingbin="$NEWMODPATH/addon/ping"

# Cache for Calibrate.sh optimizations
CACHE_DIR_cln="$NEWMODPATH/cache"
data_dir="$NEWMODPATH/addon/Net_Calibrate/data"
fallback_json="$data_dir/unknown.json"
cache_dir="$data_dir/cache"

## Cache for states
CALIBRATE_STATE_RUN="$NEWMODPATH/cache/calibrate.state"
CALIBRATE_LAST_RUN="$NEWMODPATH/cache/calibrate.ts"

# Calibration cache (best values) - avoids re-calibrating from scratch every boot.
# Cache is keyed by provider/operator string (from configure_network JSON).
CALIBRATE_CACHE_ENV="$NEWMODPATH/cache/calibrate.best.env"
CALIBRATE_CACHE_META="$NEWMODPATH/cache/calibrate.best.meta"

calibrate_cache_load_vars() {
    local env_file="$1"
    [ -f "$env_file" ] || return 1

    # Strictly accept only BEST_ro_ril_* lines (numbers only).
    if ! grep -Eq '^(BEST_ro_ril_(hsupa|hsdpa|lte|ltea|nr5g)_category)=[0-9]+$' "$env_file" 2>/dev/null; then
        return 1
    fi

    # shellcheck disable=SC1090
    . "$env_file" 2>/dev/null || return 1
    return 0
}

calibrate_cache_try_use() {
    # Args: provider ping_target
    local provider="$1" ping_target="$2"
    local enable max_age now ts age max_rtt max_loss rc

    enable=$(getprop persist.kitsunping.calibrate_cache_enable 2>/dev/null)
    [ -z "$enable" ] && enable=1
    case "$enable" in
        0|false|FALSE|off|OFF|no|NO) return 1 ;;
    esac

    [ -f "$CALIBRATE_CACHE_META" ] || return 1
    [ -f "$CALIBRATE_CACHE_ENV" ] || return 1

    # Meta format: PROVIDER='<str>' TS=<epoch>
    local cached_provider cached_ts
    cached_provider=$(awk -F= '/^PROVIDER=/{gsub(/^PROVIDER=|^\x27|\x27$/, "", $0); sub(/^PROVIDER=/, "", $0); print; exit}' "$CALIBRATE_CACHE_META" 2>/dev/null)
    cached_ts=$(awk -F= '/^TS=/{print $2; exit}' "$CALIBRATE_CACHE_META" 2>/dev/null)
    [ -z "$cached_provider" ] && return 1
    [ -z "$cached_ts" ] && return 1

    if [ "$cached_provider" != "$provider" ]; then
        return 1
    fi

    max_age=$(getprop persist.kitsunping.calibrate_cache_max_age_sec 2>/dev/null)
    [ -z "$max_age" ] && max_age=604800
    case "$max_age" in ''|*[!0-9]* ) max_age=604800;; esac

    now=$(date +%s)
    case "$now" in ''|*[!0-9]* ) now=0;; esac
    case "$cached_ts" in ''|*[!0-9]* ) cached_ts=0;; esac

    if [ "$now" -gt 0 ] && [ "$cached_ts" -gt 0 ]; then
        age=$((now - cached_ts))
        [ "$age" -lt 0 ] && age=0
        if [ "$age" -gt "$max_age" ]; then
            return 1
        fi
    fi

    # Quick validation: ensure we still have good ping metrics.
    max_rtt=$(getprop persist.kitsunping.calibrate_cache_rtt_ms 2>/dev/null)
    [ -z "$max_rtt" ] && max_rtt=120
    case "$max_rtt" in ''|*[!0-9]* ) max_rtt=120;; esac

    max_loss=$(getprop persist.kitsunping.calibrate_cache_loss_pct 2>/dev/null)
    [ -z "$max_loss" ] && max_loss=5
    case "$max_loss" in ''|*[!0-9]* ) max_loss=5;; esac

    # Prefer ping_target from JSON, but fallback to 8.8.8.8
    [ -z "$ping_target" ] && ping_target="8.8.8.8"

    test_ping_target "$ping_target"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        return 1
    fi

    # Require numeric metrics
    if ! printf '%s' "${PROBE_RTT_MS:-}" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        return 1
    fi
    if ! printf '%s' "${PROBE_LOSS_PCT:-}" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        return 1
    fi

    if awk -v rtt="$PROBE_RTT_MS" -v max="$max_rtt" 'BEGIN{exit !(rtt>0 && rtt<=max)}' && \
       awk -v loss="$PROBE_LOSS_PCT" -v max="$max_loss" 'BEGIN{exit !(loss>=0 && loss<=max)}'; then
        if ! calibrate_cache_load_vars "$CALIBRATE_CACHE_ENV"; then
            return 1
        fi

        log_info "Using calibration cache for provider=$provider (rtt=${PROBE_RTT_MS}ms loss=${PROBE_LOSS_PCT}%)" >> "$trace_log"

        # Mark calibration as cooling and refresh last-run timestamp.
        echo "cooling" | atomic_write "$CALIBRATE_STATE_RUN"
        echo "$(date +%s)" | atomic_write "$CALIBRATE_LAST_RUN"

        echo "BEST_ro_ril_hsupa_category=$BEST_ro_ril_hsupa_category"
        echo "BEST_ro_ril_hsdpa_category=$BEST_ro_ril_hsdpa_category"
        echo "BEST_ro_ril_lte_category=$BEST_ro_ril_lte_category"
        echo "BEST_ro_ril_ltea_category=$BEST_ro_ril_ltea_category"
        echo "BEST_ro_ril_nr5g_category=$BEST_ro_ril_nr5g_category"
        return 0
    fi

    return 1
}

calibrate_cache_save() {
    # Args: provider
    local provider="$1" ts
    ts=$(date +%s)
    case "$ts" in ''|*[!0-9]* ) ts=0;; esac

    # Save env with BEST_* values.
    {
        echo "BEST_ro_ril_hsupa_category=${BEST_ro_ril_hsupa_category:-}"
        echo "BEST_ro_ril_hsdpa_category=${BEST_ro_ril_hsdpa_category:-}"
        echo "BEST_ro_ril_lte_category=${BEST_ro_ril_lte_category:-}"
        echo "BEST_ro_ril_ltea_category=${BEST_ro_ril_ltea_category:-}"
        echo "BEST_ro_ril_nr5g_category=${BEST_ro_ril_nr5g_category:-}"
    } | atomic_write "$CALIBRATE_CACHE_ENV"

    {
        echo "PROVIDER='$provider'"
        echo "TS=$ts"
    } | atomic_write "$CALIBRATE_CACHE_META"
}

# Getprops variables
ping_count="$(getprop persist.kitsunping.ping_timeout)"
ping_count="${ping_count:-7}"

# Rare if not found but just in case
verify_scripts() {
    script="$1"
    if [ ! -f "$script" ]; then
        echo "[ERROR] Required script not found: $script" >> "$trace_log"
        exit 1
    fi

    # These helpers are sourced, not executed; on Windows-built zips the +x bit
    # is often lost. Ensure readability and continue.
    if [ ! -r "$script" ]; then
        chmod 0644 "$script" 2>/dev/null
    fi
    if [ ! -r "$script" ]; then
        echo "[ERROR] Required script not readable: $script" >> "$trace_log"
        exit 1
    fi

    echo "[INFO] Sourcing script: $script" >> "$trace_log"
    . "$script"
}

# Load helper scripts for advanced functions
verify_scripts "$NEWMODPATH/addon/functions/utils/env_detect.sh"
# Network helpers (test_ping_target/test_dns_ip)
verify_scripts "$NEWMODPATH/addon/functions/network_utils.sh"
# Generic utils
verify_scripts "$NEWMODPATH/addon/functions/utils/Kitsutils.sh"

# Description: Backup current network-related properties to a file.
echo "$(date +%s)" | atomic_write "$CALIBRATE_LAST_RUN"
echo "running" | atomic_write "$CALIBRATE_STATE_RUN"

# Create backup when calibration starts
create_backup

# Description: Ensure core binaries exist and ping works.
check_and_detect_commands() {
    log_info "====================== check_and_detect_commands =========================" >> "$trace_log"

    check_core_commands ip ndc resetprop awk || return 1
    detect_ip_binary || return 1
    ipbin="$IP_BIN"

    # returns 0 = OK, 1 = ping binary not found, 2 = ping not functional
    check_and_prepare_ping "$pingbin"
    # get output code
    local rc
    rc=$?

    case "$rc" in
        0)
            log_debug "Ping binary functional: $PING_BIN" >> "$trace_log"
            return 0
            ;;
        1)
            log_error "Ping binary not found" >> "$trace_log"
            return 1
            ;;
        2)
            log_warning "Ping binary detected but not functional" >> "$trace_log"

            # Scan for common issues
            if is_install_context; then
                log_info "Install context detected." >> "$trace_log"
                log_info "Error code 2: Ping not functional in install context (possible no connectivity)" >> "$trace_log"
                return 2 # skip calibration in install context
            elif is_daemon_running; then
                # posible SELinux or permission issue, or network blocking while daemon is active
                log_error "Ping not functional while daemon is running" >> "$trace_log"
                log_error "Check SELinux, permissions, or network state" >> "$trace_log"

                if command -v getenforce >/dev/null 2>&1 && getenforce | grep -q Enforcing; then
                    log_warning "SELinux enforcing mode may block ping (CAP_NET_RAW)" >> "$trace_log"
                fi
                return 3
            else
                log_error "Ping not functional; check connectivity or permissions, or if exist" >> "$trace_log"
            fi
            return 1
            ;;
    esac
}

# v4.85
# Main function to calibrate network settings
# Description: Orchestrate full calibration flow for radio properties using ping-based scoring.
# Usage: calibrate_network_settings <delay_seconds>
calibrate_network_settings() {
    if [ -z "$1" ] || ! echo "$1" | grep -Eq '^[0-9]+$' || [ "$1" -lt 1 ]; then
        log_error "calibrate_network_settings <delay_seconds>" >&2
        return 1
    fi

    log_info "====================== calibrate_network_settings =========================" >> "$trace_log" 
    # Ensure core commands and ping functionality
    check_and_detect_commands
    local calibrate_ping_status=$?

    # v4.89
    # Interpret decision result and return appropriate code to executor.sh for postpone handling, etc.
    case "$calibrate_ping_status" in
        0)
            log_info "Ping functional; proceeding with calibration" >> "$NETMETER_FILE"
            ;;
        1)
            log_error "Ping binary not found; aborting calibration" >> "$NETMETER_FILE"
            return 1
            ;;
        2)
            log_error "Ping not functional (install/context issue); aborting calibration" >> "$NETMETER_FILE"
            return 2
            ;;
        3)
            log_info "Ping not functional while daemon running; requesting postpone" >> "$NETMETER_FILE"
            log_error "Check SELinux, permissions, or network state" >> "$NETMETER_FILE"
            if command -v getenforce >/dev/null 2>&1 && getenforce | grep -q Enforcing; then
                log_warning "SELinux enforcing mode may block ping (CAP_NET_RAW)" >> "$NETMETER_FILE"
            fi
            return 3
            ;;
        *)
            log_error "Unknown status code: $calibrate_ping_status; aborting calibration" >> "$NETMETER_FILE"
            return 4
            ;;
    esac

  
    local delay=$1 # seconds
    local config_json dns1 dns2 TEST_IP # unassigned local variables

    log_info "====================== calibrate_property =========================" >> "$trace_log"
    log_info "Execution trace, delay: $delay seconds" >> "$trace_log"
    config_json=$(configure_network) # get network configuration
    log_info "====================== calibrate_property =========================" >> "$trace_log"
    log_info "Network configuration obtained (config_json): $config_json" >> "$trace_log"

    echo "$config_json" | "$jqbin" -e 'type == "object" and has("provider") and has("dns") and has("ping")' >/dev/null || {
        log_info "[ERROR] config_json invalido o incompleto:" >> "$trace_log"
        log_info "$config_json" >> "$trace_log"
        return 1
    }

    provider_name=$(echo "$config_json" | "$jqbin" -r '.provider // "Unknown"')

    # Extract DNS and ping targets from JSON, with defaults
    dns1=$(echo "$config_json" | "$jqbin" -r '.dns[0] // "8.8.8.8"')
    dns2=$(echo "$config_json" | "$jqbin" -r '.dns[1] // "8.8.4.4"')
    PING_VAL=$(echo "$config_json" | "$jqbin" -r '.ping // "8.8.8.8"')

    # Fast path: if we have a valid cache for this provider and ping is still good, reuse it.
    # This avoids re-calibrating from scratch on every reboot when the operator remains the same.
    if calibrate_cache_try_use "$provider_name" "$PING_VAL"; then
        return 0
    fi

    test_dns_ip "$dns1" "$dns2" "$PING_VAL"
    status=$?

    case "$status" in
        0) log_info "Provider FULL_OK" >> "$trace_log" ;;
        2) log_warning "Provider DNS_ONLY_OK (ping target no metrics; DNS usable for metrics)" >> "$trace_log" ;;
        3) log_warning "Provider PING_ONLY_OK (ping target usable; DNS not usable for metrics)" >> "$trace_log" ;;
        1)
            # No abort here: we can still try hostname fallback for metrics.
            log_warning "Provider UNUSABLE for metrics; trying fallback targets" >> "$trace_log"
            ;;
    esac

    # If JSON provides an IP for ping, probe both the IP and a geo-aware
    # hostname (so DNS resolution uses the provider DNS we just configured)
    # and choose the target with lower RTT.
    country_code=$(getprop gsm.sim.operator.iso-country 2>/dev/null | tr '[:upper:]' '[:lower:]')
    [ -z "$country_code" ] && country_code="global"

    if echo "$PING_VAL" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
        ORIGINAL_IP="$PING_VAL"
        HOSTNAME="${country_code}.pool.ntp.org"
        log_info "Ping field is IP; probing ORIGINAL_IP=$ORIGINAL_IP and HOSTNAME=$HOSTNAME" >> "$trace_log"

        # Probe ORIGINAL IP and HOSTNAME.
        # IMPORTANT: Only targets that return RTT stats are usable for calibration.
        avg_ip="9999"
        avg_host="9999"

        test_ping_target "$ORIGINAL_IP"
        rc_ip=$?
        out_ip="$PROBE_LAST_OUTPUT"
        if [ $rc_ip -eq 0 ]; then
            avg_ip="$PROBE_RTT_MS"
        else
            log_debug "Discarding ORIGINAL_IP for calibration (no metrics): rc=$rc_ip" >> "$trace_log"
        fi

        test_ping_target "$HOSTNAME"
        rc_host=$?
        out_host="$PROBE_LAST_OUTPUT"
        if [ $rc_host -eq 0 ]; then
            avg_host="$PROBE_RTT_MS"
        else
            log_debug "Discarding HOSTNAME for calibration (no metrics): rc=$rc_host" >> "$trace_log"
        fi

        # Extract resolved IP for logging (if present in ping output)
        resolved_host_ip=$(echo "$out_host" | awk -F'[()]' 'NR==1{print $2}')
        [ -z "$resolved_host_ip" ] && resolved_host_ip="(unresolved)"

        # Decide: prefer numeric smaller RTT; handle non-numeric gracefully
        choice=$(awk -v a="$avg_ip" -v b="$avg_host" 'BEGIN {
            isnum = "^-?[0-9]+(\.[0-9]+)?$"
            if (a ~ isnum && b ~ isnum) {
                if (a <= 0 && b <= 0) { print "host"; exit }
                if (a <= 0) { print "host"; exit }
                if (b <= 0) { print "ip"; exit }
                if (a <= b) print "ip"; else print "host"
            } else if (a ~ isnum) print "ip"; else print "host"
        }')

        if [ "$choice" = "ip" ]; then
            TEST_IP="$ORIGINAL_IP"
            log_info "Chose ORIGINAL_IP ($avg_ip ms) over HOSTNAME ($avg_host ms)" >> "$trace_log"
        else
            TEST_IP="$HOSTNAME"
            log_info "Chose HOSTNAME $HOSTNAME -> $resolved_host_ip ($avg_host ms) over ORIGINAL_IP ($avg_ip ms)" >> "$trace_log"
        fi
    else
        TEST_IP="$PING_VAL"
    fi

    log_info "DNS1: $dns1, DNS2: $dns2, TEST_IP: $TEST_IP" >> "$trace_log"
    log_info "Checking connectivity..."  >> "$trace_log"

    if ! $PING_BIN -c 3 -W 5 "$TEST_IP" >/dev/null; then
        log_error "[ERROR] No Internet connection" >> "$trace_log"
        return 1
    else
        log_info "Connectivity test passed" >> "$trace_log"
    fi

    local index=1
    export TEST_IP

    log_info "Starting calibration for $TEST_IP" >> "$trace_log"
    for prop in $NET_PROPERTIES_KEYS; do
        (
            case "$prop" in
                "ro.ril.hsupa.category")
                    vals="$NET_VAL_HSUPA"
                    ;;
                "ro.ril.hsdpa.category")
                    vals="$NET_VAL_HSDPA"
                    ;;
                *)
                    vals=$(get_values_for_prop "$index")
                    ;;
            esac
            if [ -z "$vals" ]; then
                log_info "Empty value set for $prop" >> "$trace_log"
                continue
            fi
            log_info "====================== calibrate_network_settings =========================" >> "$trace_log"
            log_info "Calibrating properties: prop: [$prop] val: [$vals] delay: [$delay] at [${CACHE_DIR_cln}/$prop.best]" >> "$trace_log"
            calibrate_property "$prop" "$vals" "$delay" "$CACHE_DIR_cln/$prop.best"
        ) &
        index=$((index + 1))
    done

    wait

    for prop in $NET_PROPERTIES_KEYS; do
        # Read the best value from TMPDIR/*.best files
        local best_file="$CACHE_DIR_cln/$prop.best"
        local best_val="1"
        [ -f "$best_file" ] && best_val=$(cat "$best_file")
        log_info "Exporting properties: [BEST_${prop//./_}=$best_val]" >> "$trace_log"
        export "BEST_${prop//./_}=$best_val"
    done

    # Catch the active network interface from the default route (all within su -c to avoid awk/grep errors)
    local current_iface
    # Detect interface prioritizing real traffic: first rmnet*, then wlan*
    current_iface=$(su -c "awk 'NR>2 {gsub(/:/,\"\",\$1); if (\$1 ~ /^rmnet/) {t=\$2+\$10; if (t>max_rm) {max_rm=t; dev_rm=\$1}} else if (\$1 ~ /^wlan/) {t=\$2+\$10; if (t>max_wl) {max_wl=t; dev_wl=\$1}}} END {if (dev_rm != \"\") print dev_rm; else if (dev_wl != \"\") print dev_wl;}' /proc/net/dev" 2>/dev/null)

    sim_iso=$(getprop gsm.sim.operator.iso-country 2>/dev/null | tr '[:upper:]' '[:lower:]')


    # Decide calibration path based on interface type: rmnet* (mobile/data) vs Active wifi and not rmnet, but have SIM props vs wlan* (Wi-Fi)
    if echo "$current_iface" | grep -qi '^rmnet'; then
        log_info "Mobile/data mode: extended calibration [detail:${current_iface}]" >> "$trace_log"
        calibrate_secondary_network_settings $delay "$CACHE_DIR_cln"
    elif [ -n "$sim_iso" ]; then
        log_info "SIM detected ($sim_iso) with non-rmnet iface; running extended calibration anyway [detail:${current_iface}]" >> "$trace_log"
        calibrate_secondary_network_settings $delay "$CACHE_DIR_cln"
    elif echo "$current_iface" | grep -qi '^wlan' && [ -z "$sim_iso" ]; then
        log_info "Wi-Fi mode: calibrating only HSUPA/HSDPA [detail:${current_iface}]" >> "$trace_log"
    else
        log_info "Unknown iface, defaulting to Wi-Fi calibration path [detail:${current_iface}]" >> "$trace_log"
    fi

    echo "cooling" > "$CALIBRATE_STATE_RUN"
    log_info "====================== calibrate_network_settings =========================" >> "$trace_log"

    # Persist cache for future runs (provider keyed).
    calibrate_cache_save "$provider_name"

    echo "BEST_ro_ril_hsupa_category=$BEST_ro_ril_hsupa_category"
    echo "BEST_ro_ril_hsdpa_category=$BEST_ro_ril_hsdpa_category"
    echo "BEST_ro_ril_lte_category=$BEST_ro_ril_lte_category"
    echo "BEST_ro_ril_ltea_category=$BEST_ro_ril_ltea_category"
    echo "BEST_ro_ril_nr5g_category=$BEST_ro_ril_nr5g_category"
}

# Description: Slice shared NET_PROPERTIES_VALUES based on PROP_OFFSETS for a given index.
# Usage: get_values_for_prop <index>
get_values_for_prop() {
    local index="$1"
    log_info "====================== get_values_for_prop =========================" >> "$trace_log"
    log_info "index: $index" >> "$trace_log"

    # Store and get the initial offset for the current property (e.g., 0)
    local start=$(echo "$PROP_OFFSETS" | cut -d' ' -f$index)
    log_info "PROP_OFFSETS: $PROP_OFFSETS" >> "$trace_log"
    log_info "start: $start" >> "$trace_log"

    # Store and get the next offset (if it exists) to determine the range of values (e.g., 6)
    local end=$(echo "$PROP_OFFSETS" | cut -d' ' -f$((index + 1)) 2>/dev/null)
    log_info "PROP_OFFSETS: $PROP_OFFSETS" >> "$trace_log"
    log_info "end: $end" >> "$trace_log"

    # Calculate the total number of available values in NET_PROPERTIES_VALUES
    local total=$(echo "$NET_PROPERTIES_VALUES" | wc -w)
    log_info "PROP_OFFSETS: $NET_PROPERTIES_VALUES" >> "$trace_log"
    log_info "end: $total" >> "$trace_log"

    # Extract the values corresponding to the current property
    if [ -z "$end" ]; then
        # If there is no next offset, take all values from the current offset to the end
        echo "$NET_PROPERTIES_VALUES" | cut -d' ' -f$((start + 1))-"$total"
    else
        # If there is a next offset, take the values between the current offset and the next
        # └── that is, take those from: 0 to 6
        echo "$NET_PROPERTIES_VALUES" | cut -d' ' -f$((start + 1))-"$end"
    fi
}

#v4.85
# Description: Iterate candidate values for a property, score them via ping, persist the best.
# Usage: calibrate_property <property> "<candidates>" <delay_seconds> <best_file_path>
calibrate_property() {
    local property="$1"
    local candidates="$2"
    local delay="$3"
    local best_file="$4"
    
    local best_score=0
    local best_val=$(echo "$candidates" | awk '{print $1}')
    local attempts=3
    
    log_info "====================== calibrate_property =========================" >> "$trace_log"
    log_info "Properties: property: $property | candidates: $candidates | delay: $delay | best_file: $best_file" >> "$trace_log"
    log_info "best_val: $best_val" >> "$trace_log"

    # Verify write permissions first
    local write_test="${best_file}.test"
    log_info "write_test: $write_test" >> "$trace_log"
    if ! touch "$write_test" 2>/dev/null; then
        log_error "Cannot write to: $(dirname "$best_file")"
        return 1
    fi
    rm -f "$write_test"
    
    for candidate in $candidates; do
        local total_score=0
        
        resetprop "$property" "$candidate" >/dev/null 2>&1
            log_info "using resetprop: property: $property | candidate: $candidate" >> "$trace_log"

        sleep 1
        
        for i in $(seq 1 $attempts); do
            local ping_result=$(test_configuration "$property" "$candidate" "$delay")
            log_info "using ping_result: $ping_result" >> "$trace_log"
            local score=$(extract_scores "$ping_result")
            log_info "using score: $score" >> "$trace_log"
            
            total_score=$(awk "BEGIN {print $total_score + $score}")
            log_info "using total_score: $total_score" >> "$trace_log"
            sleep 0.5
        done
        
        local avg_score=$(awk "BEGIN {print $total_score / $attempts}")
        log_info "using avg_score: $avg_score" >> "$trace_log"
        
        if awk "BEGIN {exit !($avg_score > $best_score)}"; then
            best_score="$avg_score"
            best_val="$candidate"
        fi
    done
    
    # Create directory with error checking
    if ! mkdir -p "$(dirname "$best_file")"; then
        log_error "Could not create directory: $(dirname "$best_file")"
        return 1
    fi
    
    # Write file with verification
    if ! echo "$best_val" > "$best_file"; then
        log_error "Error writing to: $best_file"
        return 1
    fi
    
    return 0
}

# Description: Compute quality score from ping metrics (avg RTT, jitter/variance, loss).
# Usage: extract_scores "<avg> <jitter> <loss>"
extract_scores() {
    local current_ping=$(echo "$1" | awk '{print $1}')
    local current_jitter=$(echo "$1" | awk '{print $2}')
    local current_loss=$(echo "$1" | awk '{print $3}')

    # Locale guard: allow decimals written with comma (e.g. 37,182)
    current_ping=$(echo "$current_ping" | tr ',' '.')
    current_jitter=$(echo "$current_jitter" | tr ',' '.')
    current_loss=$(echo "$current_loss" | tr ',' '.')
    log_info "====================== extract_scores =========================" >> "$trace_log"
    log_info "props before verify: current_ping: $current_ping | current_jitter: $current_jitter | current_loss: $current_loss " >> "$trace_log"
    
    
    # Validation and defaulting
    [ -z "$current_ping" ] && current_ping="-1"
    [ -z "$current_jitter" ] && current_jitter="-1"
    [ -z "$current_loss" ] && current_loss="100"
    log_info "props after verify: current_ping: $current_ping | current_jitter: $current_jitter | current_loss: $current_loss " >> "$trace_log"

    # Score calculation with numeric validation
    if ! echo "$current_ping" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || \
       ! echo "$current_jitter" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || \
       ! echo "$current_loss" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        echo "0"
        return 1
    fi

    # Safe calculation with awk
    echo "$current_ping $current_jitter $current_loss" | awk '
    {
        p = $1; j = $2; l = $3
        
        if (p <= 0 || p >= 9999 || l >= 100) {
            print "0"
            exit
        }
        
        # Simplified formula
        base = 100 - (p / 2)
        score = base - (j * 0.5) - (l * 0.8)
        
        if (score < 1) score = 1
        if (score > 100) score = 100
        
        printf "%.2f", score
    }'
}

# Description: Resolve provider/dns/ping from SIM MCC/MNC JSON or fallback, apply DNS.
# Usage: configure_network
configure_network() {
    local country_code mcc_raw mnc_raw mcc mnc json_file cache_file cache_ok
    local raw provider dns_list ping dns_json

    country_code=$(getprop gsm.sim.operator.iso-country | tr '[:upper:]' '[:lower:]')
    [ -z "$country_code" ] && country_code="unknow"

    mcc_raw=$(getprop debug.tracing.mcc | tr -d '[]')
    mnc_raw=$(getprop debug.tracing.mnc | tr -d '[]')

    if echo "$mcc_raw" | grep -qE '^[0-9]+$'; then
        mcc="$mcc_raw"
    else
        mcc="000"
    fi

    if echo "$mnc_raw" | grep -qE '^[0-9]+$'; then
        mnc=$(printf "%03d" "$mnc_raw")
    else
        mnc="000"
    fi

    json_file="$data_dir/countries/${country_code}.json"

    if [ "$mcc" = "000" ] && [ "$mnc" = "000" ]; then
        log_warning "MCC/MNC not detected, using default configuration" | tee -a /sdcard/errors.log
        json_file="$fallback_json"
    fi

    cache_file="$cache_dir/${mcc}_${mnc}.conf"
    log_info "====================== configure_network =========================" >> "$trace_log"
    log_info "country_code: $country_code | mcc: $mcc | mnc: $mnc | json_file: $json_file | cache_file: $cache_file" >> "$trace_log"
    
    if [ -z "$mcc" ] || [ -z "$mnc" ]; then
        log_warning "MCC/MNC not detected, using default configuration" | tee -a /sdcard/errors.log
        mcc="000"
        mnc="000"
        json_file="$fallback_json"
        cache_file="$cache_dir/${mcc}_${mnc}.conf"
    fi

    # Hardcore validations
    [ -f "$jqbin" ] || { log_error "jq not found"; return 1; }
    [ -x "$jqbin" ] || { log_error "jq is not executable"; return 1; }
    [ -f "$json_file" ] || json_file="$fallback_json"
    [ -f "$json_file" ] || { log_error "JSON not found"; return 1; }
    "$jqbin" empty "$json_file" || { log_error "Invalid JSON"; return 1; }
    head -c3 "$json_file" | grep -q $'\xEF\xBB\xBF' && tail -c +4 "$json_file" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file" # prevenir BOM

    if [ -f "$cache_file" ] && \
       grep -q "^PROVIDER=" "$cache_file" && \
       grep -q "^DNS_LIST=" "$cache_file" && \
       grep -q "^PING=" "$cache_file"; then
        cache_ok=1
    else
        cache_ok=0
    fi

    if [ "$cache_ok" -eq 1 ]; then
        . "$cache_file"
    else
        raw=$("$jqbin" -n --slurpfile data "$json_file" \
            --arg mcc "$mcc" --arg mnc "$mnc" '
                ($data[0] // {}) as $root |
                (try ($root.entries // []) catch []) as $ents |
                ($ents[] | select((.mcc // 0) == ($mcc | tonumber) and (.mnc // "") == $mnc)) //
                (try $root.default catch {})
        ')

        log_info "Network configuration obtained (raw): $raw" >> "$trace_log"

        if [ -z "$raw" ] || [ "$raw" = "null" ]; then
            raw=$(cat "$fallback_json")
            log_info "Using fallback_json because raw is empty" >> "$trace_log"
        fi

        if ! echo "$raw" | "$jqbin" -e 'type == "object" and has("provider")' >/dev/null; then
            echo "[ERROR] Invalid JSON or missing 'provider' key" >> "/sdcard/errors.log"
            return 1
        fi

        provider=$(echo "$raw" | "$jqbin" -r '.provider // "Unknown"')
        dns_list=$(echo "$raw" | "$jqbin" -r '.dns[]?' | paste -sd " ")
        ping=$(echo "$raw" | "$jqbin" -r '.ping // "8.8.8.8"')

        log_info "Network configuration obtained (ping): $ping" >> "$trace_log"
        log_info "Network configuration obtained (dns_list): $dns_list" >> "$trace_log"
        log_info "Network configuration obtained (provider): $provider" >> "$trace_log"

        [ -z "$dns_list" ] && dns_list="8.8.8.8 1.1.1.1"
        [ -z "$ping" ] && ping="8.8.8.8"

        cat > "$cache_file" <<-EOF
PROVIDER='$provider'
DNS_LIST='$dns_list'
PING='$ping'
EOF
        . "$cache_file"
    fi

            [ -z "$DNS_LIST" ] && DNS_LIST="8.8.8.8 1.1.1.1"
            [ -z "$PING" ] && PING="8.8.8.8"
    # TODO: [PENDING] Add ndc binary compatibility strategy for multiple architectures TODO:
    for iface in $($ipbin -o link show | awk -F': ' '{print $2}' | grep -E 'rmnet|wlan|eth|ccmni|usb'); do
        log_info "Configuring DNS on interface: $iface" >> "$trace_log"
      ndc resolver setifacedns "$iface" "" $DNS_LIST >/dev/null 2>&1
    done

    dns_json=$(printf '%s\n' $DNS_LIST | "$jqbin" -R . | "$jqbin" -s .)
    log_info "dns_json: $dns_json" >> "$trace_log"

    "$jqbin" -n \
      --arg provider "$PROVIDER" \
      --argjson dns "$dns_json" \
      --arg ping "$PING" \
      '{provider: $provider, dns: $dns, ping: $ping}'
}

# Description: Calibrate LTE/LTEA/5G properties when mobile path is active.
# Usage: calibrate_secondary_network_settings <delay_seconds> <cache_dir>
calibrate_secondary_network_settings() {
    delay=$1
    CACHE_DIR="$2"
    index=1

    log_info "====================== calibrate_secondary_network_settings =========================" >> "$trace_log"

    for prop in $NET_OTHERS_PROPERTIES_KEYS; do
        (
            case "$prop" in
                "ro.ril.lte.category")
                    vals="$NET_VAL_LTE"
                    ;;
                "ro.ril.ltea.category")
                    vals="$NET_VAL_LTEA"
                    ;;
                "ro.ril.nr5g.category")
                    vals="$NET_VAL_5G"
                    ;;
                *)
                    vals="9" # Default fallback value
                    ;;
            esac
            log_info "Calibrating $prop with values: $vals" >> "$trace_log"
            calibrate_property "$prop" "$vals" "$delay" "$CACHE_DIR/$prop.best"
        ) &
    done
    wait

    # Export results
    for prop in $NET_OTHERS_PROPERTIES_KEYS; do
        best_file="$CACHE_DIR/$prop.best"
        if [ -f "$best_file" ]; then
            best_val=$(cat "$best_file")
            log_info "Best value for $prop: $best_val" >> "$trace_log"
            exp_name=$(echo "$prop" | tr '.' '_')
            export "BEST_${exp_name}=$best_val"
        else
            log_info "Best value for $prop: (not found)" >> "$trace_log"
        fi
    done
}

# Description: Apply a property candidate and measure connectivity quality via ping.
# Usage: test_configuration <property> <candidate> <delay_seconds>
test_configuration() {
    log_info "====================== test_configuration =========================" >> "$trace_log"
    local property="$1" 
    local candidate="$2" 
    local delay="$3"

    log_info "property: $property | candidate: $candidate | delay: $delay" >> "$trace_log"


    [ -z "${TEST_IP:-}" ] && { echo "9999 9999 100"; return 3; }

    resetprop "$property" "$candidate" >/dev/null 2>&1 || { echo "9999 9999 100"; return 1; }
    sleep 1

    # Warm-up pings to avoid skewed first samples
    $PING_BIN -c 3 -W 1 "$TEST_IP" >/dev/null 2>&1

    # Execute ping with consistent format
    # Binary -c 10 (10 packets), -i 0.5 (interval 500ms), -W 1 

    [ -z "$ping_count" ] && ping_count="7"

    case "$ping_count" in
        ''|*[!0-9]*)
        ping_count=7
        ;;
    esac
    local output 
    output="$($PING_BIN -c "$ping_count" -i 0.5 -W 1 "$TEST_IP" 2>&1)"
    [ $? -ne 0 ] && { echo "9999 9999 100"; return 2; }

    log_debug "Ping output: $output" >> "$trace_log"

    parse_ping "$output"
}

# Description: Parse ping output to extract avg RTT, jitter (mdev), variance (max-min), and loss.
# Usage: parse_ping "$(ping ... output)"
parse_ping() {
    local ping_output="$1"
    log_info "====================== parse_ping =========================" >> "$trace_log"
    log_info "Raw ping output: $ping_output" >> "$trace_log"

    # Keep outputs consistent with extract_scores(): "<avg_ms> <jitter_ms> <loss_percent>"
    # Defaults represent a failed/invalid measurement.
    if [ -z "$ping_output" ]; then
        echo "9999 9999 100"
        return 1
    fi

    local avg_ping="9999"
    local jitter="9999"
    local packet_loss="100"

    # Extract packet loss percentage (works for: "0% packet loss" / Spanish variants)
    packet_loss=$(echo "$ping_output" | awk '
        /packet loss|perdida|p[eé]rdida/ {
            for (i=1; i<=NF; i++) {
                if ($i ~ /^[0-9]+(\.[0-9]+)?%$/) {
                    gsub(/%/, "", $i)
                    print $i
                    found=1
                    exit
                }
            }
        }
        END {
            if (!found) print "100"
        }
    ')
    packet_loss=$(echo "$packet_loss" | awk '{gsub(/[^0-9.]/, ""); print}')
    [ -z "$packet_loss" ] && packet_loss="100"
    log_info "packet_loss: $packet_loss" >> "$trace_log"

    # Extract RTT stats line (supports multiple ping variants/locales)
    local rtt_line stats
    rtt_line=$(echo "$ping_output" | awk '
        /rtt min\/avg\/max\/mdev/ {print; exit}
        /round-trip min\/avg\/max/ {print; exit}
        /min\/avg\/max\/stddev/ {print; exit}
    ')
    log_info "rtt_line: $rtt_line" >> "$trace_log"

    if [ -n "$rtt_line" ]; then
        stats=$(echo "$rtt_line" | awk -F'=' 'NF>=2 {gsub(/^[ \t]+/, "", $2); print $2}')
        # stats should look like: min/avg/max/mdev ms or min/avg/max/stddev ms
        avg_ping=$(echo "$stats" | awk -F'/' '{print $2}')
        jitter=$(echo "$stats" | awk -F'/' '{print $4}')

        # Locale guard: allow decimals written with comma (37,182)
        avg_ping=$(echo "$avg_ping" | tr ',' '.' | awk '{gsub(/[^0-9.]/, ""); print}')
        jitter=$(echo "$jitter" | tr ',' '.' | awk '{gsub(/[^0-9.]/, ""); print}')

        # Some ping variants output only min/avg/max (no 4th field); treat jitter as 0
        [ -z "$jitter" ] && jitter="0"
        [ -z "$avg_ping" ] && avg_ping="9999"
    fi

    log_info "avg_ping: $avg_ping | jitter: $jitter | packet_loss: $packet_loss" >> "$trace_log"

    echo "$avg_ping $jitter $packet_loss"
}