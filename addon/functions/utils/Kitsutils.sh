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
            "$modpath/addon/iw" \
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
        [ -e "$modpath/addon/functions/daemon_static.sh" ] && set_perm "$modpath/addon/functions/daemon_static.sh" 0 0 0755
        [ -e "$modpath/addon/daemon/iface_monitor.sh" ] && set_perm "$modpath/addon/daemon/iface_monitor.sh" 0 0 0755
        [ -e "$modpath/addon/ip/ip" ] && set_perm "$modpath/addon/ip/ip" 0 0 0755
        [ -e "$modpath/addon/iw/iw" ] && set_perm "$modpath/addon/iw/iw" 0 0 0755
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
            "$modpath/addon/iw" \
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
            "$modpath/addon/iw/iw" \
            "$modpath/addon/ping/ping" \
            "$modpath/addon/daemon/daemon.sh" \
            "$modpath/addon/daemon/iface_monitor.sh" \
            "$modpath/addon/functions/net_math.sh" \
            "$modpath/addon/functions/core.sh" \
            "$modpath/addon/functions/daemon_static.sh" \
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

# Update or append a property in a file (portable)
update_prop_in_file() {
    key="$1"
    val="$2"
    file="$3"
    mkdir -p "$(dirname "$file")" 2>/dev/null
    touch "$file" 2>/dev/null || return 1
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        awk -v k="$key" -v v="$val" 'BEGIN{FS=OFS="="} $1==k{$2=v;found=1} {print} END{if(!found) print k"="v}' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    else
        printf '%s=%s\n' "$key" "$val" >> "$file"
    fi
}

# Detect total RAM once and write properties into system.prop for profile logic
# Thresholds (MB, with margin): 2560 (2.5GB -> 3GB class), 5120 (5GB -> 6GB class), 12288 (12GB), 16384 (16GB)
detect_and_write_ram_props() {
    modpath="$1"
    [ -z "$modpath" ] && modpath="${NEWMODPATH:-.}"
    system_prop_file="$modpath/system.prop"

    RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    if [ -z "$RAM_MB" ] || [ "$RAM_MB" -le 0 ] 2>/dev/null; then
        RAM_MB=0
    fi

    # Thresholds (MB, with margin): 2560 (2.5GB), 5120 (5GB), 12288 (12GB), 16384 (16GB)
    if [ "$RAM_MB" -lt 2560 ]; then
        RAM_CLASS="3GB"
    elif [ "$RAM_MB" -lt 5120 ]; then
        RAM_CLASS="6GB"
    elif [ "$RAM_MB" -lt 12288 ]; then
        RAM_CLASS="12GB"
    elif [ "$RAM_MB" -lt 16384 ]; then
      RAM_CLASS="16GB"
    else
        RAM_CLASS="16GB+"
    fi
    # TODO: create a function whit detect what amount of ram/cpu/proces can be added for better performance, for example, if the device have less 3gb of ram, the module can include aditional time on ping or increase the interval of the daemon to reduce the load on the system, and if the device have more than 6-12gb of ram, the module can include aditional features that require more resources, like reduce time proceses, more frecuent pings, procesos, events etc.
    update_prop_in_file "persist.kitsunping.ram.size" "${RAM_MB}MB" "$system_prop_file"
    update_prop_in_file "persist.kitsunping.ram.class" "$RAM_CLASS" "$system_prop_file"

    # Return readable info for callers
    printf '%s %s' "${RAM_MB}MB" "$RAM_CLASS"
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

    BACKUP_PROP_KEYS="
ro.ril.hsdpa.category
ro.ril.hsupa.category
ro.ril.lte.category
ro.ril.ltea.category
ro.ril.nr5g.category
ro.ril.enable.dtm
ro.ril.enable.a51
ro.ril.enable.a52
ro.ril.enable.a53
ro.ril.enable.a54
ro.ril.enable.a55
ro.ril.gprsclass
ro.ril.transmitpower
ro.telephony.default_network
ro.wifi.direct.interface
ro.config.hw_power_saving
ro.media.enc.jpeg.quality
ro.board.platform
ro.soc.manufacturer
ro.product.cpu.abi

persist.vendor.mtk.volte.enable
persist.vendor.volte_support
persist.vendor.vowifi.enable
persist.vendor.vowifi_support
persist.sys.vzw_wifi_running
persist.radio.add_power_save
persist.audio.fluence.voicecall

kitsunping.daemon.interval
kitsunping.daemon.signal_poll_interval
kitsunping.daemon.net_probe_interval
kitsunping.sigmoid.alpha
kitsunping.sigmoid.beta
kitsunping.sigmoid.gamma
kitsunping.router.debug
kitsunping.router.experimental
kitsunping.router.openwrt_mode
kitsunping.router.cache_ttl
kitsunping.router.infer_width
kitsunping.wifi.speed_threshold
kitsunping.event.debounce_sec

persist.kitsunping.debug
persist.kitsunping.ping_timeout
persist.kitsunping.emit_events
persist.kitsunping.event_debounce_sec
persist.kitsunping.calibrate_cache_enable
persist.kitsunping.calibrate_cache_max_age_sec
persist.kitsunping.calibrate_cache_rtt_ms
persist.kitsunping.calibrate_cache_loss_pct
persist.kitsunping.router.debug
persist.kitsunping.router.experimental
persist.kitsunping.router.openwrt_mode
persist.kitsunping.router.cache_ttl
persist.kitsunping.router.infer_width
persist.kitsunping.user_event
persist.kitsunping.user_event_data

persist.kitsunrouter.enable
persist.kitsunrouter.debug
persist.kitsunrouter.paired

wifi.supplicant_scan_interval
gsm.sim.operator.iso-country
debug.tracing.mcc
debug.tracing.mnc
sys.boot_completed
logcat.live
"

    # Write current properties to backup file atomically
    if ! {
        for prop_key in $BACKUP_PROP_KEYS; do
            [ -z "$prop_key" ] && continue
            printf '%s=%s\n' "$prop_key" "$(getprop_or_default "$prop_key")"
        done
    } | atomic_write "$BACKUP_FILE"
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

is_mtk() {
    soc_mfr="$(getprop ro.soc.manufacturer | tr '[:upper:]' '[:lower:]')"
    board="$(getprop ro.board.platform | tr '[:upper:]' '[:lower:]')"
    case "$soc_mfr" in
        mediatek|mtk) return 0 ;;
    esac
    case "$board" in
        mt*) return 0 ;;
    esac
    return 1
}

# usage normalize_profile_name
# Normalize the profile name to expected values (speed, stable, gaming)
# If the value is not recognized, it returns "speed" by default
normalize_profile_name() {
    case "$1" in
        speed|stable|gaming) printf '%s' "$1" ;;
        *) printf '%s' "speed" ;;
    esac
}

resolve_active_profile_name() {
    modpath="$1"
    profile=""

    [ -n "${KITSUN_PROFILE:-}" ] && profile="$KITSUN_PROFILE"

    if [ -z "$profile" ] && [ -f "$modpath/cache/policy.current" ]; then
        profile="$(cat "$modpath/cache/policy.current" 2>/dev/null)"
    fi

    if [ -z "$profile" ] && [ -f "$modpath/cache/policy.target" ]; then
        profile="$(cat "$modpath/cache/policy.target" 2>/dev/null)"
    fi

    if [ -z "$profile" ] && [ -f "$modpath/cache/policy.request" ]; then
        profile="$(cat "$modpath/cache/policy.request" 2>/dev/null)"
    fi

    normalize_profile_name "$profile"
}

apply_wcnss_profile_file() {
    dst_file="$1"
    profile_file="$2"
    log_file="$3"

    [ -f "$dst_file" ] || return 1
    [ -f "$profile_file" ] || return 1

    profile_keys="$(awk -F= '
        /^[[:space:]]*#/ {next}
        /^[[:space:]]*$/ {next}
        {
            key=$1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            if (key != "") print key
        }
    ' "$profile_file" 2>/dev/null)"

    [ -n "$profile_keys" ] || return 1

    tmp_file="${dst_file}.tmp.$$"
    awk -v profile_file="$profile_file" -v keys="$profile_keys" '
        BEGIN {
            n = split(keys, key_lines, "\n")
            for (i = 1; i <= n; i++) {
                key = key_lines[i]
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                if (key != "") keep[key] = 1
            }

            pcount = 0
            while ((getline pl < profile_file) > 0) {
                if (pl ~ /^[[:space:]]*#/ || pl ~ /^[[:space:]]*$/) continue
                pcount++
                profile_lines[pcount] = pl
            }
            close(profile_file)
            inserted = 0
        }
        {
            if ($0 == "END") {
                for (i = 1; i <= pcount; i++) print profile_lines[i]
                print "END"
                inserted = 1
                next
            }

            skip = 0
            for (k in keep) {
                pattern = "^" k "[[:space:]]*="
                if ($0 ~ pattern) {
                    skip = 1
                    break
                }
            }
            if (!skip) print
        }
        END {
            if (!inserted) {
                for (i = 1; i <= pcount; i++) print profile_lines[i]
                print "END"
            }
        }
    ' "$dst_file" > "$tmp_file" 2>>"$log_file" || {
        rm -f "$tmp_file" 2>/dev/null
        return 1
    }

    mv -f "$tmp_file" "$dst_file" 2>>"$log_file" || {
        rm -f "$tmp_file" 2>/dev/null
        return 1
    }

    return 0
}

apply_qcom_wcnss_profile() {
    modpath="$1"
    profile_name="$2"
    log_file="$3"

    [ -z "$modpath" ] && return 1
    profile_name="$(normalize_profile_name "$profile_name")"

    if ! is_qualcomm; then
        [ -n "$log_file" ] && echo "[SYS][WCNSS] Non-Qualcomm chipset; skip WCNSS profile" >> "$log_file"
        return 0
    fi

    profile_file="$modpath/net_profiles/qcom_${profile_name}_profile.conf"
    if [ ! -f "$profile_file" ]; then
        profile_file="$modpath/net_profiles/qcom_speed_profile.conf"
        [ -n "$log_file" ] && echo "[SYS][WCNSS][WARN] profile file missing, fallback to speed" >> "$log_file"
    fi

    cmdprefix=""
    if command -v magisk >/dev/null 2>&1; then
        if magisk --denylist ls >/dev/null 2>&1; then
            cmdprefix="magisk --denylist exec"
        elif magisk magiskhide ls >/dev/null 2>&1; then
            cmdprefix="magisk magiskhide exec"
        fi
    fi

    check_dirs="/system /vendor /product /system_ext"
    existing_dirs=""
    for dir in $check_dirs; do
        [ -d "$dir" ] && existing_dirs="$existing_dirs $dir"
    done

    if [ -n "$existing_dirs" ]; then
        cfgs=$($cmdprefix find $existing_dirs -type f -name WCNSS_qcom_cfg.ini 2>/dev/null)
    else
        cfgs=""
    fi

    if [ -z "$cfgs" ]; then
        [ -n "$log_file" ] && echo "[SYS][WCNSS] No WCNSS_qcom_cfg.ini found" >> "$log_file"
        return 0
    fi

    [ -n "$log_file" ] && echo "[SYS][WCNSS] Applying profile=$profile_name file=$(basename "$profile_file")" >> "$log_file"

    for cfg in $cfgs; do
        [ -f "$cfg" ] || continue

        dst="$modpath$cfg"
        mkdir -p "$(dirname "$dst")"
        [ -n "$log_file" ] && echo "[SYS][WCNSS] Migrating $cfg" >> "$log_file"
        $cmdprefix cp -af "$cfg" "$dst" 2>>"$log_file"

        if apply_wcnss_profile_file "$dst" "$profile_file" "$log_file"; then
            [ -n "$log_file" ] && echo "[SYS][WCNSS] Updated $dst" >> "$log_file"
        else
            [ -n "$log_file" ] && echo "[SYS][WCNSS][WARN] Failed to update $dst" >> "$log_file"
        fi
    done

    mkdir -p "$modpath/system"
    mv -f "$modpath/vendor" "$modpath/system/vendor" 2>/dev/null
    mv -f "$modpath/product" "$modpath/system/product" 2>/dev/null
    mv -f "$modpath/system_ext" "$modpath/system/system_ext" 2>/dev/null
    return 0
}

apply_profile_runtime_resetprops() {
    profile_name="$1"
    log_file="$2"
    rp_bin=""

    profile_name="$(normalize_profile_name "$profile_name")"

    if command -v resetprop >/dev/null 2>&1; then
        rp_bin="$(command -v resetprop 2>/dev/null)"
    fi

    [ -n "$rp_bin" ] || {
        [ -n "$log_file" ] && echo "[SYS][PROFILE][WARN] resetprop not available" >> "$log_file"
        return 1
    }

    apply_prop() {
        pkey="$1"
        pval="$2"
        if "$rp_bin" -n "$pkey" "$pval" >>"$log_file" 2>&1; then
            [ -n "$log_file" ] && echo "[SYS][PROFILE] resetprop -n $pkey $pval" >> "$log_file"
            return 0
        fi
        [ -n "$log_file" ] && echo "[SYS][PROFILE][WARN] resetprop failed: $pkey=$pval" >> "$log_file"
        return 1
    }

    # TODO: create method to implement gaming profile when x app is lanched, com.app1=gaming
    
    if is_mtk; then
        case "$profile_name" in
            gaming)
                apply_prop "sys.wifi6.enable" "1"
                apply_prop "persist.vendor.connmgr.wifi.bss_coloring" "1"
                ;;
            speed)
                apply_prop "sys.wifi6.enable" "1"
                ;;
            stable)
                apply_prop "sys.wifi6.enable" "0"
                apply_prop "persist.vendor.connmgr.wifi.bss_coloring" "0"
                ;;
        esac
        return 0
    fi

    if is_qualcomm; then
        case "$profile_name" in
            gaming|speed)
                apply_prop "sys.wifi6.enable" "1"
                apply_prop "persist.vendor.connmgr.wifi.bss_coloring" "1"
                ;;
            stable)
                apply_prop "sys.wifi6.enable" "0"
                apply_prop "persist.vendor.connmgr.wifi.bss_coloring" "0"
                ;;
        esac
        return 0
    fi

    [ -n "$log_file" ] && echo "[SYS][PROFILE] Unsupported SoC for runtime Wi-Fi resetprops" >> "$log_file"
    return 0
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

    if [ ! -w "$target_file" ] && [ "${target_file#/proc/sys/}" = "$target_file" ]; then
        chmod 0777 "$target_file" 2>> "$SERVICES_LOGS"
    fi

    case "$target_file" in
        /proc/sys/*)
            local sysctl_bin=""
            sysctl_param=${target_file#/proc/sys/}
            sysctl_param=$(echo "$sysctl_param" | tr '/' '.')
            # Skip if not writable to avoid noisy errors on readonly tunables
            if [ ! -w "$target_file" ]; then
                echo "[SYS][SKIP]: '$target_file' no es escribible" >> "$SERVICES_LOGS"
                return 0
            fi
            if command -v sysctl >/dev/null 2>&1; then
                sysctl_bin="$(command -v sysctl)"
            elif [ -x /system/bin/sysctl ]; then
                sysctl_bin="/system/bin/sysctl"
            fi
            if [ -n "$sysctl_bin" ]; then
                if "$sysctl_bin" -w "$sysctl_param=$normalized_value" >> "$SERVICES_LOGS" 2>&1; then
                    current_value=$(cat "$target_file" 2>/dev/null)
                    if [ "$current_value" = "$normalized_value" ]; then
                        echo "[OK] $log_text (sysctl): $normalized_value" >> "$SERVICES_LOGS"
                        return 0
                    fi
                    echo "[SYS][WARN]: sysctl aplico pero verificacion leida no coincide en $target_file (got=$current_value expected=$normalized_value)" >> "$SERVICES_LOGS"
                else
                    echo "[SYS] [WARN]: Fallo sysctl $sysctl_param; intento escritura directa" >> "$SERVICES_LOGS"
                fi
            else
                echo "[SYS][WARN]: sysctl no disponible; intento escritura directa para $target_file" >> "$SERVICES_LOGS"
            fi
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
    local value target_file log_text line_count ok_count fail_count
    line_count=0
    ok_count=0
    fail_count=0

    while IFS='|' read -r value target_file log_text; do
        line_count=$((line_count + 1))

        value=$(printf '%s' "$value" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        target_file=$(printf '%s' "$target_file" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        log_text=$(printf '%s' "$log_text" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        [ -z "$value" ] && [ -z "$target_file" ] && [ -z "$log_text" ] && continue
        case "$value" in \#*) continue ;; esac

        if [ -z "$target_file" ]; then
            echo "[SYS][WARN]: apply_param_set linea $line_count sin target_file" >> "$SERVICES_LOGS"
            fail_count=$((fail_count + 1))
            continue
        fi

        if custom_write "$value" "$target_file" "$log_text"; then
            ok_count=$((ok_count + 1))
        else
            fail_count=$((fail_count + 1))
            echo "[SYS][WARN]: apply_param_set fallo linea $line_count target=$target_file value=$value" >> "$SERVICES_LOGS"
        fi
    done

    echo "[SYS][INFO]: apply_param_set resumen ok=$ok_count fail=$fail_count" >> "$SERVICES_LOGS"
}
