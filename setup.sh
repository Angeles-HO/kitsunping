#!/system/bin/sh

# --- Configuracion inicial ---
INSTALL_START_TIME=$(date +%s)
SKIPMOUNT=false          # Default para instalador Magisk
AUTOMOUNT=true           # Montaje automatico
DEBUG=true               # Mostrar logs en archivo (futuro)
POSTFSDATA=true          # Ejecutar post-fs-data
LATESTARTSERVICE=true    # Ejecutar late_start service (service.sh)
CLEANSERVICE=true        # Limpiar archivos previos si existen
PROPFILE=true            # Cargar system.prop

# --- Metadatos ---
dte=$(date)
improviserr="@heistomega | @angeles_ho"

# --- Complementos ---
complemento_kitsutils="addon/functions/utils/Kitsutils.sh"
complemento_debug="addon/functions/debug/shared_errors.sh"
complemento_net_calibrate="addon/Net_Calibrate/calibrate.sh"
complemento_VKS="addon/Volume-Key-Selector/utils.sh"

# Cargar utilidades base y permisos
. "$NEWMODPATH/$complemento_kitsutils"
set_permissions

# Verificacion y carga de complementos
verify_complemento "$complemento_VKS"
verify_complemento "$complemento_kitsutils"
verify_complemento "$complemento_debug"
verify_complemento "$complemento_net_calibrate"

divider="══════════════════════════════════════════════════"

# Backup inicial (solo una vez)
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
echo "RAM INFO        = $(free -m | awk '/^Mem:/{print $2}')"
echo "ANDROID VERSION = $(prop_or_default ro.build.version.release "N/A")"
echo "${divider}"
echo "❖ Contacto:"
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

# Espera de entrada por 60s
if $VKSEL 60; then
    echo "=============================="
    MODE_SELECTION=0
    log_info "Fixed mode selected"

    # Valores fijos
    echo "ro.ril.hsupa.category=6" >> "$NEWMODPATH/configs/kitsuneping_static.conf"
    echo "ro.ril.hsdpa.category=24" >> "$NEWMODPATH/configs/kitsuneping_static.conf"
    echo "ro.ril.lte.category=7" >> "$NEWMODPATH/configs/kitsuneping_static.conf"
    echo "ro.ril.ltea.category=6" >> "$NEWMODPATH/configs/kitsuneping_static.conf"

    # Aplicar cambios a system.prop
    cat "$NEWMODPATH/configs/kitsuneping_static.conf" >> "$NEWMODPATH/system.prop"
    echo "=============================="
else
    MODE_SELECTION=1
fi

# --- Modo Automatico ---
if [ "$MODE_SELECTION" -eq 1 ]; then
    log_info "Modo Automatico seleccionado"
    log_info "Starting network calibration..."
    log_info "This may take a while; ensure good connection and be patient"
    log_info "Backup already created at $NEWMODPATH/configs/kitsuneping_original_backup.conf"

    log_info "Starting calibration process..."
    
    calibrate_network_settings 10 2> >(tee "/sdcard/seguimiento2.log" >&2) | tee "$NEWMODPATH/logs/results.env"

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

# --- Finalizacion ---
progress_bar

INSTALL_END_TIME=$(date +%s)
INSTALL_DURATION=$((INSTALL_END_TIME - INSTALL_START_TIME))
echo "${divider}"
echo "❖ Installation completed in ${INSTALL_DURATION} seconds."
echo "${divider}"