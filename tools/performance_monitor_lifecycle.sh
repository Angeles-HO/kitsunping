#!/system/bin/sh
# Usage: performance_monitor_lifecycle.sh start|stop|status|run|run-once
# This is a development-only lifecycle test harness. It collects no metrics.

set -u

SCRIPT_DIR=${0%/*}
MODDIR="${KITSUNPING_MONITOR_MODDIR:-${SCRIPT_DIR%/tools}}"
MONITOR_DIR="${KITSUNPING_MONITOR_DIR:-$MODDIR/cache/debug/performance_monitor}"
PERFORMANCE_MONITOR_JSONL="$MONITOR_DIR/samples.jsonl"
PERFORMANCE_MONITOR_PID_FILE="$MONITOR_DIR/monitor.pid"
PERFORMANCE_MONITOR_INTERVAL_SEC="${KITSUNPING_MONITOR_INTERVAL_SEC:-10}"
PERFORMANCE_MONITOR_MAX_BYTES="${KITSUNPING_MONITOR_MAX_BYTES:-20971520}"
export PERFORMANCE_MONITOR_JSONL PERFORMANCE_MONITOR_MAX_BYTES

# shellcheck disable=SC1090
. "$MODDIR/addon/functions/debug/performance_monitor_lifecycle.sh"

monitor_debug_level_is_approved() {
    raw="${KITSUNPING_MONITOR_DEBUG_LEVEL:-}"
    if [ -z "$raw" ] && command -v getprop >/dev/null 2>&1; then
        raw="$(getprop persist.kitsunping.debug 2>/dev/null | tr -d '\r\n')"
    fi
    [ "$raw" = "2" ]
}

monitor_prepare() {
    case "$PERFORMANCE_MONITOR_INTERVAL_SEC" in ''|*[!0-9]*|0) return 2 ;; esac
    case "$PERFORMANCE_MONITOR_MAX_BYTES" in ''|*[!0-9]*|0) return 2 ;; esac
    mkdir -p "$MONITOR_DIR" || return 1
    chmod 0700 "$MONITOR_DIR" 2>/dev/null || true
    : >> "$PERFORMANCE_MONITOR_JSONL" 2>/dev/null || return 1
    chmod 0600 "$PERFORMANCE_MONITOR_JSONL" 2>/dev/null || true
}

monitor_running() {
    [ -f "$PERFORMANCE_MONITOR_PID_FILE" ] || return 1
    pid="$(cat "$PERFORMANCE_MONITOR_PID_FILE" 2>/dev/null)"
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null
}

monitor_run() {
    trap 'rm -f "$PERFORMANCE_MONITOR_PID_FILE"; exit 0' INT TERM EXIT
    printf '%s\n' "$$" > "$PERFORMANCE_MONITOR_PID_FILE"
    while :; do
        performance_monitor_write_heartbeat || exit 1
        sleep "$PERFORMANCE_MONITOR_INTERVAL_SEC"
    done
}

case "${1:-}" in
    start)
        [ "${KITSUNPING_PERF_MONITOR_ALLOW:-0}" = "1" ] || { echo 'monitor disabled: explicit development opt-in required' >&2; exit 3; }
        monitor_debug_level_is_approved || { echo 'monitor disabled: requires debug level 2' >&2; exit 4; }
        monitor_prepare || exit $?
        if monitor_running; then echo 'monitor already running'; exit 0; fi
        rm -f "$PERFORMANCE_MONITOR_PID_FILE"
        performance_monitor_write_heartbeat || exit 1
        sh "$0" run >/dev/null 2>&1 &
        child=$!
        printf '%s\n' "$child" > "$PERFORMANCE_MONITOR_PID_FILE"
        echo "monitor started pid=$child file=$PERFORMANCE_MONITOR_JSONL"
        ;;
    stop)
        if monitor_running; then
            pid="$(cat "$PERFORMANCE_MONITOR_PID_FILE")"
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$PERFORMANCE_MONITOR_PID_FILE"
        echo 'monitor stopped'
        ;;
    status)
        if monitor_running; then echo "monitor running pid=$(cat "$PERFORMANCE_MONITOR_PID_FILE")"; else echo 'monitor stopped'; fi
        ;;
    run) monitor_prepare && monitor_run ;;
    run-once) monitor_prepare && performance_monitor_write_heartbeat ;;
    *) echo 'Usage: performance_monitor_lifecycle.sh start|stop|status|run|run-once' >&2; exit 64 ;;
esac