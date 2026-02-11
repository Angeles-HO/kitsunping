#!/system/bin/sh
# SORRY FOR MUCH Logs AND COMMENTS, IT'S FOR DEBUGGING AND MAINTENANCE PURPOSES, im trying to make it easy to understand
# --- Global Vars ---
INSTALL_START_TIME=$(date +%s)
SKIPMOUNT=false          # Default for Magisk installer
AUTOMOUNT=true           # Automatic mounting
DEBUG=true               # Show logs in file (future)
POSTFSDATA=true          # Execute early_start service (post-fs-data.sh)
LATESTARTSERVICE=true    # Execute late_start service (service.sh)
CLEANSERVICE=true        # Clean previous files if they exist
PROPFILE=true            # Load system.prop

# --- Metadata ---
dte=$(date)
improviserr="@Angeles_ho"

# --- Complements ---
complemento_kitsutils="addon/functions/utils/Kitsutils.sh"
complemento_debug="addon/functions/debug/shared_errors.sh"
complemento_net_calibrate="addon/Net_Calibrate/calibrate.sh"
complemento_VKS="addon/Volume-Key-Selector/utils.sh"

# --- Path normalization ---
# setup.sh is typically sourced by Magisk's update-binary. In that context:
# - $MODPATH is expected to be set by the installer
# - $NEWMODPATH may be unset depending on installer implementation
# If NEWMODPATH/MODPATH are empty, sourcing "$NEWMODPATH/..." becomes "/addon/..." and fails.
if [ -z "${NEWMODPATH:-}" ]; then
    NEWMODPATH="${MODPATH:-}"
fi

# If executed manually (not via Magisk), try to infer module root from this script path.
if [ -z "${NEWMODPATH:-}" ]; then
    _self="$0"
    case "$_self" in
        /*) : ;;
        *) _self="$PWD/$_self" ;;
    esac
    if command -v readlink >/dev/null 2>&1; then
        _self=$(readlink -f "$_self" 2>/dev/null || echo "$_self")
    fi
    NEWMODPATH="${_self%/*}"
fi

# Keep MODPATH consistent when running outside Magisk.
if [ -z "${MODPATH:-}" ]; then
    MODPATH="$NEWMODPATH"
fi

# Load base utilities and permissions
. "$NEWMODPATH/$complemento_kitsutils"
set_permissions
set_permissions_module "$NEWMODPATH" "/sdcard/kitsuneping_install_log.txt"

# Verification and loading of complements
verify_complemento "$complemento_VKS"
verify_complemento "$complemento_kitsutils"
verify_complemento "$complemento_debug"
verify_complemento "$complemento_net_calibrate"

divider="══════════════════════════════════════════════════"

# Initial backup (only once)
log_info "Creating backup of original settings..."
create_backup
log_info "Backup created at $NEWMODPATH/configs/kitsuneping_original_backup.conf"

# --- Installation info ---
echo "${divider}"
echo "❖ Information"
echo "${divider}"
echo "Date      : ${dte}"
echo "Improviser: ${improviserr}"
echo "Module    : ${MODID}"
echo "Version   : ${MODVERS}"
echo "${divider}"
echo "❖ Device Info"
echo "${divider}"
echo "DEVICE          = $(prop_or_default ro.product.model "N/A")"
echo "BRAND           = $(prop_or_default ro.product.system.brand "N/A")"
echo "MODEL           = $(prop_or_default ro.build.product "N/A")"
echo "KERNEL          = $(uname -r)"
echo "GPU INFO        = $(prop_or_default ro.hardware.egl "N/A")"
echo "CPU INFO        = $(prop_or_default ro.hardware "N/A")"
echo "PROCESSOR BRAND = $(prop_or_default ro.board.platform "N/A")"
echo "CPU ARCH        = $(prop_or_default ro.product.cpu.abi "N/A")"
# TODO: add ram info to system.prop, to usage to calc a value to use in profiles: persist.kitsunping.ram.size, *.habiablelity, etc
echo "RAM INFO        = $(free -m | awk '/^Mem:/{print $2}')"
echo "ANDROID VERSION = $(prop_or_default ro.build.version.release "N/A")"
echo "${divider}"
echo "❖ Contact:"
echo "${divider}"
echo "Github      : https://github.com/Angeles-HO"
echo "${divider}"
echo "❖ Installation in progress..."
echo "${divider}"

# --- Mode selection ---
log_info "Select operation mode:"
log_info "  [Vol+] Fixed mode"
log_info "  [Vol-] Automatic mode (~4 mins)"
log_info "  [None] Automatic mode (~4 mins)"

## If no key is pressed, default to automatic mode
## if Vol + is pressed, fixed mode
## if Vol - is pressed, automatic mode
if $VKSEL 60; then
    echo "=============================="
    MODE_SELECTION=0
    log_info "Fixed mode selected"

    # Fixed values
    echo "ro.ril.hsupa.category=6" >> "$NEWMODPATH/configs/kitsuneping_static.conf"
    echo "ro.ril.hsdpa.category=24" >> "$NEWMODPATH/configs/kitsuneping_static.conf"
    echo "ro.ril.lte.category=7" >> "$NEWMODPATH/configs/kitsuneping_static.conf"
    echo "ro.ril.ltea.category=6" >> "$NEWMODPATH/configs/kitsuneping_static.conf"

    # Apply changes to system.prop
    cat "$NEWMODPATH/configs/kitsuneping_static.conf" >> "$NEWMODPATH/system.prop"
    echo "=============================="
else
    MODE_SELECTION=1
fi


# --- Automatic Mode ---
if [ "$MODE_SELECTION" -eq 1 ]; then
    log_info "Automatic Mode selected"
    log_info "Starting network calibration..."
    log_info "This may take a while; ensure good connection and be patient"
    log_info "Backup already created at $NEWMODPATH/configs/kitsuneping_original_backup.conf"

    log_info "Starting calibration process..."
    log_info "This process will run multiple tests to determine the optimal network settings for your device."
    log_info "Please wait and do not interrupt the process/move the device. It may take several minutes to complete."
    
    calibrate_network_settings 10 2> >(tee "/sdcard/trace_log2.log" >&2) \
        | grep -E '^BEST_[A-Za-z0-9_]+=' \
        | tee "$NEWMODPATH/logs/results.env"

    if [ -s "$NEWMODPATH/logs/results.env" ]; then
        . "$NEWMODPATH/logs/results.env"

        SYSTEM_PROP="$NEWMODPATH/system.prop"
        touch "$SYSTEM_PROP"

        {
            [ -n "$BEST_ro_ril_hsupa_category" ] && echo "ro.ril.hsupa.category=$BEST_ro_ril_hsupa_category"
            [ -n "$BEST_ro_ril_hsdpa_category" ] && echo "ro.ril.hsdpa.category=$BEST_ro_ril_hsdpa_category"
            [ -n "$BEST_ro_ril_lte_category" ] && echo "ro.ril.lte.category=$BEST_ro_ril_lte_category"
            [ -n "$BEST_ro_ril_ltea_category" ] && echo "ro.ril.ltea.category=$BEST_ro_ril_ltea_category"
            [ -n "$BEST_ro_ril_nr5g_category" ] && echo "ro.ril.nr5g.category=$BEST_ro_ril_nr5g_category"
        } >> "$SYSTEM_PROP"
        log_info "Configuration applied successfully to system.prop"
    else
        log_error "No optimal values found in the log."
        exit 1
    fi
fi

# --- Finalization ---
progress_bar
# Auto mode but not have SIM card: 250s/280s
# Auto mode with SIM card: aprox 4/6 mins (420s-512s)
# Fixed mode: aprox 20s (static values + minimal processing)
INSTALL_END_TIME=$(date +%s) 
INSTALL_DURATION=$((INSTALL_END_TIME - INSTALL_START_TIME))
echo "${divider}"
echo "❖ Installation completed in ${INSTALL_DURATION} seconds."
echo "${divider}"