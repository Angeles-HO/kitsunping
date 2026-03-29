#!/usr/bin/env sh
# ml_onnx_local.sh
# Local/offline ONNX probe helper. Not used by module runtime.
#
# Usage:
#   sh tools/ml_onnx_local.sh <model.onnx> <features.json> [onnx_bin]
#
# Expected features.json example:
# {"input":[-62,24.1,3.2,0.0,19,1,1]}
#
# Notes:
# - This script is intentionally decoupled from daemon/calibration.
# - It only runs if onnxruntime binary is provided/found.

MODEL_PATH="$1"
FEATURES_JSON="$2"
ONNX_BIN_ARG="$3"

if [ -z "$MODEL_PATH" ] || [ -z "$FEATURES_JSON" ]; then
    echo "Usage: sh tools/ml_onnx_local.sh <model.onnx> <features.json> [onnx_bin]"
    exit 1
fi

if [ ! -f "$MODEL_PATH" ]; then
    echo "[ml_onnx_local] Model not found: $MODEL_PATH"
    exit 1
fi

if [ ! -f "$FEATURES_JSON" ]; then
    echo "[ml_onnx_local] Feature JSON not found: $FEATURES_JSON"
    exit 1
fi

find_onnx_bin() {
    if [ -n "$ONNX_BIN_ARG" ] && [ -x "$ONNX_BIN_ARG" ]; then
        printf '%s' "$ONNX_BIN_ARG"
        return 0
    fi
    if command -v onnxruntime >/dev/null 2>&1; then
        command -v onnxruntime
        return 0
    fi
    if command -v ort >/dev/null 2>&1; then
        command -v ort
        return 0
    fi
    return 1
}

ONNX_BIN="$(find_onnx_bin 2>/dev/null || true)"
if [ -z "$ONNX_BIN" ]; then
    echo "[ml_onnx_local] No ONNX runtime binary found (onnxruntime/ort)."
    echo "[ml_onnx_local] This is expected in release builds; script is local-only."
    exit 0
fi

if command -v jq >/dev/null 2>&1; then
    INPUT_COUNT="$(jq -r '.input | length' "$FEATURES_JSON" 2>/dev/null || echo 0)"
else
    INPUT_COUNT="unknown"
fi

echo "[ml_onnx_local] runtime=$ONNX_BIN"
echo "[ml_onnx_local] model=$MODEL_PATH"
echo "[ml_onnx_local] features=$FEATURES_JSON (input_len=$INPUT_COUNT)"

# Generic execution shim: many runtimes have different CLI APIs.
# We try common signatures and print a clear message if unsupported.
if "$ONNX_BIN" --help >/dev/null 2>&1; then
    if "$ONNX_BIN" --help 2>&1 | grep -qi "model"; then
        echo "[ml_onnx_local] Runtime found. Execute with your runtime-specific args."
        echo "[ml_onnx_local] Example placeholder: $ONNX_BIN --model \"$MODEL_PATH\" --input \"$FEATURES_JSON\""
        exit 0
    fi
fi

echo "[ml_onnx_local] Runtime CLI not auto-detected; run manually with your runtime syntax."
exit 0
