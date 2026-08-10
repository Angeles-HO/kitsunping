#!/system/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/cache"
cat > "$TMP_DIR/cache/daemon.native.state" <<EOF
mobile.iface=rmnet_data0
mobile.egress=1
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
KITSUNPINGD_METRICS_ENABLED=1
JQ_BIN=""
POLICY_DIR="$TMP_DIR/missing-policy"
LCL_ALPHA=0.4
LCL_BETA=0.3
LCL_GAMMA=0.3
LCL_DELTA=0
transport=mobile
mobile_iface=rmnet_data0
mobile_score=100
signal_loop_count=4
SIGNAL_POLL_INTERVAL=5
EV_SIGNAL_DEGRADED=SIGNAL_DEGRADED

atomic_write() { cat > "$1"; }
score_rsrp_cached() { : > "$TMP_DIR/rsrp_score_fallback_called"; printf '%s' 60; }
score_sinr_cached() { : > "$TMP_DIR/sinr_score_fallback_called"; printf '%s' 73; }
composite_ema() { printf '%s' "$1"; }
decide_profile() { printf '%s' stable; }
log_info() { :; }
log_debug() { :; }
emit_event() { :; }
get_signal_quality() {
    : > "$TMP_DIR/fallback_called"
    printf '%s' '{"quality_score":0,"rsrp_dbm":"-","sinr_db":"-"}'
}

. "$ROOT_DIR/addon/functions/network_utils.sh"
. "$ROOT_DIR/network/mobile/cycle.sh"

network__mobile__transport_cycle

[ ! -e "$TMP_DIR/fallback_called" ]
[ ! -e "$TMP_DIR/rsrp_score_fallback_called" ]
[ ! -e "$TMP_DIR/sinr_score_fallback_called" ]
grep -Fq '"source":"kitsunpingd"' "$TMP_DIR/cache/signal_quality.json"
grep -Fq '"rsrp_dbm":"-97"' "$TMP_DIR/cache/signal_quality.json"
grep -Fq '"sinr_db":"11"' "$TMP_DIR/cache/signal_quality.json"
[ "$(cat "$TMP_DIR/cache/policy.auto_request")" = "stable" ]
grep -Fq 'helper=mobile_signal ip=0 iw=0 dumpsys=1 parser=0 external=1' "$TMP_DIR/cache/native.snapshot.metrics"

printf '%s\n' "ok"