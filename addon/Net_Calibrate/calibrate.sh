#!/system/bin/sh
trace_log="/sdcard/trace_log.log"
NET_PROPERTIES_KEYS="ro.ril.hsupa.category ro.ril.hsdpa.category" # Prioridad, para [subida y bajada] WIFI
NET_OTHERS_PROPERTIES_KEYS="ro.ril.lte.category ro.ril.ltea.category ro.ril.nr5g.category" # Prioridad, para [LTE, LTEA, 5G] Datos
NET_VAL_HSUPA="5 6 7 8 9 10 11 12 13 18" # Testeo de valores para mayor subida
NET_VAL_HSDPA="9 12 15 18 21 34 36 38 41" # Testeo de valores para mayor bajada
NET_VAL_LTE="5 6 7 8 9 10 11 12 13" # Testeo de valores para tecnologia de datos lte
NET_VAL_LTEA="5 6 7 8 9 10 11 12 13" # Testeo de valores para tecnologia de datos ltea
NET_VAL_5G="1 2 3 4 5" # Testeo de valores para tecnologia de datos 5G
NETMETER_FILE="$NEWMODPATH/logs/kitsunping.log"
CACHE_DIR_cln="$NEWMODPATH/cache"
jqbin="$NEWMODPATH/addon/jq/arm64/jq"
ipbin="$NEWMODPATH/addon/ip/ip"
data_dir="$NEWMODPATH/addon/Net_Calibrate/data"
fallback_json="$data_dir/unknow.json"
cache_dir="$data_dir/cache"

check_and_detect_commands() {
    if [ -n "$PING_BIN" ]; then
        log_debug "PING_BIN ya seteado en: $PING_BIN"
    else 
        log_info "====================== check_and_detect_commands =========================" >> "$trace_log"
        local missing=0
        # Comandos esenciales
        for cmd in ip ndc resetprop awk; do
            if ! command_exists "$cmd"; then
                log_error "Comando requerido '$cmd' no encontrado"
                missing=$((missing + 1))
            fi
        done

        if [ $missing -gt 0 ]; then
            log_error "Faltan $missing dependencias esenciales"
            return 1
        fi

        # Buscar ping
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

        # Verificar si ping es funcional
        if ! "$PING_BIN" -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
            log_error "Ping available but not functional (check permissions, SELinux, network)"
            return 1
        fi

        export PING_BIN
    fi
    return 0
}

calibrate_network_settings() {
    if [ -z "$1" ] || ! echo "$1" | grep -Eq '^[0-9]+$' || [ "$1" -lt 1 ]; then
        log_error "calibrate_network_settings <delay_segundos>" >&2
        return 1
    fi

    log_info "====================== calibrate_network_settings =========================" >> "$trace_log" 
    check_and_detect_commands

    local delay=$1 # segundos
    local config_json dns1 dns2 TEST_IP # variables locales sin asiganar

    log_info "====================== calibrate_property =========================" >> "$trace_log"
    log_info "Execution trace, delay: $delay seconds" >> "$trace_log"
    config_json=$(configure_network) # obtener configuracion de red
    log_info "====================== calibrate_property =========================" >> "$trace_log"
    log_info "Network configuration obtained (config_json): $config_json" >> "$trace_log"

    echo "$config_json" | "$jqbin" -e 'type == "object" and has("provider") and has("dns") and has("ping")' >/dev/null || {
        log_info "[ERROR] config_json invalido o incompleto:" >> "$trace_log"
        log_info "$config_json" >> "$trace_log"
        return 1
    }

    dns1=$(echo "$config_json" | "$jqbin" -r '.dns[0] // "8.8.8.8"')
    dns2=$(echo "$config_json" | "$jqbin" -r '.dns[1] // "8.8.4.4"')
    TEST_IP=$(echo "$config_json" | "$jqbin" -r '.ping // "8.8.8.8"')

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
        # Leemos el mejor valor desde archivos TMPDIR/*.best
        local best_file="$CACHE_DIR_cln/$prop.best"
        local best_val="1"
        [ -f "$best_file" ] && best_val=$(cat "$best_file")
        log_info "Exporting properties: [BEST_${prop//./_}=$best_val]" >> "$trace_log"
        export "BEST_${prop//./_}=$best_val"
    done

    #local current_iface=$($ipbin route | grep default | awk '{print $5}' | head -n1)
#
    #if echo "$current_iface" | grep -qiE 'rmnet|ccmni'; then
    #    log_info "Modo Movil-datos: Calibracion extendida [detalle:${current_iface}]" >> "$trace_log"
    #    calibrate_secondary_network_settings $delay "$CACHE_DIR_cln"
    #else
    #    log_info "Modo WIFI: Calibrando solo HSUPA/HSDPA [detalle:${current_iface}]" >> "$trace_log"
    #fi


    local current_iface=$(su -c "$ipbin route show 2>/dev/null | grep -v linkdown | grep -E 'rmnet|wlan' | awk '{print \$5}' | head -n1")

    if [ -z "$current_iface" ]; then
        current_iface=$(su -c "cat /proc/net/dev 2>/dev/null | awk 'NR>2 && (\$2 > 1000 || \$10 > 1000) {print \$1; exit}' | tr -d :")
    fi

    
    if echo "$current_iface" | grep -qi 'rmnet'; then
        log_info "Mobile/data mode: extended calibration [detail:${current_iface}]" >> "$trace_log"
        calibrate_secondary_network_settings $delay "$CACHE_DIR_cln"
    else
        log_info "Wi-Fi/other mode: calibrating only HSUPA/HSDPA [detail:${current_iface}]" >> "$trace_log"
    fi

    log_info "====================== calibrate_network_settings =========================" >> "$trace_log"
    echo "BEST_ro_ril_hsupa_category=$BEST_ro_ril_hsupa_category"
    echo "BEST_ro_ril_hsdpa_category=$BEST_ro_ril_hsdpa_category"
    echo "BEST_ro_ril_lte_category=$BEST_ro_ril_lte_category"
    echo "BEST_ro_ril_ltea_category=$BEST_ro_ril_ltea_category"
    echo "BEST_ro_ril_nr5g_category=$BEST_ro_ril_nr5g_category"
}

get_values_for_prop() {
    local index="$1"
    log_info "====================== get_values_for_prop =========================" >> "$trace_log"
    log_info "index: $index" >> "$trace_log"

    # Almacenamos y obtenemos el offset inicial para la propiedad actual (ej. 0)
    local start=$(echo "$PROP_OFFSETS" | cut -d' ' -f$index)
    log_info "PROP_OFFSETS: $PROP_OFFSETS" >> "$trace_log"
    log_info "start: $start" >> "$trace_log"

    # Almacenamos y obtenemos el siguiente offset (si existe) para determinar el rango de valores  (ej. 6)
    local end=$(echo "$PROP_OFFSETS" | cut -d' ' -f$((index + 1)) 2>/dev/null)
    log_info "PROP_OFFSETS: $PROP_OFFSETS" >> "$trace_log"
    log_info "end: $end" >> "$trace_log"

    # Calcula el numero total de valores disponibles en NET_PROPERTIES_VALUES
    local total=$(echo "$NET_PROPERTIES_VALUES" | wc -w)
    log_info "PROP_OFFSETS: $NET_PROPERTIES_VALUES" >> "$trace_log"
    log_info "end: $total" >> "$trace_log"

    # Extrae los valores correspondientes a la propiedad actual
    if [ -z "$end" ]; then
        # Si no hay un siguiente offset, toma todos los valores desde el offset actual hasta el final
        echo "$NET_PROPERTIES_VALUES" | cut -d' ' -f$((start + 1))-"$total"
    else
        # Si hay un siguiente offset, toma los valores entre el offset actual y el siguiente
        # └── es decir que toma los del: 0 al 6
        echo "$NET_PROPERTIES_VALUES" | cut -d' ' -f$((start + 1))-"$end"
    fi
}

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
    # Verificar permisos de escritura primero
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
    
    # Crear directorio con verificación de errores
    if ! mkdir -p "$(dirname "$best_file")"; then
        log_error "Could not create directory: $(dirname "$best_file")"
        return 1
    fi
    
    # Escribir archivo con verificación
    if ! echo "$best_val" > "$best_file"; then
        log_error "Error writing to: $best_file"
        return 1
    fi
    
    return 0
}

extract_scores() {
    local current_ping=$(echo "$1" | awk '{print $1}')
    local current_jitter=$(echo "$1" | awk '{print $2}')
    local current_loss=$(echo "$1" | awk '{print $3}')
    log_info "====================== extract_scores =========================" >> "$trace_log"
    log_info "props before verify: current_ping: $current_ping | current_jitter: $current_jitter | current_loss: $current_loss " >> "$trace_log"
    
    
    # Validación básica
    [ -z "$current_ping" ] && current_ping="-1"
    [ -z "$current_jitter" ] && current_jitter="-1"
    [ -z "$current_loss" ] && current_loss="100"
    log_info "props after verify: current_ping: $current_ping | current_jitter: $current_jitter | current_loss: $current_loss " >> "$trace_log"

    # Cálculo del score con validación numérica
    if ! echo "$current_ping" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || \
       ! echo "$current_jitter" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || \
       ! echo "$current_loss" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        echo "0"
        return 1
    fi

    # Cálculo seguro con awk
    echo "$current_ping $current_jitter $current_loss" | awk '
    {
        p = $1; j = $2; l = $3
        
        if (p <= 0 || p >= 9999 || l >= 100) {
            print "0"
            exit
        }
        
        # Fórmula simplificada
        base = 100 - (p / 2)
        score = base - (j * 0.5) - (l * 0.8)
        
        if (score < 1) score = 1
        if (score > 100) score = 100
        
        printf "%.2f", score
    }'
}


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

    # Comprobacion de locos para evitar posibles errores comunes y poco comunes
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

        log_info "Configuracion de red obtenida (ping): $ping" >> "$trace_log"
        log_info "Configuracion de red obtenida (dns_list): $dns_list" >> "$trace_log"
        log_info "Configuracion de red obtenida (provider): $provider" >> "$trace_log"

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

    for iface in $($ipbin -o link show | awk -F': ' '{print $2}' | grep -E 'rmnet|wlan|eth|ccmni|usb'); do
        log_info "Configurando DNS en interfaz: $iface" >> "$trace_log"
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


calibrate_secondary_network_settings() {
    local delay=$1
    local CACHE_DIR="$2"
    local index=1

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
                    vals="9" # Valor por defecto
                    ;;
            esac
            log_info "Calibrando $prop con valores: $vals" >> "$trace_log"
            calibrate_property "$prop" "$vals" "$delay" "$CACHE_DIR/$prop.best"
        ) &
    done
    wait

    # Exportar resultados
    for prop in $NET_OTHERS_PROPERTIES_KEYS; do
        local best_file="$CACHE_DIR/$prop.best"
        log_info "Mejor valor para $prop: $(cat "$best_file")" >> "$trace_log"
        [ -f "$best_file" ] && export "BEST_${prop//./_}=$(cat "$best_file")"
    done
}


guardar_cache() {
    local contenido="$1"
    local archivo="$2"
    echo "$contenido" >> "$archivo"
}


test_configuration() {
    log_info "====================== test_configuration =========================" >> "$trace_log"
    local property="$1" 
    local candidate="$2" 
    local delay="$3"

    log_info "property: $property | candidate: $candidate | delay: $delay" >> "$trace_log"


    [ -z "${TEST_IP:-}" ] && { echo "9999 9999 100"; return 3; }

    resetprop "$property" "$candidate" >/dev/null 2>&1 || { echo "9999 9999 100"; return 1; }
    sleep 1

    # Ejecutar ping con formato consistente
    # Binario -c 10 (10 paquetes), -i 0.5 (intervalo 500ms), -W 0.9 (timeout por paquete) 
    output=$($PING_BIN -c "$delay" -i 0.5 -W 0.9 "$TEST_IP" 2>&1)
    [ $? -ne 0 ] && { echo "9999 9999 100"; return 2; }

    log_info "Ping output: $output" >> "$trace_log"

    parse_ping "$output"
}


parse_ping() {
    local input="$1"
    log_info "====================== parse_ping =========================" >> "$trace_log"
    if [ -z "$input" ]; then
        echo "-1 -1 100"
        return 1
    fi

    # Variables por defecto
    local avg_ping="-1"
    local jitter="-1"
    local packet_loss="100"

    # Extraer pérdida de paquetes
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

    # Extraer estadísticas RTT
    local rtt_line
    rtt_line=$(echo "$input" | grep -E "rtt min/avg/max/mdev|round-trip min/avg/max|tiempo mínimo/máximo/promedio")
    log_info "rtt_line: $rtt_line" >> "$trace_log"
    if [ -n "$rtt_line" ]; then
        avg_ping=$(echo "$rtt_line" | awk -F'=' '{print $2}' | awk -F'/' '{print $2}')
        jitter=$(echo "$rtt_line" | awk -F'=' '{print $2}' | awk -F'/' '{print $4}' | awk '{print $1}')
    fi

    [ -z "$avg_ping" ] && avg_ping="-1"
    [ -z "$jitter" ] && jitter="-1"
    [ -z "$packet_loss" ] && packet_loss="100"

    echo "${avg_ping} ${jitter} ${packet_loss}"
}