#!/system/bin/sh

# Opt-in operational metrics for snapshot-backed calls. Disabled by default so
# normal daemon operation performs no additional metrics-file writes.

KITSUNPINGD_METRICS_FILE="${KITSUNPINGD_METRICS_FILE:-${MODDIR:-/data/adb/modules/Kitsunping}/cache/native.snapshot.metrics}"
KITSUNPINGD_METRICS_ENABLED="${KITSUNPINGD_METRICS_ENABLED:-}"
KITSUNPINGD_METRICS_TOGGLE_FILE="${KITSUNPINGD_METRICS_TOGGLE_FILE:-${MODDIR:-/data/adb/modules/Kitsunping}/cache/native.snapshot.metrics.enabled}"
KITSUNPINGD_METRICS_ENV_OVERRIDE="$KITSUNPINGD_METRICS_ENABLED"

if [ -z "$KITSUNPINGD_METRICS_ENV_OVERRIDE" ] && [ -r "$KITSUNPINGD_METRICS_TOGGLE_FILE" ]; then
    IFS= read -r KITSUNPINGD_METRICS_ENABLED < "$KITSUNPINGD_METRICS_TOGGLE_FILE" || true
fi
case "$KITSUNPINGD_METRICS_ENABLED" in
    1) ;;
    *) KITSUNPINGD_METRICS_ENABLED=0 ;;
esac

kitsunpingd_metrics_enabled() {
    local enabled
    if [ -n "$KITSUNPINGD_METRICS_ENV_OVERRIDE" ]; then
        [ "$KITSUNPINGD_METRICS_ENV_OVERRIDE" = "1" ]
        return
    fi
    enabled=0
    [ -r "$KITSUNPINGD_METRICS_TOGGLE_FILE" ] && \
        IFS= read -r enabled < "$KITSUNPINGD_METRICS_TOGGLE_FILE" || true
    [ "$enabled" = "1" ]
}

kitsunpingd_metrics_cleanup_disabled() {
    kitsunpingd_metrics_enabled && return 0
    rm -f "$KITSUNPINGD_METRICS_FILE" "$KITSUNPINGD_METRICS_TOGGLE_FILE" 2>/dev/null || true
}

# A disabled measurement window must leave no ambiguous artifacts in cache.
kitsunpingd_metrics_cleanup_disabled

kitsunpingd_metrics_record() {
    local helper ip iw dumpsys parser external
    if ! kitsunpingd_metrics_enabled; then
        rm -f "$KITSUNPINGD_METRICS_FILE" "$KITSUNPINGD_METRICS_TOGGLE_FILE" 2>/dev/null || true
        return 0
    fi
    helper="$1"
    ip="${2:-0}"
    iw="${3:-0}"
    dumpsys="${4:-0}"
    parser="${5:-0}"
    external=$((ip + iw + dumpsys + parser))
    printf 'helper=%s ip=%s iw=%s dumpsys=%s parser=%s external=%s\n' \
        "$helper" "$ip" "$iw" "$dumpsys" "$parser" "$external" >> "$KITSUNPINGD_METRICS_FILE" 2>/dev/null || true
}