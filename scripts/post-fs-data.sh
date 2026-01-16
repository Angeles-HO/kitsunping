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

# Initial log
echo "exec1: $(date '+%Y-%m-%d %H:%M:%S') ====" > "$SERVICES_LOGS"

# Path check
if [ -z "$MODPATH" ]; then
    echo "[ERROR] MODPATH is not defined" >> "$SERVICES_LOGS"
  exit 1
fi

# Load default utils
UTIL_FUNCTIONS="/data/adb/magisk/util_functions.sh"
if [ -f "$UTIL_FUNCTIONS" ]; then
  . "$UTIL_FUNCTIONS" 2>> "$SERVICES_LOGS"
else
    echo "util_functions.sh not found" >> "$SERVICES_LOGS"
fi

log() {
    echo "[LOG][$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$SERVICES_LOGS"
}

# Common utilities
COMMON_UTIL="$MODPATH/addon/functions/utils/Kitsutils.sh"
if [ -f "$COMMON_UTIL" ]; then
    . "$COMMON_UTIL"
else
    log "Could not load $COMMON_UTIL"
fi

# Set permissions
set_permissions_module "$MODPATH" "$SERVICES_LOGS"

# SELinux 
# permissive 0 
# enforcing 1
log "Setting SELinux to permissive temporarily"
set_selinux_enforce 0 "$SERVICES_LOGS"

log "Waiting for sys.boot_completed"
while true; do
    boot=$(getprop sys.boot_completed)
    [ "$boot" = "1" ] && break
    sleep 1
done

log "System boot completed; running services"
MAIN_SERVICE="$MODPATH/service.sh"
BACKUP_SERVICE="/data/adb/modules/Kitsun_ping_backup/service.sh"

if [ -f "$MAIN_SERVICE" ]; then
    log "Running main service"
    if ! sh "$MAIN_SERVICE" >> "$SERVICES_LOGS" 2>&1; then
        log "Main service failed, trying backup"
        if [ -f "$BACKUP_SERVICE" ]; then
            if ! sh "$BACKUP_SERVICE" >> "$SERVICES_LOGS" 2>&1; then
                log "Backup service failed"
            else
                log "Backup service executed successfully"
            fi
        else
            log "No backup service found"
        fi
    else
        log "Main service executed successfully"
    fi
else
    log "Main service not found"
fi

log "Restoring SELinux enforcing"
set_selinux_enforce 1 "$SERVICES_LOGS"

log "Execution completed"
exit 0