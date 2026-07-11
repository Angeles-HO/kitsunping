# ONNX Infer Contract (Phase 2)

Status: scaffold contract (stable for runtime integration)

## CLI

```sh
$MODDIR/bin/infer [--model <path>] [--input <features.json>] [--stdin]
```

- `--model`: optional path to ONNX model file.
- `--input`: optional JSON file with features; when omitted, reads from stdin.
- `--stdin`: force read from stdin.

## Input JSON (expected keys)

All fields are optional; missing values fallback to safe defaults.

```json
{
  "wifi_score": 0,
  "mobile_score": 0,
  "latency_ms": 0,
  "jitter_ms": 0,
  "loss_pct": 0,
  "battery_pct": 100,
  "is_charging": 0
}
```

## Output JSON (required keys)

```json
{
  "delta_alpha": 0.0000,
  "delta_beta": 0.0000,
  "delta_gamma": 0.0000,
  "delta_delta": 0.0000
}
```

Output constraints:

- each delta in `[-0.10, +0.10]`
- decimal point `.` locale-independent numeric output
- one-line JSON object

## Runtime guardrails (daemon side)

Even valid output is re-guarded by runtime:

1. step cap (`ONNX_STEP_CAP`)
2. EMA (`ONNX_EMA_FACTOR`)
3. weight clamp + normalize (`daemon_normalize_sigmoid_weights`)
4. circuit breaker on repeated degradation

The infer wrapper can suggest; daemon always decides.

## Control flags (module properties)

- `persist.kitsunping.onnx.enable` / `kitsunping.onnx.enable`: global ONNX on/off.
- `persist.kitsunping.onnx.learning_enable` / `kitsunping.onnx.learning_enable`: enable adaptive weight updates.
- `persist.kitsunping.onnx.use_default_model` / `kitsunping.onnx.use_default_model`: force bundled model (`$MODDIR/models/base.onnx`).

These flags are intended to be controlled from the app settings UI.
