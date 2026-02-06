#!/system/bin/sh
# profile_runner.sh - moved run_profile_script to separate file for reuse in service.sh
# Part of Kitsunping - policy/executor.sh and scripts/service.sh

# This file is usually sourced by executor.sh. When sourced, $0 is the caller.
# Prefer caller-provided SCRIPT_DIR/NEWMODPATH; otherwise derive safely.

if [ -z "${SCRIPT_DIR:-}" ] || [ ! -d "${SCRIPT_DIR:-/}" ]; then
    SCRIPT_DIR="${0%/*}"
fi

if [ -z "${NEWMODPATH:-}" ] || [ ! -d "${NEWMODPATH:-/}" ]; then
    case "$SCRIPT_DIR" in
        */addon/policy) NEWMODPATH="${SCRIPT_DIR%%/addon/policy}" ;;
        */addon/*) NEWMODPATH="${SCRIPT_DIR%%/addon/*}" ;;
        */addon) NEWMODPATH="${SCRIPT_DIR%%/addon}" ;;
        *) NEWMODPATH="${SCRIPT_DIR%/*}" ;;
    esac
fi

# Provide compatibility vars without clobbering the caller when sourced.
: "${MODDIR:=$NEWMODPATH}"
: "${ADDON_DIR:=$NEWMODPATH/addon}"

SERVICES_LOGS_CALLED_BY_DAEMON="$NEWMODPATH/logs/services_daemon.log"
# Load essential functions
[ -f "$NEWMODPATH/addon/functions/utils/Kitsutils.sh" ] && . "$NEWMODPATH/addon/functions/utils/Kitsutils.sh"


run_profile_script() {
    profile_name="$1"
    profile_script=""

    case "$profile_name" in
        speed) profile_script="$NEWMODPATH/net_profiles/speed_profile.sh" ;;
        stable) profile_script="$NEWMODPATH/net_profiles/stable_profile.sh" ;;
        gaming) profile_script="$NEWMODPATH/net_profiles/gaming_profile.sh" ;;
        *) echo "[SYS][SERVICE][WARN] Perfil desconocido: $profile_name" >> "$SERVICES_LOGS_CALLED_BY_DAEMON"; return 1 ;;
    esac

    if [ ! -f "$profile_script" ]; then
        echo "[SYS][SERVICE][WARN] Script de perfil no encontrado: $profile_script" >> "$SERVICES_LOGS_CALLED_BY_DAEMON"
        return 1
    fi

    echo "[SYS][SERVICE] Aplicando perfil: $profile_name ($profile_script)" >> "$SERVICES_LOGS_CALLED_BY_DAEMON"
    . "$profile_script" >>"$SERVICES_LOGS_CALLED_BY_DAEMON" 2>&1 || {
        echo "[SYS][SERVICE][ERROR] Fallo al aplicar perfil: $profile_name" >> "$SERVICES_LOGS_CALLED_BY_DAEMON"
        return 1
    }

    return  0
}
