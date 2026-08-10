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
trap 'KITSUNPING_MONITOR_DIR="$TMP_ROOT/monitor" KITSUNPING_MONITOR_MODDIR="$REPO_DIR" "$REPO_DIR/tools/performance_monitor_lifecycle.sh" stop >/dev/null 2>&1 || true; rm -rf "$TMP_ROOT"' EXIT INT TERM

MONITOR_ENV="KITSUNPING_MONITOR_DIR=$TMP_ROOT/monitor KITSUNPING_MONITOR_MODDIR=$REPO_DIR KITSUNPING_MONITOR_DEBUG_LEVEL=2 KITSUNPING_PERF_MONITOR_ALLOW=1 KITSUNPING_MONITOR_INTERVAL_SEC=60"
env $MONITOR_ENV sh "$REPO_DIR/tools/performance_monitor_lifecycle.sh" start > "$TMP_ROOT/start.out"
assert_file_contains "$TMP_ROOT/start.out" 'monitor started' 'monitor starts with explicit development opt-in'
assert_file_exists "$TMP_ROOT/monitor/samples.jsonl" 'monitor creates JSONL output'
assert_file_contains "$TMP_ROOT/monitor/samples.jsonl" '"event":"heartbeat"' 'monitor writes lifecycle heartbeat'
env $MONITOR_ENV sh "$REPO_DIR/tools/performance_monitor_lifecycle.sh" status > "$TMP_ROOT/status.out"
assert_file_contains "$TMP_ROOT/status.out" 'monitor running' 'monitor reports running process'
env $MONITOR_ENV sh "$REPO_DIR/tools/performance_monitor_lifecycle.sh" stop > "$TMP_ROOT/stop.out"
assert_file_contains "$TMP_ROOT/stop.out" 'monitor stopped' 'monitor stops cleanly'

ROTATE_ENV="KITSUNPING_MONITOR_DIR=$TMP_ROOT/rotate KITSUNPING_MONITOR_MODDIR=$REPO_DIR KITSUNPING_MONITOR_MAX_BYTES=1"
env $ROTATE_ENV sh "$REPO_DIR/tools/performance_monitor_lifecycle.sh" run-once
env $ROTATE_ENV sh "$REPO_DIR/tools/performance_monitor_lifecycle.sh" run-once
assert_file_exists "$TMP_ROOT/rotate/samples.jsonl.1" 'monitor rotates bounded JSONL output'

if grep -E '(/proc|scaling_cur_freq|thermal_zone|cpuinfo)' "$REPO_DIR/tools/performance_monitor_lifecycle.sh" "$REPO_DIR/addon/functions/debug/performance_monitor_lifecycle.sh" >/dev/null 2>&1; then
    fail 'monitor skeleton does not collect metrics yet'
else
    pass 'monitor skeleton does not collect metrics yet'
fi

finish