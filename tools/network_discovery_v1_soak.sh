#!/system/bin/sh

# Read-only, external soak observer. It never sources or modifies module code.
set -eu

duration_seconds=${1:?duration seconds required}
interval_seconds=${2:?interval seconds required}
output_dir=${3:?output directory required}
module=/data/adb/modules/Kitsunping
snapshot="$module/cache/daemon.native.state"
max_age_seconds=25

case "$duration_seconds:$interval_seconds" in
    *[!0-9:]*|0:*|*:0) echo 'duration and interval must be positive integers' >&2; exit 2 ;;
esac

mkdir -p "$output_dir"
chmod 0700 "$output_dir" 2>/dev/null || true
samples="$output_dir/health.tsv"
metadata="$output_dir/metadata.env"
started=$(date +%s)
deadline=$((started + duration_seconds))

printf 'started_epoch=%s\nduration_seconds=%s\ninterval_seconds=%s\nmodule=%s\nmode=read_only_external_observer\n' \
    "$started" "$duration_seconds" "$interval_seconds" "$module" > "$metadata"
printf 'epoch\tdaemon\tsidecar\tsnapshot\tsnapshot_age_seconds\tcontract\tprimary\tfallback\tnative_health\tfallback_used\tfallback_reason\tiface\twifi_link\twifi_ip\twifi_egress\tmobile_link\tmobile_ip\tmobile_egress\tdaemon_rss_kib\tsidecar_rss_kib\n' > "$samples"

value() {
    key=$1
    sed -n "s/^$key=//p" "$snapshot" 2>/dev/null | head -n 1
}

process_state() {
    pid_file=$1
    pid=$(cat "$pid_file" 2>/dev/null || true)
    case "$pid" in
        ''|*[!0-9]*) printf absent ;;
        *) kill -0 "$pid" 2>/dev/null && printf running || printf stale ;;
    esac
}

rss_kib() {
    pid_file=$1
    pid=$(cat "$pid_file" 2>/dev/null || true)
    case "$pid" in
        ''|*[!0-9]*) printf unknown ;;
        *) awk '/VmRSS:/ { print $2; found=1; exit } END { if (!found) print "unknown" }' "/proc/$pid/status" 2>/dev/null ;;
    esac
}

while :; do
    now=$(date +%s)
    [ "$now" -le "$deadline" ] || break
    daemon=$(process_state "$module/cache/daemon.pid")
    sidecar=$(process_state "$module/cache/kitsunpingd.pid")
    snapshot_state=missing
    age=unknown
    contract=unknown
    primary=unknown
    fallback=unknown
    iface=unknown
    wifi_link=unknown
    wifi_ip=unknown
    wifi_egress=unknown
    mobile_link=unknown
    mobile_ip=unknown
    mobile_egress=unknown
    health=missing

    if [ -r "$snapshot" ]; then
        snapshot_state=present
        ts=$(value native.ts_epoch)
        contract=$(value network.discovery.contract)
        primary=$(value network.discovery.primary)
        fallback=$(value network.discovery.fallback)
        iface=$(value iface)
        wifi_link=$(value wifi.link)
        wifi_ip=$(value wifi.ip)
        wifi_egress=$(value wifi.egress)
        mobile_link=$(value mobile.link)
        mobile_ip=$(value mobile.ip)
        mobile_egress=$(value mobile.egress)
        case "$ts" in
            ''|*[!0-9]*) health=invalid ;;
            *)
                age=$((now - ts))
                [ "$age" -lt 0 ] && age=0
                if [ "$age" -gt "$max_age_seconds" ]; then
                    health=stale
                elif [ "$contract" != v1 ] || [ "$primary" != BINARY ] || [ "$fallback" != SHELL ] || \
                    [ -z "$iface" ] || [ -z "$wifi_link" ] || [ -z "$wifi_ip" ] || [ -z "$wifi_egress" ] || \
                    [ -z "$mobile_link" ] || [ -z "$mobile_ip" ] || [ -z "$mobile_egress" ]; then
                    health=invalid
                else
                    health=valid
                fi
                ;;
        esac
    fi

    # Runtime fallback counters are intentionally not enabled during soak.
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tunknown\tunknown\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$now" "$daemon" "$sidecar" "$snapshot_state" "$age" "$contract" "$primary" "$fallback" "$health" \
        "${iface:-unknown}" "${wifi_link:-unknown}" "${wifi_ip:-unknown}" "${wifi_egress:-unknown}" \
        "${mobile_link:-unknown}" "${mobile_ip:-unknown}" "${mobile_egress:-unknown}" \
        "$(rss_kib "$module/cache/daemon.pid")" "$(rss_kib "$module/cache/kitsunpingd.pid")" >> "$samples"
    sleep "$interval_seconds"
done

printf 'completed_epoch=%s\n' "$(date +%s)" >> "$metadata"