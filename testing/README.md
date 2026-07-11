# Testing

This directory contains fixture-based shell tests focused on functions and runtime flows.

Scope:

- failsafe and rescue regression coverage,
- module conflict scanning with synthetic module trees,
- adaptive sampling transitions,
- ML feature logging opt-in behavior,
- offline ONNX helper validation,
- ONNX runtime scaffold guardrails (step cap/EMA/circuit breaker),
- ONNX infer wrapper contract validation.

Run the full suite with:

```sh
sh testing/run.sh
```

This suite is designed to run without Android services or router access. Each test creates its own temporary fixture tree and cleans up after itself.