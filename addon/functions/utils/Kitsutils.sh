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
            "$modpath/addon/bin" \
            "$modpath/addon/jq" \
            "$modpath/addon/bc" \
            "$modpath/addon/ip" \
            "$modpath/addon/iw" \
            "$modpath/addon/ping" \
            "$modpath/addon/Volume-Key-Selector/tools"; do
            [ -d "$d" ] && set_perm_recursive "$d" 0 0 0755 0755
        done

        [ -e "$modpath/addon/daemon/daemon.sh" ] && set_perm "$modpath/addon/daemon/daemon.sh" 0 0 0755
        [ -e "$modpath/installer/service.sh" ] && set_perm "$modpath/installer/service.sh" 0 0 0755
        [ -e "$modpath/installer/post-fs-data.sh" ] && set_perm "$modpath/installer/post-fs-data.sh" 0 0 0755
        [ -e "$modpath/installer/uninstall.sh" ] && set_perm "$modpath/installer/uninstall.sh" 0 0 0755
        [ -e "$modpath/service.sh" ] && set_perm "$modpath/service.sh" 0 0 0755
        [ -e "$modpath/post-fs-data.sh" ] && set_perm "$modpath/post-fs-data.sh" 0 0 0755
        [ -e "$modpath/policy/executor/executor.sh" ] && set_perm "$modpath/policy/executor/executor.sh" 0 0 0755
        [ -e "$modpath/addon/policy/executor.sh" ] && set_perm "$modpath/addon/policy/executor.sh" 0 0 0755
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
            "$modpath/addon/bin" \
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
            "$modpath/installer/service.sh" \
            "$modpath/installer/post-fs-data.sh" \
            "$modpath/installer/uninstall.sh" \
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
            "$modpath/policy/executor/executor.sh" \
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

    # Ensure files touched at runtime keep explicit writable ownership/perms.
    # This does not bypass read-only mounts, but gives deterministic perms after reinstall.
    set_runtime_writable_permissions "$modpath" "$log_file"

    # Log success
    [ -n "$log_file" ] && echo "[OK] Permissions set in $modpath" >> "$log_file"
    # end closing function no return data 
    return 0
}

# Ensure files that daemon/failsafe update at runtime have explicit ownership/perms.
# Usage: set_runtime_writable_permissions <modpath> [log_file]
set_runtime_writable_permissions() {
    local modpath="$1"
    local log_file="$2"
    local runtime_dir runtime_file

    [ -n "$modpath" ] || return 1

    for runtime_dir in \
        "$modpath/cache" \
        "$modpath/logs" \
        "$modpath/cache/tmp"; do
        if [ -d "$runtime_dir" ] || mkdir -p "$runtime_dir" 2>/dev/null; then
            chmod 0755 "$runtime_dir" 2>/dev/null || true
            chown 0:0 "$runtime_dir" 2>/dev/null || true
        else
            [ -n "$log_file" ] && echo "[WARN] cannot create runtime dir: $runtime_dir" >> "$log_file"
        fi
    done

    for runtime_file in \
        "$modpath/module.prop" \
        "$modpath/cache/daemon.state" \
        "$modpath/cache/link_context.state" \
        "$modpath/cache/kitsunping_runtime.json" \
        "$modpath/cache/daemon.last" \
        "$modpath/cache/event.last.json" \
        "$modpath/cache/router.last" \
        "$modpath/cache/router.dni" \
        "$modpath/cache/router.pairing.json"; do
        if [ ! -e "$runtime_file" ]; then
            touch "$runtime_file" 2>/dev/null || {
                [ -n "$log_file" ] && echo "[WARN] cannot create runtime file: $runtime_file" >> "$log_file"
                continue
            }
        fi

        chmod 0644 "$runtime_file" 2>/dev/null || {
            [ -n "$log_file" ] && echo "[WARN] chmod 0644 failed on $runtime_file" >> "$log_file"
        }
        chown 0:0 "$runtime_file" 2>/dev/null || {
            [ -n "$log_file" ] && echo "[WARN] chown failed on $runtime_file" >> "$log_file"
        }

        if [ ! -w "$runtime_file" ]; then
            [ -n "$log_file" ] && echo "[WARN] not writable after permission set: $runtime_file (possible read-only mount/context issue)" >> "$log_file"
        fi
    done

    return 0
}

set_permissions() {
    set_permissions_module "$NEWMODPATH"
}

progress_bar() {
    local spin
    local progress=""
    local completed=0

    while [ "$completed" -lt 10 ]; do
        progress=$(printf "%-${completed}s" | tr ' ' "=")$(printf "%$((10-completed))s" | tr ' ' "-")
        case $((completed % 4)) in
            0) spin='-' ;;
            1) spin='\\' ;;
            2) spin='|' ;;
            3) spin='/' ;;
        esac
        printf '\r[%s] %s' "$progress" "$spin"
        sleep 0.5
        completed=$((completed+1))
    done

    # Render a stable final state and end with newline to avoid trailing spinner artifacts.
    printf '\r[%s] %s\n' "==========" "OK"
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
    local target="$1" tmp target_dir
    [ -n "$target" ] || return 1
    target_dir="$(dirname "$target")"
    [ -n "$target_dir" ] || target_dir="."
    mkdir -p "$target_dir" 2>/dev/null || return 1
    tmp=$(mktemp "$target_dir/.atomic_write.XXXXXX" 2>/dev/null) || tmp="$target_dir/.atomic_write.$$.$(date +%s).tmp"
    if ! cat - > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi

    if mv -f "$tmp" "$target" 2>/dev/null; then
        return 0
    fi

    # Fallback: overwrite in place when rename is blocked by FS constraints.
    if cat "$tmp" > "$target" 2>/dev/null; then
        rm -f "$tmp" 2>/dev/null || true
        return 0
    fi

    rm -f "$tmp" 2>/dev/null || true
    return 1
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
# TODO: use this for add better staility on executor, daemon, logs.
detect_and_write_ram_props() {
    modpath="$1"
    [ -z "$modpath" ] && modpath="${NEWMODPATH:-.}"
    system_prop_file="$modpath/system.prop"

    RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    if [ -z "$RAM_MB" ] || [ "$RAM_MB" -le 0 ] 2>/dev/null; then
        RAM_MB=0
    fi

    # Thresholds (MB, with margin): 2560 (2.5GB), 5120 (5GB), 12288 (12GB), 16384 (16GB)
    if [ "$RAM_MB" -ge 0 ] && [ "$RAM_MB" -lt 2860 ]; then
        RAM_CLASS="3GB"
    elif [ "$RAM_MB" -ge 2860 ] && [ "$RAM_MB" -lt 5120 ]; then
        RAM_CLASS="6GB"
    elif [ "$RAM_MB" -ge 5120 ] && [ "$RAM_MB" -lt 12288 ]; then
        RAM_CLASS="12GB"
    elif [ "$RAM_MB" -ge 12288 ] && [ "$RAM_MB" -lt 16384 ]; then
        RAM_CLASS="16GB"
    else
        RAM_CLASS="16GB+"
    fi

    # TODO: create a function to classify what amount of ram/cpu/proces can be added for better performance, for example, if the device have less 3gb of ram, the module can include aditional time on ping or increase the interval of the daemon to reduce the load on the system, and if the device have more than 6-12gb of ram, the module can include aditional features that require more resources, like reduce time proceses, more frecuent pings, procesos, events etc.
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

wifi.supplicant_scan_interval
gsm.sim.operator.iso-country
debug.tracing.mcc
debug.tracing.mnc
sys.boot_completed
logcat.live

sys.wifi6.enable
persist.vendor.connmgr.wifi.bss_coloring
persist.vendor.data.mode
persist.radio.def_network
net.tcp.2g_init_rwnd
net.tcp_def_init_rwnd
sys.tcp_cubic.hystart
persist.data.df.agg.dl_pkt
persist.data.df.agg.dl_size
persist.data.df.dl_mode
persist.data.df.ul_mode
persist.data.df.mux_count
vendor.wlan.driver.version
vendor.wlan.firmware.version
ro.vendor.radio.default_network
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

# ── SoC detection helpers ──────────────────────────────────────────
# Multi-layered detection: manufacturer prop → board platform → hardware
# paths → cpuinfo/device-tree fallback.  Cached after first call.
_KITSUN_SOC_VENDOR=""   # cache: qualcomm | mtk | exynos | unknown

_detect_soc_vendor() {
    [ -n "$_KITSUN_SOC_VENDOR" ] && return 0

    # Layer 1: ro.soc.manufacturer (most reliable on modern devices)
    _soc_mfr="$(getprop ro.soc.manufacturer 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    case "$_soc_mfr" in
        qti|qualcomm)   _KITSUN_SOC_VENDOR="qualcomm"; return 0 ;;
        mediatek|mtk)   _KITSUN_SOC_VENDOR="mtk";      return 0 ;;
        samsung|slsi)   _KITSUN_SOC_VENDOR="exynos";   return 0 ;;
    esac

    # Layer 2: ro.board.platform / ro.hardware
    _board="$(getprop ro.board.platform 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    case "$_board" in
        msm*|sdm*|sm[0-9]*|qcom*|taro|kalama|pineapple|lahaina|waipio|crow|sun|parrot|cape)
            _KITSUN_SOC_VENDOR="qualcomm"; return 0 ;;
        mt*|mt[0-9]*)
            _KITSUN_SOC_VENDOR="mtk"; return 0 ;;
        exynos*|universal*|erd*|s5e*)
            _KITSUN_SOC_VENDOR="exynos"; return 0 ;;
    esac

    _hw="$(getprop ro.hardware 2>/dev/null | tr '[:upper:]' '[:lower:]')"
    case "$_hw" in
        qcom|qualcomm) _KITSUN_SOC_VENDOR="qualcomm"; return 0 ;;
        mt*|mediatek)  _KITSUN_SOC_VENDOR="mtk";      return 0 ;;
        exynos*|samsung*|samsungexynos*) _KITSUN_SOC_VENDOR="exynos"; return 0 ;;
    esac

    # Layer 3: Qualcomm-specific sysfs (Adreno GPU path)
    [ -d /sys/class/kgsl/kgsl-3d0/devfreq ] && {
        _KITSUN_SOC_VENDOR="qualcomm"; return 0
    }
    # MediaTek-specific sysfs
    [ -d /sys/kernel/ged/hal ] && {
        _KITSUN_SOC_VENDOR="mtk"; return 0
    }

    # Layer 4: additional getprop fallbacks
    for _p in ro.vendor.qti.soc_name ro.chipname ro.hardware.chipname; do
        _v="$(getprop "$_p" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        case "$_v" in
            sm[0-9]*|sdm*|msm*|qcom*) _KITSUN_SOC_VENDOR="qualcomm"; return 0 ;;
            mt[0-9]*)                  _KITSUN_SOC_VENDOR="mtk";      return 0 ;;
            exynos*|s5e*)              _KITSUN_SOC_VENDOR="exynos";   return 0 ;;
        esac
    done

    _KITSUN_SOC_VENDOR="unknown"
    return 1
}

is_qualcomm() {
    _detect_soc_vendor
    [ "$_KITSUN_SOC_VENDOR" = "qualcomm" ]
}

is_mtk() {
    _detect_soc_vendor
    [ "$_KITSUN_SOC_VENDOR" = "mtk" ]
}

is_exynos() {
    _detect_soc_vendor
    [ "$_KITSUN_SOC_VENDOR" = "exynos" ]
}

# Return the cached vendor string (qualcomm|mtk|exynos|unknown)
get_soc_vendor() {
    _detect_soc_vendor
    printf '%s' "$_KITSUN_SOC_VENDOR"
}

# Detect 5G radio capability (NSA or SA)
is_5g_capable() {
    # Check Samsung-specific ril props first
    case "$(getprop ril.5g_rf 2>/dev/null)" in 1) return 0 ;; esac
    case "$(getprop ril.enabled_5g_rf 2>/dev/null)" in 1) return 0 ;; esac
    # Check ro.telephony.default_network >= 23 (NR preference modes)
    _net="$(getprop ro.telephony.default_network 2>/dev/null)"
    [ -n "$_net" ] && [ "$_net" -ge 23 ] 2>/dev/null && return 0
    # Check NR band config
    [ -n "$(getprop persist.vendor.radio.nr5g 2>/dev/null)" ] && return 0
    return 1
}

# Detect Samsung SHS hardware offload (rmnet scheduler)
is_shs_active() {
    case "$(getprop persist.vendor.data.shs_ko_load 2>/dev/null)" in 1) return 0 ;; esac
    [ -d /sys/module/rmnet_shs ] && return 0
    return 1
}

# usage normalize_profile_name
# Normalize the profile name to expected values.
# If the value is not recognized, it returns "speed" by default
normalize_profile_name() {
    case "$1" in
        benchmark) printf '%s' "benchmark_gaming" ;;
        speed|stable|gaming|benchmark_gaming|benchmark_speed) printf '%s' "$1" ;;
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

    # Convert newlines to pipe — busybox awk rejects literal newlines in -v
    profile_keys_flat="$(printf '%s' "$profile_keys" | tr '\n' '|')"

    tmp_file="${dst_file}.tmp.$$"
    awk -v profile_file="$profile_file" -v keys="$profile_keys_flat" '
        BEGIN {
            n = split(keys, key_lines, "|")
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

    # Deduplicate: /system/vendor/… and /vendor/… are the same physical file
    # on most devices.  Keep only one cfg per basename-path, preferring the
    # shorter (canonical) form.
    _seen_wcnss=""
    for cfg in $cfgs; do
        [ -f "$cfg" ] || continue

        # Normalise to the Magisk systemless mount destination immediately
        # so we never need the mv-at-the-end trick.
        case "$cfg" in
            /system/vendor/*)    dst="$modpath${cfg}" ;;
            /system/product/*)   dst="$modpath${cfg}" ;;
            /system/system_ext/*) dst="$modpath${cfg}" ;;
            /vendor/*)           dst="$modpath/system${cfg}" ;;
            /product/*)          dst="$modpath/system${cfg}" ;;
            /system_ext/*)       dst="$modpath/system${cfg}" ;;
            *)                   dst="$modpath${cfg}" ;;
        esac

        # Skip if we already processed an equivalent destination
        case "$_seen_wcnss" in
            *"|$dst|"*) continue ;;
        esac
        _seen_wcnss="${_seen_wcnss}|$dst|"

        mkdir -p "$(dirname "$dst")"
        [ -n "$log_file" ] && echo "[SYS][WCNSS] Migrating $cfg -> $dst" >> "$log_file"
        $cmdprefix cp -af "$cfg" "$dst" 2>>"$log_file"

        if apply_wcnss_profile_file "$dst" "$profile_file" "$log_file"; then
            [ -n "$log_file" ] && echo "[SYS][WCNSS] Updated $dst" >> "$log_file"
        else
            [ -n "$log_file" ] && echo "[SYS][WCNSS][WARN] Failed to update $dst" >> "$log_file"
        fi
    done

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
    
    # ── Common tunables (all SoC vendors) applied per profile ──
    case "$profile_name" in
        gaming|benchmark_gaming|benchmark_speed|speed)
            # Aggressive data aggregation for throughput
            apply_prop "persist.data.df.agg.dl_pkt"  "20"
            apply_prop "persist.data.df.agg.dl_size"  "8192"
            apply_prop "persist.data.df.dl_mode"       "5"
            apply_prop "persist.data.df.ul_mode"       "5"
            apply_prop "persist.data.df.mux_count"     "8"
            # Keep cubic hystart off for high-throughput profiles (avoids premature exit of slow-start)
            apply_prop "sys.tcp_cubic.hystart"         "0"
            # Larger initial receive window for fast connections
            apply_prop "net.tcp_def_init_rwnd"         "80"
            apply_prop "net.tcp.2g_init_rwnd"          "20"
            ;;
        stable)
            # Conservative / stock-like data aggregation
            apply_prop "persist.data.df.agg.dl_pkt"  "10"
            apply_prop "persist.data.df.agg.dl_size"  "4096"
            apply_prop "persist.data.df.dl_mode"       "2"
            apply_prop "persist.data.df.ul_mode"       "2"
            apply_prop "persist.data.df.mux_count"     "4"
            # Re-enable hystart for safety on congested/weak links
            apply_prop "sys.tcp_cubic.hystart"         "1"
            apply_prop "net.tcp_def_init_rwnd"         "60"
            apply_prop "net.tcp.2g_init_rwnd"          "10"
            ;;
    esac

    # ── SoC-specific Wi-Fi resetprops ──
    if is_mtk; then
        case "$profile_name" in
            gaming|benchmark_gaming)
                apply_prop "sys.wifi6.enable" "1"
                apply_prop "persist.vendor.connmgr.wifi.bss_coloring" "1"
                ;;
            speed|benchmark_speed)
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
            gaming|benchmark_gaming|benchmark_speed|speed)
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


# how_to_proceed_with_calibration moved to calibration/calibrate.sh


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

 