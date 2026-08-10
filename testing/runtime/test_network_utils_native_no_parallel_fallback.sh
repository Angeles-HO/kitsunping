#!/system/bin/sh

set -eu

SCRIPT_DIR=$(dirname -- "$0")
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/cache"
MODDIR="$TMP_DIR"
KITSUNPINGD_LEGACY_COLLECTORS_FILE="$TMP_DIR/legacy-network-collectors.sh"
KITSUNPINGD_SNAPSHOT_BRIDGE_FILE="$TMP_DIR/snapshot-bridge.sh"
KITSUNPINGD_SNAPSHOT_METRICS_FILE="$TMP_DIR/snapshot-metrics.sh"
: "$MODDIR" "$KITSUNPINGD_LEGACY_COLLECTORS_FILE" "$KITSUNPINGD_SNAPSHOT_BRIDGE_FILE" "$KITSUNPINGD_SNAPSHOT_METRICS_FILE"

cat > "$KITSUNPINGD_LEGACY_COLLECTORS_FILE" <<'EOF'
legacy_get_wifi_status() { : > "$MODDIR/cache/legacy_wifi_called"; printf '%s' unexpected; }
legacy_get_mobile_status() { : > "$MODDIR/cache/legacy_mobile_called"; printf '%s' unexpected; }
legacy_get_current_iface() { : > "$MODDIR/cache/legacy_iface_called"; printf '%s' unexpected; }
EOF

cat > "$KITSUNPINGD_SNAPSHOT_BRIDGE_FILE" <<'EOF'
get_native_wifi_status() { printf '%s' 'iface=wlan0 link=UP ip=1 egress=1 reason=usable_route'; }
get_native_mobile_status() { printf '%s' 'iface=rmnet_data0 link=UP ip=1 egress=0 reason=no_default_route'; }
get_native_current_iface() { printf '%s' 'wlan0'; }
get_native_wifi_rssi_dbm() { printf '%s' '-55'; }
get_native_wifi_extended_info() { printf '%s' 'bssid=aa:bb:cc:dd:ee:ff ssid=Native_AP freq=5220 width=80'; }
EOF

cat > "$KITSUNPINGD_SNAPSHOT_METRICS_FILE" <<'EOF'
kitsunpingd_metrics_record() { :; }
EOF

command_exists() { return 1; }
resolve_iw_binary() { return 1; }
atomic_write() { cat > "$1"; }
. "$ROOT_DIR/addon/functions/network_utils.sh"

[ "$(get_current_iface)" = "wlan0" ]
[ "$(get_wifi_status)" = "iface=wlan0 link=UP ip=1 egress=1 reason=usable_route" ]
[ "$(get_mobile_status rmnet_data0)" = "iface=rmnet_data0 link=UP ip=1 egress=0 reason=no_default_route" ]
[ "$(get_wifi_rssi_dbm wlan0)" = "-55" ]
[ "$(get_wifi_extended_info wlan0)" = "bssid=aa:bb:cc:dd:ee:ff ssid=Native_AP freq=5220 width=80" ]

[ ! -e "$TMP_DIR/cache/legacy_iface_called" ]
[ ! -e "$TMP_DIR/cache/legacy_wifi_called" ]
[ ! -e "$TMP_DIR/cache/legacy_mobile_called" ]

printf '%s\n' "ok"