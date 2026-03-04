#!/system/bin/sh
# Compatibility wrapper: addon/Net_Calibrate -> calibration

if [ -z "${NEWMODPATH:-}" ] || [ ! -d "${NEWMODPATH:-/}" ]; then
    if [ -n "${MODDIR:-}" ] && [ -d "${MODDIR:-/}" ]; then
        NEWMODPATH="$MODDIR"
    else
        _caller_dir="${0%/*}"
        case "$_caller_dir" in
            */addon/Net_Calibrate) NEWMODPATH="${_caller_dir%%/addon/Net_Calibrate}" ;;
            */addon/*) NEWMODPATH="${_caller_dir%%/addon/*}" ;;
            */addon) NEWMODPATH="${_caller_dir%%/addon}" ;;
            *) NEWMODPATH="${_caller_dir%/*}" ;;
        esac
    fi
fi

: "${MODDIR:=$NEWMODPATH}"

CALIBRATE_NEW="$MODDIR/calibration/calibrate.sh"
if [ -f "$CALIBRATE_NEW" ]; then
    . "$CALIBRATE_NEW"
    return 0 2>/dev/null || exit 0
fi

echo "[ERROR] calibration script not found: $CALIBRATE_NEW" >&2
return 1 2>/dev/null || exit 1
