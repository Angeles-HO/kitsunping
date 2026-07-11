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

INFER_BIN="$REPO_DIR/bin/infer"
MODEL_FILE="$REPO_DIR/models/base.onnx"
INPUT_FILE="$TMP_DIR/features.json"
OUTPUT_FILE="$TMP_DIR/out.json"
HELP_FILE="$TMP_DIR/help.txt"

cat > "$INPUT_FILE" <<'EOF'
{"wifi_score":40,"mobile_score":90,"latency_ms":180,"loss_pct":9,"battery_pct":70,"is_charging":1}
EOF

sh "$INFER_BIN" --help > "$HELP_FILE"
assert_file_contains "$HELP_FILE" "Usage: infer" "infer wrapper exposes usage text"

sh "$INFER_BIN" --model "$MODEL_FILE" --input "$INPUT_FILE" > "$OUTPUT_FILE"
assert_file_contains "$OUTPUT_FILE" '"delta_alpha"' "infer output includes delta_alpha"
assert_file_contains "$OUTPUT_FILE" '"delta_beta"' "infer output includes delta_beta"
assert_file_contains "$OUTPUT_FILE" '"delta_gamma"' "infer output includes delta_gamma"
assert_file_contains "$OUTPUT_FILE" '"delta_delta"' "infer output includes delta_delta"
assert_file_contains "$OUTPUT_FILE" '"delta_alpha":-0.0200' "infer applies wifi/mobile gap rule"
assert_file_contains "$OUTPUT_FILE" '"delta_beta":0.0200' "infer applies complementary beta delta"
assert_file_contains "$OUTPUT_FILE" '"delta_gamma":-0.0100' "infer applies latency/loss gamma adjustment"
assert_file_contains "$OUTPUT_FILE" '"delta_delta":0.0200' "infer applies latency/loss delta adjustment"

cat > "$INPUT_FILE" <<'EOF'
{"wifi_score":80,"mobile_score":20,"latency_ms":40,"loss_pct":0,"battery_pct":10,"is_charging":0}
EOF

sh "$INFER_BIN" --input "$INPUT_FILE" > "$OUTPUT_FILE"
assert_file_contains "$OUTPUT_FILE" '"delta_alpha":0.0000' "low battery no-charge forces neutral alpha delta"
assert_file_contains "$OUTPUT_FILE" '"delta_beta":0.0000' "low battery no-charge forces neutral beta delta"
assert_file_contains "$OUTPUT_FILE" '"delta_gamma":0.0000' "low battery no-charge forces neutral gamma delta"
assert_file_contains "$OUTPUT_FILE" '"delta_delta":0.0000' "low battery no-charge forces neutral delta delta"

finish
