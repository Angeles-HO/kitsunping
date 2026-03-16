#!/system/bin/sh
# detect_module_conflicts.sh
# Scans active Magisk modules for potential overlap with Kitsunping network/runtime behavior.

set -u

MODDIR="${MODDIR:-/data/adb/modules/Kitsunping}"
MODULES_DIR="/data/adb/modules"
EXCLUDE_MODULES="Kitsunping busybox-ndk iw iw2"

LOG_DIR="$MODDIR/logs"
CACHE_DIR="$MODDIR/cache"
REPORT_FILE="$LOG_DIR/conflicts_report.log"
STATE_FILE="$CACHE_DIR/conflicts.state"

mkdir -p "$LOG_DIR" "$CACHE_DIR" 2>/dev/null || true

now_ts="$(date +%s 2>/dev/null || echo 0)"

# High-risk: likely to collide with traffic shaping, routing, or network stack behavior.
PATTERN_HIGH='(/proc/sys/net|sysctl[[:space:]]+-w|sysctl[[:space:]]+-p|ip[[:space:]]+rule|ip[[:space:]]+route|iptables|ip6tables|nft[[:space:]]|tc[[:space:]]+qdisc|tc[[:space:]]+class|tc[[:space:]]+filter)'

# Medium-risk: network-oriented runtime/property surfaces (avoid generic setprop noise).
PATTERN_MEDIUM='(cmd[[:space:]]+wifi|wpa_cli|iw[[:space:]]+|ifconfig|ip[[:space:]]+link|svc[[:space:]]+wifi|resetprop[[:space:]]+(net\.|persist\.(net|wifi)|persist\.sys\.wifi)|setprop[[:space:]]+(net\.|persist\.(net|wifi)|persist\.sys\.wifi))'

is_excluded_module() {
    local name="$1"
    local x
    for x in $EXCLUDE_MODULES; do
        [ "$name" = "$x" ] && return 0
    done
    return 1
}

scan_module() {
    local module_path="$1"
    local module_name="$2"
    local high_hits medium_hits high_n medium_n risk

    high_hits="$(grep -RInE "$PATTERN_HIGH" "$module_path" 2>/dev/null | head -n 8)"
    medium_hits="$(grep -RInE "$PATTERN_MEDIUM" "$module_path" 2>/dev/null | head -n 8)"

    high_n=0
    medium_n=0
    [ -n "$high_hits" ] && high_n="$(printf '%s\n' "$high_hits" | wc -l | tr -d ' ')"
    [ -n "$medium_hits" ] && medium_n="$(printf '%s\n' "$medium_hits" | wc -l | tr -d ' ')"

    risk="low"
    if [ "$high_n" -gt 0 ]; then
        risk="high"
    elif [ "$medium_n" -gt 0 ]; then
        risk="medium"
    fi

    printf 'module=%s risk=%s high_hits=%s medium_hits=%s\n' "$module_name" "$risk" "$high_n" "$medium_n" >> "$REPORT_FILE"

    if [ -n "$high_hits" ]; then
        printf '[high:%s]\n%s\n' "$module_name" "$high_hits" >> "$REPORT_FILE"
    fi
    if [ -n "$medium_hits" ]; then
        printf '[medium:%s]\n%s\n' "$module_name" "$medium_hits" >> "$REPORT_FILE"
    fi

    printf '%s' "$risk"
}

# Header
{
    printf '===== Kitsunping Conflict Scan =====\n'
    printf 'ts=%s\n' "$now_ts"
    printf 'modules_dir=%s\n' "$MODULES_DIR"
    printf 'exclude=%s\n' "$EXCLUDE_MODULES"
} > "$REPORT_FILE"

modules_scanned=0
high_modules=0
medium_modules=0
low_modules=0
highest_risk="none"

for module_path in "$MODULES_DIR"/*; do
    [ -d "$module_path" ] || continue

    module_name="$(basename "$module_path")"

    is_excluded_module "$module_name" && continue
    [ -f "$module_path/disable" ] && continue
    [ -f "$module_path/remove" ] && continue

    modules_scanned=$((modules_scanned + 1))
    module_risk="$(scan_module "$module_path" "$module_name")"

    case "$module_risk" in
        high)
            high_modules=$((high_modules + 1))
            highest_risk="high"
            ;;
        medium)
            medium_modules=$((medium_modules + 1))
            [ "$highest_risk" = "none" ] && highest_risk="medium"
            ;;
        *)
            low_modules=$((low_modules + 1))
            [ "$highest_risk" = "none" ] && highest_risk="low"
            ;;
    esac

done

if [ "$modules_scanned" -eq 0 ]; then
    highest_risk="none"
fi

{
    printf 'summary modules_scanned=%s high=%s medium=%s low=%s highest_risk=%s\n' \
        "$modules_scanned" "$high_modules" "$medium_modules" "$low_modules" "$highest_risk"
} >> "$REPORT_FILE"

{
    printf 'ts=%s\n' "$now_ts"
    printf 'modules_scanned=%s\n' "$modules_scanned"
    printf 'high_modules=%s\n' "$high_modules"
    printf 'medium_modules=%s\n' "$medium_modules"
    printf 'low_modules=%s\n' "$low_modules"
    printf 'highest_risk=%s\n' "$highest_risk"
} > "$STATE_FILE"

printf 'conflict_scan_done report=%s state=%s highest_risk=%s\n' "$REPORT_FILE" "$STATE_FILE" "$highest_risk"
exit 0
