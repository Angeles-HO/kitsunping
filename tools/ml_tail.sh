#!/system/bin/sh
# ml_tail.sh
# Show latest ML calibration vectors from cache/ml without touching daemon/calibration flow.
# Usage:
#   sh tools/ml_tail.sh [module_path] [count]
# Example:
#   sh tools/ml_tail.sh /data/adb/modules/Kitsunping 20

MODPATH="${1:-/data/adb/modules/Kitsunping}"
COUNT_RAW="${2:-10}"

case "$COUNT_RAW" in
    ''|*[!0-9]*) COUNT=10 ;;
    *) COUNT="$COUNT_RAW" ;;
esac
[ "$COUNT" -lt 1 ] && COUNT=1
[ "$COUNT" -gt 200 ] && COUNT=200

FILE="$MODPATH/cache/ml/calibration_features.jsonl"
LAST_FILE="$MODPATH/cache/ml/last_calibration_feature.json"

if [ ! -f "$FILE" ]; then
    echo "[ml_tail] No feature log found: $FILE"
    echo "[ml_tail] Enable capture with: setprop persist.kitsunping.ml_feature_log_enable 1"
    exit 0
fi

echo "[ml_tail] file=$FILE"
echo "[ml_tail] showing last $COUNT lines"
echo "------------------------------------------------------------"
tail -n "$COUNT" "$FILE" 2>/dev/null || cat "$FILE" 2>/dev/null

if [ -f "$LAST_FILE" ]; then
    echo "------------------------------------------------------------"
    echo "[ml_tail] last snapshot: $LAST_FILE"
    cat "$LAST_FILE" 2>/dev/null
    echo
fi
