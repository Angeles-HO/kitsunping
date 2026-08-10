#!/system/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/cache"
cat > "$TMP_DIR/ip" <<'EOF'
#!/bin/sh

if [ "$1" = "link" ] && [ "$2" = "show" ] && [ "$#" -eq 2 ]; then
    printf '%s\n' '2: wlan0: <BROADCAST> mtu 1500 qdisc noop state UP mode DEFAULT'
elif [ "$1" = "link" ] && [ "$2" = "show" ]; then
    printf '%s\n' '2: iface: <BROADCAST> mtu 1500 qdisc noop state UP mode DEFAULT'
elif [ "$1" = "addr" ] && [ "$2" = "show" ]; then
    printf '%s\n' '    inet 192.0.2.10/24 scope global'
elif [ "$1" = "route" ] && [ "$2" = "get" ]; then
    printf '%s\n' '8.8.8.8 via 192.0.2.1 dev wlan0'
fi
EOF
chmod +x "$TMP_DIR/ip"

cat > "$TMP_DIR/cache/daemon.native.state" <<EOF
iface=bad iface
wifi.iface=wlan0
wifi.link=SIDEWAYS
wifi.ip=2
wifi.egress=1
mobile.iface=rmnet_data0
mobile.link=UP
mobile.ip=1
mobile.egress=2
native.ts_epoch=$(date +%s)
EOF

MODDIR="$TMP_DIR"
IP_BIN="$TMP_DIR/ip"
KITSUNPINGD_LEGACY_COLLECTORS_FILE="$ROOT_DIR/addon/functions/legacy_network_collectors.sh"
KITSUNPINGD_SNAPSHOT_BRIDGE_FILE="$ROOT_DIR/addon/functions/snapshot_bridge.sh"
KITSUNPINGD_SNAPSHOT_METRICS_FILE="$ROOT_DIR/addon/functions/snapshot_metrics.sh"
command_exists() { return 1; }
atomic_write() { cat > "$1"; }
. "$ROOT_DIR/addon/functions/network_utils.sh"

[ "$(get_current_iface)" = "wlan0" ]
[ "$(get_wifi_status)" = "iface=wlan0 link=UP ip=1 egress=1 reason=usable_route" ]
[ "$(get_mobile_status rmnet_data0)" = "iface=rmnet_data0 link=UP ip=1 egress=0 reason=no_default_route" ]

printf '%s\n' "ok"