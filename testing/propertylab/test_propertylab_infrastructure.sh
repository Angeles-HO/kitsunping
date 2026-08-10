#!/bin/sh

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in /*) : ;; *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;; esac
TEST_DIR=${SCRIPT_PATH%/*}
ROOT_DIR=${TEST_DIR%/*}
REPO_DIR=${ROOT_DIR%/*}

# shellcheck disable=SC1090
. "$ROOT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM
LAB="$TMP_ROOT/propertylab"
cp -R "$REPO_DIR/PropertyLab" "$LAB"
chmod +x "$LAB/bin/propertylab.sh"

PROPERTYLAB_MODDIR="$LAB" PROPERTYLAB_LOG_DIR="$LAB/logs" PROPERTYLAB_STATE_DIR="$LAB/state" \
PROPERTYLAB_PRODUCTION_MODULE_DIR="$TMP_ROOT/no-production-module" \
    sh "$LAB/bin/propertylab.sh" preflight > "$TMP_ROOT/preflight.out"
assert_file_contains "$TMP_ROOT/preflight.out" 'PROPERTYLAB_PREFLIGHT=ok' 'empty manifest preflight succeeds'
assert_file_contains "$LAB/state/last_run" 'experiment_id=pl-control-empty-v1' 'preflight records static experiment id'

mkdir -p "$TMP_ROOT/Kitsunping"
if PROPERTYLAB_MODDIR="$LAB" PROPERTYLAB_LOG_DIR="$LAB/logs" PROPERTYLAB_STATE_DIR="$LAB/state" \
    PROPERTYLAB_PRODUCTION_MODULE_DIR="$TMP_ROOT/Kitsunping" \
    sh "$LAB/bin/propertylab.sh" preflight >/dev/null 2>&1; then
    fail 'preflight rejects enabled production Kitsunping module'
else
    pass 'preflight rejects enabled production Kitsunping module'
fi

touch "$TMP_ROOT/Kitsunping/disable"
PROPERTYLAB_MODDIR="$LAB" PROPERTYLAB_LOG_DIR="$LAB/logs" PROPERTYLAB_STATE_DIR="$LAB/state" \
PROPERTYLAB_PRODUCTION_MODULE_DIR="$TMP_ROOT/Kitsunping" \
    sh "$LAB/bin/propertylab.sh" preflight >/dev/null
pass 'preflight permits disabled production Kitsunping module'

if grep -R -E '(resetprop|setprop|svc[[:space:]]+wifi|cmd[[:space:]]+wifi)' "$LAB/bin" "$LAB/lib" "$LAB/service.sh" "$LAB/uninstall.sh" >/dev/null 2>&1; then
    fail 'PropertyLab infrastructure contains a forbidden device mutation command'
else
    pass 'PropertyLab infrastructure contains no device mutation command'
fi

finish