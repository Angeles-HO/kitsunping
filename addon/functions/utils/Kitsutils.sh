#!/system/bin/sh
# MODDIR=${0%/*}
# Funciones utiles para acortar el codigo y mejorar la legibilidad

# ---------------------------------------------------------------------
# actualizacion 1.7 solo la progress bar que andaba mal, muy mal
# actualizacion 1.8 solo la progress bar que andaba mal
# Actualizacion: Verificar si el complemento de funciones utilitarias existe
# funcion para verificar si el complemento existe
verify_complemento() {
    local complemento="$1"

    if [ -f "$NEWMODPATH/$complemento" ]; then
        . "$NEWMODPATH/$complemento" || {
            echo "[ERROR] No se pudo cargar el complemento: $complemento"
            exit 1
        }
    else
        echo "[ERROR] Complemento no encontrado: $complemento"
        exit 1
    fi
}

prop_or_default() {
    local val="$(getprop "$1")"
  [ -n "$val" ] && echo "$val" || echo "$2"
}


# actualizacion 1.8 el script no tenia permisos....... . _  .
set_permissions_module() {
    modpath="$1"
    log_file="$2"

    [ -z "$modpath" ] && { [ -n "$log_file" ] && echo "[WARN] modpath vacio" >> "$log_file"; return 1; }
    [ ! -d "$modpath" ] && { [ -n "$log_file" ] && echo "[WARN] $modpath no existe" >> "$log_file"; return 1; }

    if command -v set_perm_recursive >/dev/null 2>&1; then
        set_perm_recursive "$modpath" 0 0 0755 0644
        set_perm "$modpath/addon/Volume-Key-Selector/tools/arm/keycheck" 0 0 0755
        set_perm "$modpath/addon/Volume-Key-Selector/tools/x86/keycheck" 0 0 0755
        set_perm "$modpath/addon/jq/arm64/jq" 0 0 0755
    else
        find "$modpath" -type d -exec chmod 0755 {} \;
        find "$modpath" -type f -exec chmod 0644 {} \;
        chmod 0755 "$modpath/service.sh" "$modpath/post-fs-data.sh" 2>/dev/null
        chmod 0755 "$modpath/addon/Volume-Key-Selector/tools/arm/keycheck" 2>/dev/null
        chmod 0755 "$modpath/addon/Volume-Key-Selector/tools/x86/keycheck" 2>/dev/null
        chmod 0755 "$modpath/addon/jq/arm64/jq" 2>/dev/null
    fi

    [ -n "$log_file" ] && echo "[OK] Permisos asignados en $modpath" >> "$log_file"
    return 0
}

set_permissions() {
    set_permissions_module "$NEWMODPATH"
}

progress_bar() {
    local rueda='-\|/'  # Algo un poco mas atractivo
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
    if [ -f "$BACKUP_FILE" ]; then
        log_info "Backup ya existe en $BACKUP_FILE"
        log_info "Creando uno nuevo con timestamp"
        BACKUP_FILE="$NEWMODPATH/configs/kitsuneping_original_backup_$(get_time_stamp).conf"
        return 0
    fi

    touch "$BACKUP_FILE"

    {
        echo "ro.ril.hsdpa.category=$(getprop_or_default ro.ril.hsdpa.category)"
        echo "ro.ril.hsupa.category=$(getprop_or_default ro.ril.hsupa.category)"
        echo "ro.ril.lte.category=$(getprop_or_default ro.ril.lte.category)"
        echo "ro.ril.ltea.category=$(getprop_or_default ro.ril.ltea.category)"
        echo "ro.ril.nr5g.category=$(getprop_or_default ro.ril.nr5g.category)"
    } >> "$BACKUP_FILE"
}

set_selinux_enforce() {
    enforce_state="$1"
    log_file="$2"

    if [ "$(id -u)" -ne 0 ]; then
        [ -n "$log_file" ] && echo "[SYS][ERROR] root requerido" >> "$log_file"
        return 1
    fi

    case "$enforce_state" in
        0|1) :;;
        *)
            [ -n "$log_file" ] && echo "[SYS][ERROR] Valor invalido: $enforce_state" >> "$log_file"
            return 2
            ;;
    esac

    if setenforce "$enforce_state" 2>>"$log_file"; then
        [ -n "$log_file" ] && echo "[SYS][OK] SELinux temporal: $(getenforce)" >> "$log_file"
    else
        [ -n "$log_file" ] && echo "[SYS][ERROR] Fallo setenforce" >> "$log_file"
        return 3
    fi

    return 0
}

