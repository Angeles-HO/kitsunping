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
complemento_net_calibrate="calibration/calibrate.sh"
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

# Ensure runtime directories exist even when ZIP packaging omits empty folders.
mkdir -p "$NEWMODPATH/cache" "$NEWMODPATH/logs" "$NEWMODPATH/calibration/data/cache" 2>/dev/null || true

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

# Legacy fix: if base backup exists but is empty (tracked placeholder from old builds),
# repopulate it from the oldest non-empty timestamped snapshot.
repair_base_backup_if_empty() {
    base_backup_file="$1"
    base_backup_dir="${base_backup_file%/*}"
    donor_backup=""

    [ -f "$base_backup_file" ] || return 0
    [ -s "$base_backup_file" ] && return 0

    for candidate_backup in "$base_backup_dir"/kitsuneping_original_backup_*.conf; do
        [ -f "$candidate_backup" ] || continue
        [ -s "$candidate_backup" ] || continue
        donor_backup="$candidate_backup"
        break
    done

    if [ -z "$donor_backup" ]; then
        log_warning "Base backup is empty and no snapshot is available to repair it"
        return 0
    fi

    if cp -f "$donor_backup" "$base_backup_file" 2>/dev/null; then
        chmod 0644 "$base_backup_file" 2>/dev/null || true
        log_info "Repaired empty base backup from snapshot: $donor_backup"
    else
        log_warning "Failed to repair empty base backup from: $donor_backup"
    fi
}

# Initial backup (only once)
log_info "Creating backup of original settings..."
backup_base_file="$NEWMODPATH/configs/kitsuneping_original_backup.conf"
repair_base_backup_if_empty "$backup_base_file"
backup_base_preexisting=0
[ -f "$backup_base_file" ] && backup_base_preexisting=1

if create_backup; then
    backup_created_path="${BACKUP_FILE:-$backup_base_file}"
    if [ "$backup_base_preexisting" -eq 1 ]; then
        log_info "Backup base already existed; new snapshot saved at $backup_created_path"
    else
        log_info "Backup created at $backup_created_path"
    fi
else
    log_warning "Backup could not be created"
fi

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
# Detect RAM and delegate to Kitsutils.sh (function persisted there)
detect_and_write_ram_props "$NEWMODPATH" >/dev/null 2>&1 || true
# Report RAM info from the written system.prop (fallback to free output)
RAM_INFO=$(grep -m1 '^persist.kitsunping.ram.size=' "$NEWMODPATH/system.prop" 2>/dev/null | cut -d= -f2 || echo "$(free -m | awk '/^Mem:/{print $2}')MB")
RAM_CLASS=$(grep -m1 '^persist.kitsunping.ram.class=' "$NEWMODPATH/system.prop" 2>/dev/null | cut -d= -f2 || echo "unknown")
echo "RAM INFO        = ${RAM_INFO} (class: ${RAM_CLASS})"
echo "ANDROID VERSION = $(prop_or_default ro.build.version.release "N/A")"
echo "${divider}"
echo "❖ Contact:"
echo "${divider}"
echo "Github      : https://github.com/Angeles-HO"
echo "${divider}"
echo "❖ Installation in progress..."
echo "${divider}"

# --- Mode selection ---
log_info "Tip: you can apply static fix first, reboot, then run manual calibration later"
log_info "Select operation mode:"
log_info "  [Vol+] Fixed mode"
log_info "  [Vol-] Automatic mode (~4 mins)"
log_info "  [None] Automatic mode (~4 mins)"

apply_fixed_mode() {
    echo "=============================="
    log_info "Fixed mode selected"

    # Fixed values
    echo "ro.ril.hsupa.category=6" >> "$NEWMODPATH/configs/kitsuneping_static.conf"
    echo "ro.ril.hsdpa.category=24" >> "$NEWMODPATH/configs/kitsuneping_static.conf"
    echo "ro.ril.lte.category=7" >> "$NEWMODPATH/configs/kitsuneping_static.conf"
    echo "ro.ril.ltea.category=6" >> "$NEWMODPATH/configs/kitsuneping_static.conf"

    # Apply changes to system.prop
    cat "$NEWMODPATH/configs/kitsuneping_static.conf" >> "$NEWMODPATH/system.prop"
    echo "=============================="
}

requested_mode_raw="${INSTALL_MODE:-}"
requested_mode=""
if [ -n "$requested_mode_raw" ]; then
    requested_mode_lower=$(echo "$requested_mode_raw" | tr '[:upper:]' '[:lower:]')
    case "$requested_mode_lower" in
        fixed|fijo|0)
            requested_mode="fixed"
            ;;
        auto|automatic|automatico|1)
            requested_mode="auto"
            ;;
        *)
            log_warning "Unknown INSTALL_MODE='$requested_mode_raw'; falling back to VKSEL"
            ;;
    esac
fi

## If no key is pressed, default to automatic mode
## if Vol + is pressed, fixed mode
## if Vol - is pressed, automatic mode
if [ "$requested_mode" = "fixed" ]; then
    MODE_SELECTION=0
    log_info "INSTALL_MODE requested fixed mode"
    apply_fixed_mode
elif [ "$requested_mode" = "auto" ]; then
    MODE_SELECTION=1
    log_info "INSTALL_MODE requested automatic mode"
else
    vksel_timeout="${INSTALL_VK_TIMEOUT:-$(getprop persist.kitsunping.install_vk_timeout 2>/dev/null | tr -d '\r\n')}"
    vksel_timeout="$(uint_or_default "$vksel_timeout" "20")"
    [ "$vksel_timeout" -lt 5 ] && vksel_timeout=5
    [ "$vksel_timeout" -gt 60 ] && vksel_timeout=60
    log_info "Waiting ${vksel_timeout}s for key selection (INSTALL_VK_TIMEOUT / persist.kitsunping.install_vk_timeout)"

    if $VKSEL "$vksel_timeout"; then
        MODE_SELECTION=0
        apply_fixed_mode
    else
        MODE_SELECTION=1
    fi
fi


# --- Automatic Mode ---
if [ "$MODE_SELECTION" -eq 1 ]; then
    log_info "Automatic Mode selected"
    log_info "Starting network calibration..."
    log_info "This may take a while; ensure good connection and be patient"
    if [ -n "${backup_created_path:-}" ]; then
        log_info "Backup ready at $backup_created_path"
    else
        log_info "Backup path unavailable; continuing with calibration"
    fi

    log_info "Starting calibration process..."
    log_info "This process will run multiple tests to determine the optimal network settings for your device."
    log_info "Please wait and do not interrupt the process/move the device. It may take several minutes to complete."
    
    # POSIX-safe stderr handling: capture once, then mirror to installer stderr and persistent trace log.
    trace_log_file="/sdcard/trace_log2.log"
    trace_tmp_err="$NEWMODPATH/logs/calibration.stderr.log"
    : > "$trace_tmp_err"

    calibrate_start_ts="$(date +%s 2>/dev/null || echo 0)"
    log_info "Calibration stage started at ts=$calibrate_start_ts"

    progress_state_file="$NEWMODPATH/cache/calibrate.progress"
    calibrate_stdout_file="$NEWMODPATH/logs/calibration.stdout.log"
    : > "$calibrate_stdout_file"
    rm -f "$progress_state_file" 2>/dev/null || true

    # Run calibration in background and stream coarse stage updates from a separate state file.
    calibrate_network_settings 10 >"$calibrate_stdout_file" 2>"$trace_tmp_err" &
    calibrate_pid=$!

    last_progress_signature=""
    while kill -0 "$calibrate_pid" 2>/dev/null; do
        if [ -f "$progress_state_file" ]; then
            progress_pct=$(awk -F= '$1=="pct"{print $2; exit}' "$progress_state_file" 2>/dev/null)
            progress_stage=$(awk -F= '$1=="stage"{print $2; exit}' "$progress_state_file" 2>/dev/null)
            progress_msg=$(awk -F= '$1=="msg"{sub(/^[^=]*=/, ""); print; exit}' "$progress_state_file" 2>/dev/null)
            progress_signature="${progress_pct}|${progress_stage}|${progress_msg}"
            if [ -n "$progress_signature" ] && [ "$progress_signature" != "$last_progress_signature" ]; then
                log_info "Calibration progress [${progress_pct:-0}%][${progress_stage:-unknown}] ${progress_msg:-working}"
                last_progress_signature="$progress_signature"
            fi
        fi
        sleep 2
    done

    wait "$calibrate_pid"
    calibrate_rc=$?

    grep -E '^BEST_[A-Za-z0-9_]+=' "$calibrate_stdout_file" | tee "$NEWMODPATH/logs/results.env"
    if [ "$calibrate_rc" -ne 0 ]; then
        log_warning "Calibration process exited with code $calibrate_rc"
    fi

    calibrate_end_ts="$(date +%s 2>/dev/null || echo 0)"
    if [ "$calibrate_start_ts" -gt 0 ] 2>/dev/null && [ "$calibrate_end_ts" -ge "$calibrate_start_ts" ] 2>/dev/null; then
        calibrate_elapsed="$((calibrate_end_ts - calibrate_start_ts))"
        log_info "Calibration stage completed in ${calibrate_elapsed}s"
    fi

    if [ -s "$trace_tmp_err" ]; then
        cat "$trace_tmp_err" >&2
        cat "$trace_tmp_err" >> "$trace_log_file" 2>/dev/null || true
    fi

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