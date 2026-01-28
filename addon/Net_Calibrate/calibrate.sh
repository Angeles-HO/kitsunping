#!/system/bin/sh
# Net Calibrate.sh Script
# Version: 4.87
# Description: This script calibrates network properties for optimal performance.
# Status: Archived - 26/01/2026
trace_log="/sdcard/trace_log.log"
NET_PROPERTIES_KEYS="ro.ril.hsupa.category ro.ril.hsdpa.category" # Priority, for [upload and download] WIFI
NET_OTHERS_PROPERTIES_KEYS="ro.ril.lte.category ro.ril.ltea.category ro.ril.nr5g.category" # Priority, for [LTE, LTEA, 5G] Data
NET_VAL_HSUPA="5 6 7 8 9 10 11 12 13 18" # Testing values for higher upload
NET_VAL_HSDPA="9 12 15 18 21 34 36 38 41" # Testing values for higher download
NET_VAL_LTE="5 6 7 8 9 10 11 12 13" # Testing values for LTE data technology
NET_VAL_LTEA="5 6 7 8 9 10 11 12 13" # Testing values for LTEA data technology
NET_VAL_5G="1 2 3 4 5" # Testing values for 5G data technology
NETMETER_FILE="$NEWMODPATH/logs/kitsunping.log"
CACHE_DIR_cln="$NEWMODPATH/cache"
jqbin="$NEWMODPATH/addon/jq/arm64/jq"
ipbin="$NEWMODPATH/addon/ip/ip" # TODO: search a another binary, this depends of libandroid-support.so
data_dir="$NEWMODPATH/addon/Net_Calibrate/data"
fallback_json="$data_dir/unknown.json"
cache_dir="$data_dir/cache"
CALIBRATE_STATE_RUN="$NEWMODPATH/cache/calibrate.state"
CALIBRATE_LAST_RUN="$NEWMODPATH/cache/calibrate.ts"

date +%s > "$CALIBRATE_LAST_RUN" 2>/dev/null
echo "running" > "$CALIBRATE_STATE_RUN"

# Description: Ensure core binaries (ping, resetprop, ip, ndc, awk) exist and that ping works.
# Usage: check_and_detect_commands
check_and_detect_commands() {
    if [ -n "$PING_BIN" ]; then
        log_debug "PING_BIN already set: $PING_BIN"
    else 
        log_info "====================== check_and_detect_commands =========================" >> "$trace_log"
        local missing=0
        
        for cmd in ip ndc resetprop awk; do
            if ! command_exists "$cmd"; then
                log_error "Required command '$cmd' not found"
                missing=$((missing + 1))
            fi
        done

        if [ $missing -gt 0 ]; then
            log_error "Missing $missing essential dependencies, cannot proceed"
            return 1
        fi

        # Search for ping binary
        PING_BIN=$(command -v ping 2>/dev/null)
        if [ -z "$PING_BIN" ] || [ ! -x "$PING_BIN" ]; then
            log_warning "Ping not found in PATH, scanning common locations..."
            for path in /system/bin /system/xbin /vendor/bin /data/adb/magisk /data/data/com.termux/files/usr/bin; do
                if [ -x "$path/ping" ]; then
                    PING_BIN="$path/ping"
                    log_warning "Ping binary found at: $PING_BIN" >> "$trace_log"
                    log_warning "Using detected ping binary..." >> "$trace_log"
                    break
                fi
                log_warning "Ping not found in: $path" >> "$trace_log"
            done
        fi

        if [ -z "$PING_BIN" ]; then
            log_error "Ping not available on the system"
            return 1
        fi

        # Verify if ping is functional
        # If ping fails, try to detect whether we're in an install/context where the
        # daemon is not running (e.g. a module 'running' installation). In that case
        # abort calibration quietly (return 0). Otherwise treat as fatal and return 1.

        # TODO: need more logs for depuration and calibration
        if ! "$PING_BIN" -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
            # Check whether the daemon is already running (normal operation) using pidfile
            # Prefer the same singleton check used by daemon.sh (pidfile at $MODDIR/cache/daemon.pid)
            local old_pid
            for pidfile in "${NEWMODPATH:-}/cache/daemon.pid" "${MODDIR:-}/cache/daemon.pid"; do
                if [ -f "$pidfile" ]; then
                    old_pid=$(cat "$pidfile" 2>/dev/null)
                    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
                        log_error "Ping available but not functional (check permissions, SELinux, network)"
                        log_error "Connectivity test failed using ping at: $PING_BIN while daemon is running (PID=$old_pid); aborting calibration."
                        log_error "Please verify network connectivity and permissions."
                        return 1
                    else
                        # Stale pidfile: remove
                        rm -f "$pidfile" 2>/dev/null
                    fi
                fi
            done

            # Fallback: try to detect running process by name if no pidfile found
            if pgrep -f '[k]itsunping' >/dev/null 2>&1; then
                log_error "Ping available but not functional (check permissions, SELinux, network)"
                log_error "Connectivity test failed using ping at: $PING_BIN while daemon process detected; aborting calibration."
                log_error "Please verify network connectivity and permissions."
                return 1
            fi

            # Detect common locations that indicate a module installation or "runin" workflow
            # If such an installation is in progress, abort calibration without treating as error
            if [ -d "/data/adb/modules/runin" ] || [ -d "/data/adb/modules/kitsunping" ] || [ -f "/data/adb/modules/.installed_runin" ]; then
                log_info "Daemon not running and 'runin' / module-install detected; aborting calibration without error."
                return 0
            fi

            # Default: treat as error
            log_error "Ping available but not functional (check permissions, SELinux, network)"
            log_error "Connectivity test failed using ping at: $PING_BIN, cannot proceed, please check wifi/data status."
            log_error "Please verify network connectivity and permissions."
            return 1
        fi

        export PING_BIN
    fi
    return 0
}

# Main function to calibrate network settings
# Description: Orchestrate full calibration flow for radio properties using ping-based scoring.
# Usage: calibrate_network_settings <delay_seconds>
calibrate_network_settings() {
    if [ -z "$1" ] || ! echo "$1" | grep -Eq '^[0-9]+$' || [ "$1" -lt 1 ]; then
        log_error "calibrate_network_settings <delay_seconds>" >&2
        return 1
    fi

    log_info "====================== calibrate_network_settings =========================" >> "$trace_log" 
    check_and_detect_commands

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

    dns1=$(echo "$config_json" | "$jqbin" -r '.dns[0] // "8.8.8.8"')
    dns2=$(echo "$config_json" | "$jqbin" -r '.dns[1] // "8.8.4.4"')
    PING_VAL=$(echo "$config_json" | "$jqbin" -r '.ping // "8.8.8.8"')

    # If JSON provides an IP for ping, probe both the IP and a geo-aware
    # hostname (so DNS resolution uses the provider DNS we just configured)
    # and choose the target with lower RTT.
    country_code=$(getprop gsm.sim.operator.iso-country 2>/dev/null | tr '[:upper:]' '[:lower:]')
    [ -z "$country_code" ] && country_code="global"

    if echo "$PING_VAL" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
        ORIGINAL_IP="$PING_VAL"
        HOSTNAME="${country_code}.pool.ntp.org"
        log_info "Ping field is IP; probing ORIGINAL_IP=$ORIGINAL_IP and HOSTNAME=$HOSTNAME" >> "$trace_log"

        # Probe ORIGINAL IP
        out_ip=$($PING_BIN -c 3 -W 2 "$ORIGINAL_IP" 2>&1 || true)
        avg_ip=$(parse_ping "$out_ip" | awk '{print $1}')

        # Probe HOSTNAME (this exercises DNS configured above)
        out_host=$($PING_BIN -c 3 -W 2 "$HOSTNAME" 2>&1 || true)
        avg_host=$(parse_ping "$out_host" | awk '{print $1}')

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
    # TODO: Need add a ndc binary for many architectures and compatibility
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
    # Binary -c 10 (10 packets), -i 0.5 (interval 500ms), -W 0.9 (timeout per packet) 
    # TODO: delete $delay and user less time than 10, can be 5, 10 is good but slow
    
    local output=$($PING_BIN -c "$delay" -i 0.5 -W 0.9 "$TEST_IP" 2>&1)
    [ $? -ne 0 ] && { echo "9999 9999 100"; return 2; }

    log_info "Ping output: $output" >> "$trace_log"

    parse_ping "$output"
}

# Description: Parse ping output to extract avg RTT, jitter (mdev), variance (max-min), and loss.
# Usage: parse_ping "$(ping ... output)"
parse_ping() {
    local input="$1"
    log_info "====================== parse_ping =========================" >> "$trace_log"
    if [ -z "$input" ]; then
        echo "-1 -1 100"
        return 1
    fi

    # Default variables
    local avg_ping="-1"
    local jitter="-1"
    local min_ping="-1"
    local max_ping="-1"
    local variance="-1"
    local packet_loss="100"

    # Extract packet loss
    packet_loss=$(echo "$input" | awk '
        /packet loss|perdida/ {
            for (i=1; i<=NF; i++) {
                if ($i ~ /^[0-9]+%$/) {
                    gsub(/%/, "", $i)
                    print $i
                    exit
                }
            }
        }
        END { print "0" }')
    log_info "packet_loss: $packet_loss" >> "$trace_log"

    # Extract RTT statistics
    local rtt_line
    rtt_line=$(echo "$input" | grep -E "rtt min/avg/max/mdev|round-trip min/avg/max|tiempo mínimo/máximo/promedio")
    log_info "rtt_line: $rtt_line" >> "$trace_log"
    if [ -n "$rtt_line" ]; then
        local rtt_stats
        # Normalize spacing to avoid parsing failures when there are extra blanks
        rtt_stats=$(echo "$rtt_line" | awk -F'=' '{print $2}' | tr -s ' ' | sed 's/^ *//')
        min_ping=$(echo "$rtt_stats" | awk -F'/' '{print $1}')
        avg_ping=$(echo "$rtt_stats" | awk -F'/' '{print $2}')
        max_ping=$(echo "$rtt_stats" | awk -F'/' '{print $3}')
        jitter=$(echo "$rtt_stats" | awk -F'/' '{print $4}' | awk '{print $1}')
    fi

    [ -z "$avg_ping" ] && avg_ping="-1"
    [ -z "$jitter" ] && jitter="-1"
    [ -z "$min_ping" ] && min_ping="-1"
    [ -z "$max_ping" ] && max_ping="-1"
    [ -z "$packet_loss" ] && packet_loss="100"

    if echo "$min_ping" | grep -Eq '^[0-9]+(\.[0-9]+)?$' && \
       echo "$max_ping" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        variance=$(awk "BEGIN {print $max_ping - $min_ping}")
    fi

    # Adjust jitter penalizing more when variance (max-min) is greater
    local adjusted_jitter="$jitter"
    if echo "$variance" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        if ! echo "$adjusted_jitter" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || \
           awk "BEGIN {exit !($variance > $adjusted_jitter)}"; then
            adjusted_jitter="$variance"
        fi
    fi

    log_info "rtt_min: $min_ping | rtt_max: $max_ping | variance: $variance | jitter_final: $adjusted_jitter" >> "$trace_log"

    echo "${avg_ping} ${adjusted_jitter} ${packet_loss}"
}