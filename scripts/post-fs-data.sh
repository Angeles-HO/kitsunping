#!/system/bin/sh
# =============================================================================
# post-fs-data.sh: Script ejecutado despues del montaje del sistema de archivos
# =============================================================================

# Variables de entorno
MODDIR=${0%/*}
MODPATH="$MODDIR"
LOGS_DIR="$MODPATH/logs"
SERVICES_LOGS="$LOGS_DIR/Kitsun_ping_debug_post_fs_data.log"

# Crear directorio de logs
mkdir -p "$LOGS_DIR"

# Log inicial
echo "exec1: $(date '+%Y-%m-%d %H:%M:%S') ====" > "$SERVICES_LOGS"

# Comprobar ruta
if [ -z "$MODPATH" ]; then
  echo "[ERROR] MODPATH no esta definido" >> "$SERVICES_LOGS"
  exit 1
fi

# Cargar utils por defecto
UTIL_FUNCTIONS="/data/adb/magisk/util_functions.sh"
if [ -f "$UTIL_FUNCTIONS" ]; then
  . "$UTIL_FUNCTIONS" 2>> "$SERVICES_LOGS"
else
  echo "util_functions.sh no encontrado" >> "$SERVICES_LOGS"
fi

log() {
    echo "[LOG][$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$SERVICES_LOGS"
}

# Utilidades comunes
COMMON_UTIL="$MODPATH/addon/functions/utils/Kitsutils.sh"
if [ -f "$COMMON_UTIL" ]; then
    . "$COMMON_UTIL"
else
    log "No se pudo cargar $COMMON_UTIL"
fi

# Establecer permisos
set_permissions_module "$MODPATH" "$SERVICES_LOGS"

# SELinux 
# permissive 0 
# enforcing 1
log "Estableciendo SELinux permisivo temporalmente"
set_selinux_enforce 0 "$SERVICES_LOGS"

log "Esperando sys.boot_completed"
while true; do
    boot=$(getprop sys.boot_completed)
    [ "$boot" = "1" ] && break
    sleep 1
done

log "Sistema iniciado ejecutando servicios"
MAIN_SERVICE="$MODPATH/service.sh"
BACKUP_SERVICE="/data/adb/modules/Kitsun_ping_backup/service.sh"

if [ -f "$MAIN_SERVICE" ]; then
    log "Ejecutando servicio principal"
    if ! sh "$MAIN_SERVICE" >> "$SERVICES_LOGS" 2>&1; then
        log "Fallo servicio principal, intentando backup"
        if [ -f "$BACKUP_SERVICE" ]; then
            if ! sh "$BACKUP_SERVICE" >> "$SERVICES_LOGS" 2>&1; then
                log "Fallo en servicio de backup"
            else
                log "Servicio backup ejecutado exitosamente"
            fi
        else
            log "No existe servicio de backup"
        fi
    else
        log "Servicio principal ejecutado exitosamente"
    fi
else
    log "No existe servicio principal"
fi

log "Restaurando SELinux enforcing"
set_selinux_enforce 1 "$SERVICES_LOGS"

log "Ejecucion completada"
exit 0