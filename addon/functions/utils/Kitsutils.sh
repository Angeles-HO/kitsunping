#!/system/bin/sh
# MODDIR=${0%/*}
# Funciones utiles para acortar el codigo y mejorar la legibilidad

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

        set_perm "$modpath/addon/daemon/daemon.sh" 0 0 0755
        set_perm "$modpath/service.sh" 0 0 0755
        set_perm "$modpath/post-fs-data.sh" 0 0 0755
        set_perm "$modpath/addon/policy/executor.sh" 0 0 0755
        set_perm "$modpath/addon/functions/utils/Kitsutils.sh" 0 0 0644
        set_perm "$modpath/addon/functions/net_math.sh" 0 0 0644
        set_perm "$modpath/addon/functions/core.sh" 0 0 0644
        set_perm "$modpath/addon/daemon/iface_monitor.sh" 0 0 0644
        set_perm "$modpath/addon/ip/ip" 0 0 0755
        set_perm "$modpath/addon/ping/ping" 0 0 0755
        set_perm "$modpath/addon/Volume-Key-Selector/tools/arm/keycheck" 0 0 0755
        set_perm "$modpath/addon/Volume-Key-Selector/tools/x86/keycheck" 0 0 0755
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

    {
        echo "ro.ril.hsdpa.category=$(getprop_or_default ro.ril.hsdpa.category)"
        echo "ro.ril.hsupa.category=$(getprop_or_default ro.ril.hsupa.category)"
        echo "ro.ril.lte.category=$(getprop_or_default ro.ril.lte.category)"
        echo "ro.ril.ltea.category=$(getprop_or_default ro.ril.ltea.category)"
        echo "ro.ril.nr5g.category=$(getprop_or_default ro.ril.nr5g.category)"
    } > "$BACKUP_FILE"

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

is_qualcomm() {
    case "$(getprop ro.soc.manufacturer | tr '[:upper:]' '[:lower:]')" in
        qti|qualcomm)
            return 0
            ;;
    esac
    return 1
}

# Atomic write helper
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