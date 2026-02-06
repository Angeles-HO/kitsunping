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
    log "Qualcomm detected ($CHIPSET): applying WCNSS_qcom_cfg.ini tweaks"

    CMDPREFIX=""
    if command -v magisk >/dev/null 2>&1; then
        if magisk --denylist ls >/dev/null 2>&1; then
            CMDPREFIX="magisk --denylist exec"
        elif magisk magiskhide ls >/dev/null 2>&1; then
            CMDPREFIX="magisk magiskhide exec"
        fi
    fi

    CHECK_DIRS="/system /vendor /product /system_ext"
    EXISTING_DIRS=""
    for dir in $CHECK_DIRS; do
        [ -d "$dir" ] && EXISTING_DIRS="$EXISTING_DIRS $dir"
    done

    if [ -n "$EXISTING_DIRS" ]; then
        CFGS=$($CMDPREFIX find $EXISTING_DIRS -type f -name WCNSS_qcom_cfg.ini 2>/dev/null)
    else
        CFGS=""
    fi

    for CFG in $CFGS; do
        [ -f "$CFG" ] || continue
        dst="$MODPATH$CFG"
        mkdir -p "$(dirname "$dst")"
        log "Migrating $CFG"
        $CMDPREFIX cp -af "$CFG" "$dst" 2>>"$SERVICES_LOGS"
        log "Modifying $dst"
        sed -i '/gChannelBondingMode24GHz=/d;/gChannelBondingMode5GHz=/d;/gForce1x1Exception=/d;/sae_enabled=/d;/BandCapability=/d;s/^END$/gChannelBondingMode24GHz=1\ngChannelBondingMode5GHz=1\ngForce1x1Exception=0\nsae_enabled=1\nBandCapability=0\nEND/g' "$dst"
    done

    if [ -z "$CFGS" ]; then
        log "No WCNSS_qcom_cfg.ini found; skipping migration"
    else
        mkdir -p "$MODPATH/system"
        mv -f "$MODPATH/vendor" "$MODPATH/system/vendor" 2>/dev/null
        mv -f "$MODPATH/product" "$MODPATH/system/product" 2>/dev/null
        mv -f "$MODPATH/system_ext" "$MODPATH/system/system_ext" 2>/dev/null
    fi
else
    log "Non-Qualcomm chipset ($CHIPSET)"
fi

log "Restoring SELinux enforcing"
set_selinux_enforce 1 "$SERVICES_LOGS"

log "Execution completed"
# Exit 0 for no whait 40s to this script finish default by magisk
exit 0 