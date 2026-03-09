#!/system/bin/sh
# executor_kpi.sh — per-hour KPI counters for executor.sh
# Sourced by executor.sh after helpers are loaded.
# Requires: atomic_write, epoch_now, uint_or_default (from core.sh / policy_common.sh)
# Requires: EXECUTOR_KPI_HOURLY_FILE (set by executor.sh before sourcing this file)

KPI_HOUR=0
KPI_CHANGES_HOUR=0
KPI_ROLLBACKS_HOUR=0
KPI_APPLY_SUM_MS=0
KPI_APPLY_COUNT=0
KPI_MEAN_APPLY_MS=0

load_executor_kpi_hourly() {
    [ -f "$EXECUTOR_KPI_HOURLY_FILE" ] || return 0

    KPI_HOUR=$(awk -F= '$1=="kpi.hour" {print substr($0, index($0, "=")+1)}' "$EXECUTOR_KPI_HOURLY_FILE" 2>/dev/null | tail -n1)
    KPI_CHANGES_HOUR=$(awk -F= '$1=="kpi.changes_hour" {print substr($0, index($0, "=")+1)}' "$EXECUTOR_KPI_HOURLY_FILE" 2>/dev/null | tail -n1)
    KPI_ROLLBACKS_HOUR=$(awk -F= '$1=="kpi.rollbacks_hour" {print substr($0, index($0, "=")+1)}' "$EXECUTOR_KPI_HOURLY_FILE" 2>/dev/null | tail -n1)
    KPI_APPLY_SUM_MS=$(awk -F= '$1=="kpi.apply_sum_ms" {print substr($0, index($0, "=")+1)}' "$EXECUTOR_KPI_HOURLY_FILE" 2>/dev/null | tail -n1)
    KPI_APPLY_COUNT=$(awk -F= '$1=="kpi.apply_count" {print substr($0, index($0, "=")+1)}' "$EXECUTOR_KPI_HOURLY_FILE" 2>/dev/null | tail -n1)

    KPI_HOUR="$(uint_or_default "$KPI_HOUR" "0")"
    KPI_CHANGES_HOUR="$(uint_or_default "$KPI_CHANGES_HOUR" "0")"
    KPI_ROLLBACKS_HOUR="$(uint_or_default "$KPI_ROLLBACKS_HOUR" "0")"
    KPI_APPLY_SUM_MS="$(uint_or_default "$KPI_APPLY_SUM_MS" "0")"
    KPI_APPLY_COUNT="$(uint_or_default "$KPI_APPLY_COUNT" "0")"
}

write_executor_kpi_hourly() {
    cat <<EOF | atomic_write "$EXECUTOR_KPI_HOURLY_FILE"
kpi.hour=$KPI_HOUR
kpi.changes_hour=$KPI_CHANGES_HOUR
kpi.rollbacks_hour=$KPI_ROLLBACKS_HOUR
kpi.apply_sum_ms=$KPI_APPLY_SUM_MS
kpi.apply_count=$KPI_APPLY_COUNT
EOF
}

update_executor_kpi_hourly() {
    local change_inc="$1" rollback_inc="$2" apply_ms="$3" apply_count_inc="$4"
    local now_epoch hour_bucket

    now_epoch=$(epoch_now)
    now_epoch="$(uint_or_default "$now_epoch" "0")"
    hour_bucket=$((now_epoch / 3600))

    load_executor_kpi_hourly

    if [ "$KPI_HOUR" -ne "$hour_bucket" ]; then
        KPI_HOUR="$hour_bucket"
        KPI_CHANGES_HOUR=0
        KPI_ROLLBACKS_HOUR=0
        KPI_APPLY_SUM_MS=0
        KPI_APPLY_COUNT=0
    fi

    change_inc="$(uint_or_default "$change_inc" "0")"
    rollback_inc="$(uint_or_default "$rollback_inc" "0")"
    apply_ms="$(uint_or_default "$apply_ms" "0")"
    apply_count_inc="$(uint_or_default "$apply_count_inc" "0")"

    KPI_CHANGES_HOUR=$((KPI_CHANGES_HOUR + change_inc))
    KPI_ROLLBACKS_HOUR=$((KPI_ROLLBACKS_HOUR + rollback_inc))
    KPI_APPLY_SUM_MS=$((KPI_APPLY_SUM_MS + apply_ms))
    KPI_APPLY_COUNT=$((KPI_APPLY_COUNT + apply_count_inc))

    if [ "$KPI_APPLY_COUNT" -gt 0 ]; then
        KPI_MEAN_APPLY_MS=$((KPI_APPLY_SUM_MS / KPI_APPLY_COUNT))
    else
        KPI_MEAN_APPLY_MS=0
    fi

    write_executor_kpi_hourly
}
