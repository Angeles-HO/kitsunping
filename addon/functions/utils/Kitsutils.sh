#!/system/bin/sh
# Funciones utiles para acortar el codigo y mejorar la legibilidad
# NOTE: This file is commonly *sourced*. When sourced, $0 is the caller, so
# avoid clobbering MODDIR/NEWMODPATH based on an assumed directory layout.

if [ -z "${NEWMODPATH:-}" ] || [ ! -d "${NEWMODPATH:-/}" ]; then
    if [ -n "${MODDIR:-}" ] && [ -d "${MODDIR:-/}" ]; then
        NEWMODPATH="$MODDIR"
    else
        case "$0" in
            */addon/*) NEWMODPATH="${0%%/addon/*}" ;;
            *) NEWMODPATH="${0%/*}" ;;
        esac
    fi
fi

: "${MODDIR:=${NEWMODPATH}}"

verify_complemento() {
    local complemento="$1"

    if [ -f "$NEWMODPATH/$complemento" ]; then
        . "$NEWMODPATH/$complemento" || {
            echo "[ERROR] Could not load complemento: $complemento"
            exit 1
        }
    else
        echo "[ERROR] Complemento not found: $complemento"
        exit 1
    fi
}

prop_or_default() {
    local val="$(getprop "$1")"
  [ -n "$val" ] && echo "$val" || echo "$2"
}
 
## Set permissions function
## Usage: set_permissions_module <modpath> [log_file]
##  modpath: Path to the module installation directory
set_permissions_module() {
    modpath="$1"
    log_file="$2"
    # Optional third parameter: if set to "1" will attempt a last-resort chcon when no restorecon
    # Usage: set_permissions_module <modpath> [log_file] [allow_chcon_last_resort]
    last_resort_chcon="${3:-0}"
    [ -z "$modpath" ] && { [ -n "$log_file" ] && echo "[WARN] modpath vacio" >> "$log_file"; return 1; }
    [ ! -d "$modpath" ] && { [ -n "$log_file" ] && echo "[WARN] $modpath no existe" >> "$log_file"; return 1; }

    # Preferir las funciones de Magisk si están disponibles (aplican SELinux context por defecto)
    if command -v set_perm_recursive >/dev/null 2>&1; then
        set_perm_recursive "$modpath" 0 0 0755 0644
        for d in \
            "$modpath/addon/jq" \
            "$modpath/addon/bc" \
            "$modpath/addon/ip" \
            "$modpath/addon/ping" \
            "$modpath/addon/Volume-Key-Selector/tools"; do
            [ -d "$d" ] && set_perm_recursive "$d" 0 0 0755 0755
        done

        [ -e "$modpath/addon/daemon/daemon.sh" ] && set_perm "$modpath/addon/daemon/daemon.sh" 0 0 0755
        [ -e "$modpath/scripts/service.sh" ] && set_perm "$modpath/scripts/service.sh" 0 0 0755
        [ -e "$modpath/service.sh" ] && set_perm "$modpath/service.sh" 0 0 0755
        [ -e "$modpath/post-fs-data.sh" ] && set_perm "$modpath/post-fs-data.sh" 0 0 0755
        [ -e "$modpath/scripts/post-fs-data.sh" ] && set_perm "$modpath/scripts/post-fs-data.sh" 0 0 0755
        set_perm "$modpath/addon/policy/executor.sh" 0 0 0755
        set_perm "$modpath/addon/functions/utils/Kitsutils.sh" 0 0 0755
        set_perm "$modpath/addon/functions/net_math.sh" 0 0 0755
        set_perm "$modpath/addon/functions/core.sh" 0 0 0755
        [ -e "$modpath/addon/daemon/iface_monitor.sh" ] && set_perm "$modpath/addon/daemon/iface_monitor.sh" 0 0 0755
        [ -e "$modpath/addon/ip/ip" ] && set_perm "$modpath/addon/ip/ip" 0 0 0755
        [ -e "$modpath/addon/ping/ping" ] && set_perm "$modpath/addon/ping/ping" 0 0 0755
        [ -e "$modpath/addon/Volume-Key-Selector/tools/arm/keycheck" ] && set_perm "$modpath/addon/Volume-Key-Selector/tools/arm/keycheck" 0 0 0755
        [ -e "$modpath/addon/Volume-Key-Selector/tools/x86/keycheck" ] && set_perm "$modpath/addon/Volume-Key-Selector/tools/x86/keycheck" 0 0 0755
    else
        # Fallback: attempt operations but avoid masking errors with '|| true'. Log failures to help debugging.
        if ! chown -R 0:0 "$modpath" 2>/dev/null; then
            [ -n "$log_file" ] && echo "[WARN] chown -R failed for $modpath" >> "$log_file"
        fi

        if ! find "$modpath" -type d -exec chmod 0755 {} \; 2>/dev/null; then
            [ -n "$log_file" ] && echo "[WARN] chmod 0755 on directories failed in $modpath" >> "$log_file"
        fi

        if ! find "$modpath" -type f -exec chmod 0644 {} \; 2>/dev/null; then
            [ -n "$log_file" ] && echo "[WARN] chmod 0644 on files failed in $modpath" >> "$log_file"
        fi

        # Ensure specific executables/scripts have executable permission and proper owner; log if any step fails.
        for dir in \
            "$modpath/addon/bc" \
            "$modpath/addon/jq" \
            "$modpath/addon/ip" \
            "$modpath/addon/ping" \
            "$modpath/addon/Volume-Key-Selector/tools"; do
            if [ -d "$dir" ]; then
                if ! find "$dir" -type f -exec chmod 0755 {} \; 2>/dev/null; then
                    [ -n "$log_file" ] && echo "[WARN] chmod 0755 failed in $dir" >> "$log_file"
                fi
                if ! find "$dir" -type f -exec chown 0:0 {} \; 2>/dev/null; then
                    [ -n "$log_file" ] && echo "[WARN] chown failed in $dir" >> "$log_file"
                fi
            fi
        done

        for f in \
            "$modpath/scripts/service.sh" \
            "$modpath/scripts/post-fs-data.sh" \
            "$modpath/service.sh" \
            "$modpath/post-fs-data.sh" \
            "$modpath/addon/Volume-Key-Selector/tools/arm/keycheck" \
            "$modpath/addon/Volume-Key-Selector/tools/x86/keycheck" \
            "$modpath/addon/ip/ip" \
            "$modpath/addon/ping/ping" \
            "$modpath/addon/daemon/daemon.sh" \
            "$modpath/addon/daemon/iface_monitor.sh" \
            "$modpath/addon/functions/net_math.sh" \
            "$modpath/addon/functions/core.sh" \
            "$modpath/addon/policy/executor.sh"; do
            if [ -e "$f" ]; then
                if ! chmod 0755 "$f" 2>/dev/null; then
                    [ -n "$log_file" ] && echo "[WARN] chmod 0755 failed on $f" >> "$log_file"
                fi
                if ! chown 0:0 "$f" 2>/dev/null; then
                    [ -n "$log_file" ] && echo "[WARN] chown failed on $f" >> "$log_file"
                fi
            fi
        done

        # Ensure Kitsutils.sh perms explicitly
        kf="$modpath/addon/functions/utils/Kitsutils.sh"
        if [ -e "$kf" ]; then
            if ! chmod 0644 "$kf" 2>/dev/null; then
                [ -n "$log_file" ] && echo "[WARN] chmod 0644 failed on $kf" >> "$log_file"
            fi
            if ! chown 0:0 "$kf" 2>/dev/null; then
                [ -n "$log_file" ] && echo "[WARN] chown failed on $kf" >> "$log_file"
            fi
        fi

    fi

    # Try to set SELinux context if possible. Prefer restorecon; chcon is last-resort and
    # can be undesirable for Magisk modules (may not be ideal and can be ignored under enforcing).
    if command -v restorecon >/dev/null 2>&1; then
        if ! restorecon -R "$modpath" 2>/dev/null; then
            [ -n "$log_file" ] && echo "[WARN] restorecon failed on $modpath" >> "$log_file"
        fi
    else
        if [ "$last_resort_chcon" = "1" ]; then
            if command -v chcon >/dev/null 2>&1; then
                [ -n "$log_file" ] && echo "[WARN] Applying generic SELinux context via chcon (last resort)" >> "$log_file"
                if ! chcon -R u:object_r:system_file:s0 "$modpath" 2>/dev/null; then
                    [ -n "$log_file" ] && echo "[WARN] chcon failed on $modpath" >> "$log_file"
                fi
            else
                [ -n "$log_file" ] && echo "[WARN] chcon not available; cannot apply SELinux context" >> "$log_file"
            fi
        else
            [ -n "$log_file" ] && echo "[WARN] restorecon not available; skipping chcon (disabled by default)" >> "$log_file"
        fi
    fi

    # Log success
    [ -n "$log_file" ] && echo "[OK] Permissions set in $modpath" >> "$log_file"
    # end closing function no return data 
    return 0
}

set_permissions() {
    set_permissions_module "$NEWMODPATH"
}

progress_bar() {
    local rueda='-\|/'
    local progress=""
    local completed=0

    while [ $completed -le 10 ]; do
        progress=$(printf "%-${completed}s" | tr ' ' "=")$(printf "%$((10-completed))s" | tr ' ' "-")
        echo -ne "[${progress}] ${rueda:$((completed % 4)):1}"
        sleep 0.5
        echo -ne "\r"
        completed=$((completed+1))
    done
}

get_time_stamp() {
    date +"%Y-%m-%d-%H:%M:%S"
}

getprop_or_default() {
  val="$(getprop "$1")"
  [ -n "$val" ] && echo "$val" || echo "$2"
}

# Atomic write helper
# usage: 
atomic_write() {
    local target="$1" tmp
    tmp=$(mktemp "${target}.XXXXXX") || tmp="${target}.$$.$(date +%s).tmp"
    if cat - > "$tmp" 2>/dev/null; then
        mv "$tmp" "$target" 2>/dev/null || rm -f "$tmp"
    else
        rm -f "$tmp"
        return 1
    fi
}

# Crear backup de los valores que se van a modificar para backup y restauracion
create_backup() {
    BACKUP_FILE="$NEWMODPATH/configs/kitsuneping_original_backup.conf"

    # Asegurar directorio
    mkdir -p "$NEWMODPATH/configs" 2>/dev/null

    # Si ya existe, rotar con timestamp y continuar (no salir) para siempre tener uno fresco
    if [ -f "$BACKUP_FILE" ]; then
        log_info "Backup already exists at $BACKUP_FILE"
        log_info "Creating a new one with timestamp"
        BACKUP_FILE="$NEWMODPATH/configs/kitsuneping_original_backup_$(get_time_stamp).conf"
    fi

    if ! touch "$BACKUP_FILE" 2>/dev/null; then
        log_error "Cannot write backup file at $BACKUP_FILE"
        return 1
    fi

    # Write current properties to backup file atomically
    if ! atomic_write "$BACKUP_FILE" <<EOF
ro.ril.hsdpa.category=$(getprop_or_default ro.ril.hsdpa.category)
ro.ril.hsupa.category=$(getprop_or_default ro.ril.hsupa.category)
ro.ril.lte.category=$(getprop_or_default ro.ril.lte.category)
ro.ril.ltea.category=$(getprop_or_default ro.ril.ltea.category)
ro.ril.nr5g.category=$(getprop_or_default ro.ril.nr5g.category)
ro.ril.enable.dtm=$(getprop_or_default ro.ril.enable.dtm)
ro.ril.enable.a51=$(getprop_or_default ro.ril.enable.a51)
ro.ril.enable.a52=$(getprop_or_default ro.ril.enable.a52)
ro.ril.enable.a53=$(getprop_or_default ro.ril.enable.a53)
ro.ril.gprsclass=$(getprop_or_default ro.ril.gprsclass)
ro.ril.transmitpower=$(getprop_or_default ro.ril.transmitpower)
kitsunping.daemon.interval=$(getprop_or_default kitsunping.daemon.interval)
persist.kitsunping.debug=$(getprop_or_default persist.kitsunping.debug)
persist.kitsunping.ping_timeout=$(getprop_or_default persist.kitsunping.ping_timeout)
persist.kitsunping.emit_events=$(getprop_or_default persist.kitsunping.emit_events)
persist.kitsunping.event_debounce_sec=$(getprop_or_default persist.kitsunping.event_debounce_sec)
ro.telephony.default_network=$(getprop_or_default ro.telephony.default_network)
ro.wifi.direct.interface=$(getprop_or_default ro.wifi.direct.interface)
wifi.supplicant_scan_interval=$(getprop_or_default wifi.supplicant_scan_interval)
persist.vendor.mtk.volte.enable=$(getprop_or_default persist.vendor.mtk.volte.enable)
persist.vendor.volte_support=$(getprop_or_default persist.vendor.volte_support)
persist.vendor.vowifi.enable=$(getprop_or_default persist.vendor.vowifi.enable)
persist.vendor.vowifi_support=$(getprop_or_default persist.vendor.vowifi_support)
persist.sys.vzw_wifi_running=$(getprop_or_default persist.sys.vzw_wifi_running)
persist.radio.add_power_save=$(getprop_or_default persist.radio.add_power_save)
ro.config.hw_power_saving=$(getprop_or_default ro.config.hw_power_saving)
ro.media.enc.jpeg.quality=$(getprop_or_default ro.media.enc.jpeg.quality)
persist.audio.fluence.voicecall=$(getprop_or_default persist.audio.fluence.voicecall)
logcat.live=$(getprop_or_default logcat.live)
EOF
    then
        log_error "Cannot write backup file at $BACKUP_FILE"
        return 1
    fi

    log_info "Backup saved at $BACKUP_FILE"
    return 0
}

set_selinux_enforce() {
    enforce_state="$1"
    log_file="$2"

    if [ "$(id -u)" -ne 0 ]; then
        [ -n "$log_file" ] && echo "[SYS][ERROR] root required" >> "$log_file"
        return 1
    fi

    case "$enforce_state" in
        0|1) :;;
        *)
            [ -n "$log_file" ] && echo "[SYS][ERROR] Invalid value: $enforce_state" >> "$log_file"
            return 2
            ;;
    esac

    if setenforce "$enforce_state" 2>>"$log_file"; then
        [ -n "$log_file" ] && echo "[SYS][OK] SELinux temporary: $(getenforce)" >> "$log_file"
    else
        [ -n "$log_file" ] && echo "[SYS][ERROR] setenforce failed" >> "$log_file"
        return 3
    fi

    return 0
}

# simple check for Qualcomm SoC, can be better but no testers available
is_qualcomm() {
    case "$(getprop ro.soc.manufacturer | tr '[:upper:]' '[:lower:]')" in
        qti|qualcomm)
            return 0
            ;;
    esac
    return 1
}


# how_to_proceed_with_calibration moved to addon/Net_Calibrate/calibrate.sh


# Normaliza valores de sysctl (convierte comas a espacios cuando aplica)
normalize_sysctl_value() {
    case "$1" in
        *","*) echo "${1//,/ }" ;;
        *) echo "$1" ;;
    esac
}

# Actualizacion: Una funcion simple para agilizar el script y evitar la repeticion de codigo
# └──Actualizacion: Cambie el nombre de la funcion a custom_write
custom_write() {
    echo "[DEBUG]: Llamada a [custom_write()] con argumentos: ['$1'], ['$2'], ['$3']" >> "$SERVICES_LOGS"

    value="$1"
    normalized_value=$(normalize_sysctl_value "$value") # 
    target_file="$2"
    log_text="$3"

    if [ "$#" -ne 3 ]; then
        echo "[SYS] [ERROR]: Numero de argumentos invalido en [custom_write()]" >> "$SERVICES_LOGS"
        return 1
    fi

    case "$target_file" in
        /*) ;;
        *)
            echo "[SYS] [ERROR]: Ruta no absoluta: '$target_file'" >> "$SERVICES_LOGS"
            return 2
            ;;
    esac

    if [ -z "$value" ] && [ "$value" != "0" ]; then
        echo "[SYS] [ERROR]: Valor vacio para '$target_file'" >> "$SERVICES_LOGS"
        return 3
    fi

    if [ ! -e "$target_file" ]; then
        echo "[SYS] [WARN]: Ruta no existe: '$target_file'" >> "$SERVICES_LOGS"
        return 0
    fi

    if [ ! -w "$target_file" ]; then
        chmod 0777 "$target_file" 2>> "$SERVICES_LOGS"
    fi

    case "$target_file" in
        /proc/sys/*)
            sysctl_param=${target_file#/proc/sys/}
            sysctl_param=$(echo "$sysctl_param" | tr '/' '.')
            # Skip if not writable to avoid noisy errors on readonly tunables
            if [ ! -w "$target_file" ]; then
                echo "[SYS][SKIP]: '$target_file' no es escribible" >> "$SERVICES_LOGS"
                return 0
            fi
            if /system/bin/sysctl -w "$sysctl_param=$normalized_value" >> "$SERVICES_LOGS" 2>&1; then
                echo "[OK] $log_text (sysctl): $normalized_value" >> "$SERVICES_LOGS"
                return 0
            fi
            echo "[SYS] [ERROR]: Fallo sysctl $sysctl_param" >> "$SERVICES_LOGS"
            ;;
    esac

    printf "%s" "$normalized_value" > "$target_file" 2>> "$SERVICES_LOGS"
    current_value=$(cat "$target_file" 2>/dev/null)
    if [ "$current_value" = "$normalized_value" ]; then
        echo "[OK] $log_text: $normalized_value" >> "$SERVICES_LOGS"
    else
        echo "[SYS] [ERROR]: Valor escrito ($current_value) != esperado ($normalized_value) en $target_file" >> "$SERVICES_LOGS"
        return 4
    fi

    return 0
}

apply_param_set() {
    while IFS='|' read -r value target_file log_text; do
        [ -z "$target_file" ] && continue
        custom_write "$value" "$target_file" "$log_text"
    done
}
