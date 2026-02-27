#!/system/bin/sh
# Test parsing Wi-Fi link info using a sample iw output dump.

SCRIPT_DIR="${0%/*}"
MODDIR="${SCRIPT_DIR%/*}"

. "$MODDIR/addon/functions/core.sh"
. "$MODDIR/addon/functions/network_utils.sh"

samples_dir="$MODDIR/testdata"
if [ ! -d "$samples_dir" ]; then
    echo "missing samples dir: $samples_dir" >&2
    exit 1
fi

found=0
for sample_file in "$samples_dir"/iw_link*.txt; do
    [ -f "$sample_file" ] || continue
    found=1
    echo "== $(basename "$sample_file") =="
    parse_iw_link_info_text "$(cat "$sample_file")"
    echo ""
done

for sample_file in "$samples_dir"/dumpsys*.txt; do
    [ -f "$sample_file" ] || continue
    found=1
    echo "== $(basename "$sample_file") =="
    parse_dumpsys_wifi_info_text "$(cat "$sample_file")"
    echo ""
done

if [ "$found" -eq 0 ]; then
    echo "no samples found in: $samples_dir" >&2
    exit 1
fi
