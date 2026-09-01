#!/system/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/cache"
printf '%s\n' stale > "$TMP_DIR/cache/native.snapshot.metrics"
cat > "$TMP_DIR/cache/daemon.native.state" <<EOF
iface=wlan0
wifi.iface=wlan0
wifi.link=UP
wifi.ip=1
wifi.egress=1
wifi.reason=usable_route
wifi.rssi_dbm=-55
wifi.bssid=aa:bb:cc:dd:ee:ff
wifi.band=5g
wifi.chan=44
wifi.freq=5220
wifi.width=80
wifi.width_source=explicit
wifi.width_confidence=high
wifi.standard=ax
wifi.ssid=Native_Test_AP
mobile.iface=none
mobile.link=DOWN
mobile.ip=0
mobile.egress=0
mobile.reason=link_down
mobile.rat=LTE
rsrp_dbm=-97
rsrp_score=60
sinr_db=11
sinr_score=73
native.ts_epoch=$(date +%s)
EOF

MODDIR="$TMP_DIR"
IP_BIN=false
KITSUNPINGD_SNAPSHOT_BRIDGE_FILE="$ROOT_DIR/addon/functions/snapshot_bridge.sh"
KITSUNPINGD_SNAPSHOT_METRICS_FILE="$ROOT_DIR/addon/functions/snapshot_metrics.sh"
command_exists() { return 1; }
atomic_write() { cat > "$1"; }
. "$ROOT_DIR/addon/functions/network_utils.sh"

[ "$(get_current_iface)" = "wlan0" ]
[ ! -e "$TMP_DIR/cache/native.snapshot.metrics" ]
if kitsunpingd_metrics_enabled; then
	exit 1
fi

iteration=1
while [ "$iteration" -le 20 ]; do
	[ "$(get_current_iface)" = "wlan0" ]
	[ "$(get_wifi_status)" = "iface=wlan0 link=UP ip=1 egress=1 reason=usable_route" ]
	iteration=$((iteration + 1))
done
[ ! -e "$TMP_DIR/cache/native.snapshot.metrics" ]

printf '%s\n' 1 > "$TMP_DIR/cache/native.snapshot.metrics.enabled"
unset KITSUNPINGD_METRICS_ENABLED
. "$ROOT_DIR/addon/functions/snapshot_metrics.sh"
[ "$(kitsunpingd_metrics_enabled; echo $?)" = "0" ]
[ "$(get_wifi_status)" = "iface=wlan0 link=UP ip=1 egress=1 reason=usable_route" ]
[ "$(get_mobile_status none)" = "iface=none link=DOWN ip=0 egress=0 reason=link_down" ]
[ "$(get_wifi_rssi_dbm wlan0)" = "-55" ]
native_wifi_info="$(get_wifi_extended_info wlan0)"
printf '%s' "$native_wifi_info" | grep -Fq 'bssid=aa:bb:cc:dd:ee:ff'
printf '%s' "$native_wifi_info" | grep -Fq 'ssid=Native_Test_AP'
printf '%s' "$native_wifi_info" | grep -Fq 'freq=5220'
printf '%s' "$native_wifi_info" | grep -Fq 'width=80'
printf '%s' "$native_wifi_info" | grep -Fq 'wifi_standard=ax'
grep -Fq 'helper=wifi_status ip=4 iw=0 dumpsys=0 parser=4 external=8' "$TMP_DIR/cache/native.snapshot.metrics"
grep -Fq 'helper=wifi_rssi' "$TMP_DIR/cache/native.snapshot.metrics"

rm -f "$TMP_DIR/cache/native.snapshot.metrics.enabled"
[ "$(get_wifi_status)" = "iface=wlan0 link=UP ip=1 egress=1 reason=usable_route" ]
[ ! -e "$TMP_DIR/cache/native.snapshot.metrics" ]

sed -i 's/mobile.egress=0/mobile.egress=1/' "$TMP_DIR/cache/daemon.native.state"
sed -i 's/mobile.iface=none/mobile.iface=rmnet_data0/' "$TMP_DIR/cache/daemon.native.state"
sed -i 's/mobile.link=DOWN/mobile.link=UP/' "$TMP_DIR/cache/daemon.native.state"
sed -i 's/mobile.ip=0/mobile.ip=1/' "$TMP_DIR/cache/daemon.native.state"
KITSUNPINGD_SNAPSHOT_LOADED=0
[ "$(get_mobile_status rmnet_data0)" = "iface=rmnet_data0 link=UP ip=1 egress=1 reason=usable_route" ]
if get_native_mobile_status wlan0 >/dev/null; then
	exit 1
fi
native_signal="$(get_native_mobile_signal_quality)"
printf '%s' "$native_signal" | grep -Fq '"source":"kitsunpingd"'
printf '%s' "$native_signal" | grep -Fq '"rsrp_dbm":"-97"'
printf '%s' "$native_signal" | grep -Fq '"sinr_db":"11"'

printf '%s\n' "ok"