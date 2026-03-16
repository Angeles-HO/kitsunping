#!/bin/sh
# Local pre-release checks for module/app code paths that do not require router access.

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) : ;;
    *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac

TOOLS_DIR=${SCRIPT_PATH%/*}
REPO_DIR=${TOOLS_DIR%/*}
TOOLS_LOG_DIR="$TOOLS_DIR/logs"

mkdir -p "$TOOLS_LOG_DIR" 2>/dev/null || true
export KITSUNPING_POSIX_REPORT_DIR="$TOOLS_LOG_DIR"

cd "$REPO_DIR" || {
    echo "[FAIL] Cannot enter repo dir: $REPO_DIR" >&2
    exit 1
}

fail=0

run_step() {
    name="$1"
    shift
    echo "[RUN] $name"
    if "$@"; then
        echo "[OK ] $name"
    else
        echo "[FAIL] $name" >&2
        fail=1
    fi
    echo ""
}

run_step "POSIX compat (compat mode)" ./tools/check_posix_compat.sh compat
run_step "POSIX compat (strict mode)" ./tools/check_posix_compat.sh strict
run_step "Wi-Fi parsing samples" sh ./tools/test_wifi_parsing.sh

if [ "$fail" -ne 0 ]; then
    echo "Local checks completed with failures." >&2
    exit 1
fi

echo "Local checks completed successfully."
exit 0
