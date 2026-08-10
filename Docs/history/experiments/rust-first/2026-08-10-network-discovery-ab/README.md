# network.discovery/v1 Rust-first A/B

Status: COMPLETED for functional control flow; performance decision DEFERRED

## Contract

The evaluated path was:

```text
valid network.discovery/v1 snapshot -> consume native
invalid, stale, missing, incomplete, or malformed snapshot -> Bash fallback
```

Bash did not run preventively after native acceptance.

## Functional result

The completed candidate recorded native hits and zero fallback events for the
observed discovery producers. The parity record covers the tested active-Wi-Fi
scenario with `mobile=none`; active mobile-radio parity remains open.

## Limits

- RSSI and extended Wi-Fi remain MIXED, not promoted.
- Foreground package remains MIXED; Rust may invoke `dumpsys`.
- The campaign does not establish lower energy use or lower total CPU cost.
- Fork/exec evidence was absent from this completed run.
- The candidate archive has a documented daemon-recovery boundary.

## Decision

Keep `network.discovery/v1` as the limited functional Rust-first contract with
strict Bash fallback. Do not use this campaign as justification for MIG-002 or
another migration.

## Evidence

Canonical raw evidence and final analysis:

`KitsunpingRuntimeProfiler/artifacts/network-discovery-v1/rust-first-discovery-ab-20260809-000413/final-analysis-20260810/`

See `AB_FINAL_ANALYSIS.md`, `baseline.report.json`, `candidate.report.json`,
checksums, CSV exports, SQLite exports, and completion metadata in that store.