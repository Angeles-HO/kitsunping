#!/system/bin/sh
# Compatibility wrapper: addon/policy -> policy/rules

SCRIPT_DIR="${0%/*}"
MODDIR="${SCRIPT_DIR%/addon/policy}"
RULES_SH="$MODDIR/policy/rules/decide_profile.sh"

if [ -f "$RULES_SH" ]; then
    . "$RULES_SH"
fi
