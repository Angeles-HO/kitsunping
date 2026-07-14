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
- policy-request ownership, executor latest-intent precedence, and foreground
  Gaming-to-automatic-profile release coverage.

Run the full suite with:

```sh
sh testing/run.sh
```

This suite is designed to run without Android services or router access. Each test creates its own temporary fixture tree and cleans up after itself.

Device/Magisk integration scenarios are intentionally separate because they
require a rooted non-production Android device. Follow
[device_runtime_scenarios.md](integration/device_runtime_scenarios.md) to record
device evidence and rollback each disruptive scenario.