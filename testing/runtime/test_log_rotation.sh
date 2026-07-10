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
LOG_DIR="$MODDIR/logs"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/daemon.log"
POLICY_LOG="$LOG_DIR/policy.log"
SERVICES_LOG="$LOG_DIR/services_daemon.log"

printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' > "$LOG_FILE"
printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' > "$POLICY_LOG"
printf 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' > "$SERVICES_LOG"

DAEMON_LOG_ROTATE_MAX_BYTES=64

# shellcheck disable=SC1090
. "$REPO_DIR/addon/functions/daemon_utils.sh"

daemon_rotate_runtime_logs

assert_file_exists "$LOG_FILE" "daemon log remains present after rotation"
assert_file_exists "$POLICY_LOG" "policy log remains present after rotation"
assert_file_exists "$SERVICES_LOG" "services log remains present after rotation"

assert_file_exists "${LOG_FILE}.1" "daemon log backup is created"
assert_file_exists "${POLICY_LOG}.1" "policy log backup is created"
assert_file_exists "${SERVICES_LOG}.1" "services log backup is created"

size_daemon=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d '[:space:]')
size_policy=$(wc -c < "$POLICY_LOG" 2>/dev/null | tr -d '[:space:]')
size_services=$(wc -c < "$SERVICES_LOG" 2>/dev/null | tr -d '[:space:]')

assert_eq "0" "$size_daemon" "daemon log is truncated after rotation"
assert_eq "0" "$size_policy" "policy log is truncated after rotation"
assert_eq "0" "$size_services" "services log is truncated after rotation"

finish
