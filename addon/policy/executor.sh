#!/system/bin/sh
# Compatibility wrapper: addon/policy -> policy/executor

SCRIPT_DIR="${0%/*}"
MODDIR="${SCRIPT_DIR%/addon/policy}"
EXECUTOR_SH="$MODDIR/policy/executor/executor.sh"

if [ -f "$EXECUTOR_SH" ]; then
    exec /system/bin/sh "$EXECUTOR_SH" "$@"
fi

exit 1
