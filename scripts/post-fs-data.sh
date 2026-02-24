#!/system/bin/sh
# =============================================================================
# post-fs-data.sh:
# This stage is BLOCKING. The boot process is paused before execution is done, or 40 seconds have passed.
# Scripts run before any modules are mounted. This allows a module developer to dynamically adjust their modules before it gets mounted.
# This stage happens before Zygote is started, which pretty much means everything in Android
# WARNING: using setprop will deadlock the boot process! Please use resetprop -n <prop_name> <prop_value> instead.
# Only run scripts in this mode if necessary.
# ![Documentation oficial](https://topjohnwu.github.io/Magisk/guides.html#boot-scripts)
# =============================================================================
# Ensure SELinux is restored on exit
# post-fs-data runs very early; avoid a broken trap if Kitsutils couldn't be sourced.
set_selinux_enforce() {
    # Usage: set_selinux_enforce <0|1> [logfile]
    local mode="$1" logfile="$2"
    case "$mode" in 0|1) :;; *) return 2;; esac
    if command -v setenforce >/dev/null 2>&1; then
        setenforce "$mode" 2>/dev/null
    fi
    [ -n "$logfile" ] && command -v getenforce >/dev/null 2>&1 && echo "[SYS][OK] SELinux temporary: $(getenforce)" >> "$logfile"
    return 0
}
trap 'set_selinux_enforce 1 "$SERVICES_LOGS"' EXIT INT TERM
# Global vars and paths
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

# Detectar chipset; solo ejecutar ajustes Qualcomm (WCNSS) si es Qualcomm
CHIPSET=$(getprop ro.board.platform | tr '[:upper:]' '[:lower:]')

# Set permissions
set_permissions_module "$MODDIR" "" 0

# SELinux 
# permissive 0 
# enforcing 1
log "Setting SELinux to permissive temporarily"
set_selinux_enforce 0 "$SERVICES_LOGS"

log "post-fs-data stage: skip running service.sh (Magisk late_start will run it)"


if is_qualcomm; then
    log "Qualcomm detected ($CHIPSET): profile application deferred to executor/service"
elif is_mtk; then
    log "MediaTek detected ($CHIPSET): profile application deferred to executor/service"
else
    log "Other chipset ($CHIPSET): no chipset-specific action in post-fs-data"
    log "for non-Qualcomm/MediaTek devices, profile application will be deferred to executor/service"
fi
# if the chipset its not in the list, the module will apply some profiles, but for safety, are limited to the ones that are not related to wifi, because the module is focused on wifi performance, and the wifi profiles are the most risky to apply in a wrong chipset, so for non-Qualcomm/MediaTek devices, the module will apply some profiles, but for safety, are limited to the ones that are not related to wifi, because the module is focused on wifi performance, and the wifi profiles are the most risky to apply in a wrong chipset
# if you want to include your chipset, please contact the developer with your device model and chipset information, and if possible, with a logcat of the module applying the profiles in your device, to help the developer to include your chipset in the future updates
# github: github.com/Angeles-HO/Kitsunping

log "Restoring SELinux enforcing"
set_selinux_enforce 1 "$SERVICES_LOGS"

log "Execution completed"
# Exit 0 for no whait 40s to this script finish default by magisk
exit 0 