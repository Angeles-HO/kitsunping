#!/system/bin/sh
# Compatibility wrapper: addon/policy -> policy/executor

SCRIPT_DIR="${0%/*}"
MODDIR="${SCRIPT_DIR%/addon/policy}"
RUNNER_SH="$MODDIR/policy/executor/profile_runner.sh"

if [ -f "$RUNNER_SH" ]; then
    . "$RUNNER_SH"
fi
