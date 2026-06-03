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

FAKE_RUNTIME="$TMP_DIR/fake_onnxruntime.sh"
cat > "$FAKE_RUNTIME" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--help" ]; then
    echo "usage: fake-onnx --model <file> --input <json>"
    exit 0
fi
exit 0
EOF
chmod +x "$FAKE_RUNTIME"

OUTPUT_FILE="$TMP_DIR/output.txt"
sh "$REPO_DIR/tools/ml_onnx_local.sh" \
    "$REPO_DIR/testing/fixtures/ml/model.onnx" \
    "$REPO_DIR/testing/fixtures/ml/features.json" \
    "$FAKE_RUNTIME" > "$OUTPUT_FILE"

assert_file_contains "$OUTPUT_FILE" "runtime=$FAKE_RUNTIME" "ONNX helper reports the detected runtime"
assert_file_contains "$OUTPUT_FILE" "model=$REPO_DIR/testing/fixtures/ml/model.onnx" "ONNX helper reports the fixture model"
assert_file_contains "$OUTPUT_FILE" "Example placeholder" "ONNX helper exposes the CLI guidance placeholder"

finish