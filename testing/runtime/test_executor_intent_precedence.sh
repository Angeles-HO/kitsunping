#!/bin/sh

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) : ;;
    *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac

TEST_DIR=${SCRIPT_PATH%/*}
ROOT_DIR=${TEST_DIR%/*}
REPO_DIR=${ROOT_DIR%/*}

# shellcheck disable=SC1090
. "$ROOT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

MODDIR="$TMP_ROOT/mod"
mkdir -p "$MODDIR/cache" "$MODDIR/logs"
cp -R "$REPO_DIR/policy" "$MODDIR/"
cp -R "$REPO_DIR/addon" "$MODDIR/"

# The request is newer than the event that woke the executor. Keeping current
# equal to request lets this fixture observe target resolution without running
# device profile scripts.
printf '%s' 'gaming' > "$MODDIR/cache/policy.request"
printf '%s' 'gaming' > "$MODDIR/cache/policy.current"

EVENT_NAME='PROFILE_CHANGED' \
EVENT_DETAILS='from=gaming to=stable transport=wifi' \
sh "$MODDIR/policy/executor/executor.sh"
rc=$?

target_profile=$(cat "$MODDIR/cache/policy.target" 2>/dev/null || echo '')
assert_rc 0 "$rc" "executor completes precedence fixture"
assert_eq 'gaming' "$target_profile" "current policy.request wins over historical PROFILE_CHANGED target"

finish