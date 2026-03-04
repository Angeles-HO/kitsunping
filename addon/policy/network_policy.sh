#!/system/bin/sh
# Compatibility wrapper: addon/policy -> policy/engine

SCRIPT_DIR="${0%/*}"
MODDIR="${SCRIPT_DIR%/addon/policy}"
ENGINE_SH="$MODDIR/policy/engine/network_policy.sh"

if [ -f "$ENGINE_SH" ]; then
    exec /system/bin/sh "$ENGINE_SH" "$@"
fi

exit 1
