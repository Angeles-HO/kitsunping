#!/bin/sh
# Verifies the central Debug Mode policy without requiring Android services.

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) : ;;
    *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac
TEST_DIR=${SCRIPT_PATH%/*}
MODDIR=${TEST_DIR%/testing/runtime}
SHARED_ERRORS="$MODDIR/addon/functions/debug/shared_errors.sh"
POLICY_COMMON="$MODDIR/addon/functions/policy_common.sh"

FAIL=0

pass() { printf '[PASS] %s\n' "$1"; }
fail() { printf '[FAIL] %s\n' "$1" >&2; FAIL=1; }
assert_eq() {
    actual="$1"
    expected="$2"
    message="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$message"
    else
        fail "$message (expected=$expected actual=$actual)"
    fi
}

# The runtime helper reads this command first, matching Android's getprop path.
getprop() {
    case "$1" in
        persist.kitsunping.debug) printf '%s' "${TEST_DEBUG_MODE:-0}" ;;
        *) printf '%s' '' ;;
    esac
}

# shellcheck disable=SC1090
. "$POLICY_COMMON"
# shellcheck disable=SC1090
. "$SHARED_ERRORS"

TEST_DEBUG_MODE=0
normal_output="$(log_info 'hidden info' 2>&1)"
assert_eq "$normal_output" "" "normal mode suppresses informational logs"

ui_print() {
    printf '%s\n' "$1"
}
installer_output="$(log_info 'visible installer guidance' 2>&1)"
case "$installer_output" in
    *'visible installer guidance'*) pass "installer guidance bypasses runtime debug suppression" ;;
    *) fail "installer guidance bypasses runtime debug suppression (output=$installer_output)" ;;
esac
unset -f ui_print

normal_output="$(log_debug 'hidden debug' 2>&1)"
assert_eq "$normal_output" "" "normal mode suppresses debug logs"
normal_output="$(log_warning 'visible warning' 2>&1)"
case "$normal_output" in
    *'visible warning'*) pass "normal mode retains warnings" ;;
    *) fail "normal mode retains warnings (output=$normal_output)" ;;
esac

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT INT TERM
normal_file="$workdir/normal.txt"
debug_file="$workdir/debug.txt"
printf '%s\n' 'must-not-persist' | atomic_write "$normal_file" debug_only
if [ -e "$normal_file" ]; then
    fail "normal mode skips debug-only atomic writes"
else
    pass "normal mode skips debug-only atomic writes"
fi
printf '%s\n' 'runtime-state' | atomic_write "$normal_file"
assert_eq "$(cat "$normal_file")" "runtime-state" "normal atomic writes remain persistent"

TEST_DEBUG_MODE=1
debug_output="$(log_info 'visible info' 2>&1)"
case "$debug_output" in
    *'visible info'*) pass "debug mode permits informational logs" ;;
    *) fail "debug mode permits informational logs (output=$debug_output)" ;;
esac
debug_output="$(log_debug 'visible debug' 2>&1)"
case "$debug_output" in
    *'visible debug'*) pass "debug mode permits debug logs" ;;
    *) fail "debug mode permits debug logs (output=$debug_output)" ;;
esac
printf '%s\n' 'debug-persisted' | atomic_write "$debug_file" debug_only
assert_eq "$(cat "$debug_file")" "debug-persisted" "debug mode writes debug-only atomic data"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
