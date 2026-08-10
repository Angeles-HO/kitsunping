#!/system/bin/sh
# Development-only lifecycle skeleton. This file is intentionally not sourced
# by the production daemon until the Debug enum migration is separately approved.

performance_monitor_now_epoch() {
    date +%s 2>/dev/null || awk 'BEGIN { print systime() }' 2>/dev/null || printf '0'
}

performance_monitor_json_line() {
    printf '{"schema":1,"ts_epoch":%s,"event":"heartbeat"}\n' "$(performance_monitor_now_epoch)"
}

performance_monitor_rotate() {
    [ -f "$PERFORMANCE_MONITOR_JSONL" ] || return 0
    size="$(wc -c < "$PERFORMANCE_MONITOR_JSONL" 2>/dev/null | tr -d '[:space:]')"
    case "$size" in ''|*[!0-9]*) return 1 ;; esac
    [ "$size" -lt "$PERFORMANCE_MONITOR_MAX_BYTES" ] && return 0
    rm -f "$PERFORMANCE_MONITOR_JSONL.1" 2>/dev/null || return 1
    mv "$PERFORMANCE_MONITOR_JSONL" "$PERFORMANCE_MONITOR_JSONL.1" 2>/dev/null || return 1
    : > "$PERFORMANCE_MONITOR_JSONL"
}

performance_monitor_write_heartbeat() {
    performance_monitor_rotate || return 1
    performance_monitor_json_line >> "$PERFORMANCE_MONITOR_JSONL"
}