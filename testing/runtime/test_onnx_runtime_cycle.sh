#!/bin/sh

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) : ;;
    *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac

TEST_DIR=${SCRIPT_PATH%/*}
ROOT_DIR=${TEST_DIR%/*}
REPO_DIR=${ROOT_DIR%/*}

# shellcheck disable=SC1090
. "$ROOT_DIR/lib/test_helpers.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

MODDIR="$TMP_DIR/mod"
TMPDIR="$TMP_DIR/tmp"
mkdir -p "$MODDIR/cache" "$MODDIR/logs" "$MODDIR/bin" "$MODDIR/models" "$TMPDIR"

atomic_write() {
    local dst="$1" tmp
    tmp="${dst}.tmp.$$"
    cat > "$tmp"
    mv "$tmp" "$dst"
}

now_epoch() {
    date +%s 2>/dev/null || echo 0
}

log_info() { :; }
log_debug() { :; }
log_warning() { :; }

daemon_normalize_sigmoid_weights() {
    local a="$1" b="$2" g="$3" d="$4"
    LC_ALL=C awk -v a="$a" -v b="$b" -v g="$g" -v d="$d" 'BEGIN {
        sum = a + b + g
        if (sum <= 0) { a = 0.4; b = 0.3; g = 0.3; sum = 1.0 }
        if (sum != 1.0) { a = a/sum; b = b/sum; g = g/sum }
        if (d < 0) d = 0
        if (d > 0.5) d = 0.5
        printf "%.4f %.4f %.4f %.4f", a, b, g, d
    }'
}

cat > "$MODDIR/bin/infer" <<'EOF'
#!/bin/sh
cat <<'JSON'
{"delta_alpha":0.10,"delta_beta":-0.10,"delta_gamma":0,"delta_delta":0.40}
JSON
EOF
chmod +x "$MODDIR/bin/infer"
echo "base-model" > "$MODDIR/models/base.onnx"

LCL_ALPHA=0.4
LCL_BETA=0.3
LCL_GAMMA=0.3
LCL_DELTA=0.1

ONNX_ENABLE=1
ONNX_INFER_INTERVAL=1
ONNX_INFER_TIMEOUT_SEC=2
ONNX_STEP_CAP=0.05
ONNX_EMA_FACTOR=0.20
ONNX_CIRCUIT_COOLDOWN_SEC=600

transport="wifi"
wifi_score=70
mobile_score=40
wifi_rssi_dbm=-60
rsrp=-95
sinr=10
wifi_latency_ms=25
wifi_jitter_ms=5
wifi_loss_pct=1
DAEMON_SAMPLE_MODE="base"

# shellcheck disable=SC1090
. "$REPO_DIR/addon/functions/daemon_onnx.sh"

daemon_onnx_init
daemon_run_onnx_cycle

assert_eq "0.4100" "$LCL_ALPHA" "ONNX alpha applies step cap + EMA"
assert_eq "0.2900" "$LCL_BETA" "ONNX beta applies step cap + EMA"
assert_eq "0.3000" "$LCL_GAMMA" "ONNX gamma remains stable when delta is zero"
assert_eq "0.1100" "$LCL_DELTA" "ONNX delta applies capped update"
assert_file_exists "$MODDIR/cache/onnx_runtime.state" "ONNX runtime state file is written"

ONNX_PREV_SCORE=80
daemon_onnx_register_score_feedback 60
ONNX_PREV_SCORE=80
daemon_onnx_register_score_feedback 60
ONNX_PREV_SCORE=80
daemon_onnx_register_score_feedback 60

until_value="$(daemon_onnx_uint_or_default "${ONNX_CIRCUIT_UNTIL:-0}" "0")"
case "$until_value" in
    ''|*[!0-9]*|0)
        fail "ONNX circuit breaker writes a future until timestamp"
        ;;
    *)
        pass "ONNX circuit breaker writes a future until timestamp"
        ;;
esac

    LCL_ALPHA=0.5100
    LCL_BETA=0.2400
    LCL_GAMMA=0.2500
    LCL_DELTA=0.1200

    ONNX_INITIALIZED=0
    ONNX_LOOP_COUNTER=0
    ONNX_CIRCUIT_UNTIL=0
    ONNX_LEARNING_ENABLE=0
    ONNX_USE_DEFAULT_MODEL=1
    ONNX_MODEL_PATH="$MODDIR/models/custom.onnx"

    daemon_onnx_init
    assert_eq "$MODDIR/models/base.onnx" "$ONNX_MODEL_PATH" "ONNX default-model flag forces bundled model path"

    daemon_run_onnx_cycle
    assert_eq "0.5100" "$LCL_ALPHA" "ONNX learning disabled keeps alpha unchanged"
    assert_eq "0.2400" "$LCL_BETA" "ONNX learning disabled keeps beta unchanged"
    assert_eq "0.2500" "$LCL_GAMMA" "ONNX learning disabled keeps gamma unchanged"
    assert_eq "0.1200" "$LCL_DELTA" "ONNX learning disabled keeps delta unchanged"

finish
