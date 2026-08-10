#!/system/bin/sh

set -eu

MODDIR="${MODDIR:-/data/adb/modules/Kitsunping}"
METRICS_FILE="${KITSUNPINGD_METRICS_FILE:-$MODDIR/cache/native.snapshot.metrics}"

if [ ! -s "$METRICS_FILE" ]; then
    printf '%s\n' "native_snapshot_hits=0"
    printf '%s\n' "known_avoided_external_processes=0"
    exit 0
fi

awk '
{
    helper=""; ip=iw=dumpsys=parser=external=0
    for (field_index=1; field_index<=NF; field_index++) {
        split($field_index, field, "=")
        if (field[1] == "helper") helper=field[2]
        else if (field[1] == "ip") ip=field[2]
        else if (field[1] == "iw") iw=field[2]
        else if (field[1] == "dumpsys") dumpsys=field[2]
        else if (field[1] == "parser") parser=field[2]
        else if (field[1] == "external") external=field[2]
    }
    if (helper == "cycle") cycles++
    else {
        hits++
        helper_hits[helper]++
    }
    total_ip += ip; total_iw += iw; total_dumpsys += dumpsys
    total_parser += parser; total_external += external
}
END {
    printf "native_snapshot_hits=%d\n", hits
    printf "known_avoided_ip_calls=%d\n", total_ip
    printf "known_avoided_iw_calls=%d\n", total_iw
    printf "known_avoided_dumpsys_calls=%d\n", total_dumpsys
    printf "known_avoided_parser_processes=%d\n", total_parser
    printf "known_avoided_external_processes=%d\n", total_external
    printf "measurement_cycles=%d\n", cycles
    if (cycles > 0) {
        printf "known_avoided_ip_calls_per_cycle=%.2f\n", total_ip / cycles
        printf "known_avoided_iw_calls_per_cycle=%.2f\n", total_iw / cycles
        printf "known_avoided_dumpsys_calls_per_cycle=%.2f\n", total_dumpsys / cycles
        printf "known_avoided_external_processes_per_cycle=%.2f\n", total_external / cycles
    }
    for (helper in helper_hits) printf "native_snapshot_hits_%s=%d\n", helper, helper_hits[helper]
}
' "$METRICS_FILE" | LC_ALL=C sort