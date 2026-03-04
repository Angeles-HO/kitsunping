#!/system/bin/sh
# Compatibility wrapper: scripts -> installer

SCRIPT_DIR="${0%/*}"
MODDIR="${SCRIPT_DIR%/scripts}"
TARGET_SH="$MODDIR/installer/post-fs-data.sh"

if [ -f "$TARGET_SH" ]; then
    exec /system/bin/sh "$TARGET_SH" "$@"
fi

exit 1
