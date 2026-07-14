# Kitsunping Documentation Hub

Last update: 2026-07-10

This index is the canonical entry point for project documentation. Files are grouped by lifecycle stage to reduce noise and make release work easier.

## 00-overview

- `00-overview/privacy-and-telemetry.md`: privacy boundaries and local-data behavior.
- `00-overview/runtime-locks-and-heavy-tasks.md`: lock model and heavy-task coordination.
- `00-overview/local-ci-and-release-gate.md`: CI path, failure triage, and pre-release validation commands.
- `00-overview/references-applicability-matrix-v7-beta.md`: mapping from `lib/references` topics to current executable Kitsunping scope.
- `00-overview/v7-beta-kickoff-checklist.md`: first execution steps for v7.0-beta stabilization.
- `00-overview/v7-beta-baseline-report-2026-06-29.md`: kickoff validation evidence before hardening changes.
- `00-overview/v7-beta-scope-freeze-2026-06-30.md`: finalized v7.0-beta scope boundary, branch convention, and acceptance criteria.
- `00-overview/v7-beta-device-validation-2026-07-10.md`: device-side install and calibration validation after JSON output hardening.
- `plan.md`: roadmap and release scope split for v7.0-beta and v7.0 release.

## 10-runtime

- `10-runtime/daemon.md`: daemon behavior and runtime flow.
- `10-runtime/implementation.md`: boot stages, runtime components, and state files.
- `10-runtime/property-discovery-methods.md`: methods to discover properties not exposed by plain getprop/build.prop.
- `10-runtime/network-profiles.md`: profile model and selection flow.
- `10-runtime/wifi-properties-reference.md`: Wi-Fi property reference.
- `10-runtime/binary-paths.md`: bundled/system binary resolution.
- `10-runtime/failsafe-module-status-reference.md`: failsafe and module-status lifecycle.
- `10-runtime/runtime-cadence-baseline-v7-beta.md`: baseline cadence and debounce tuning plan for v7.0-beta.
- `10-runtime/runtime-debounce-experiment-matrix-v7-beta.md`: candidate comparison matrix for debounce 60s/90s.

## 20-router

- `20-router/router-integration-boundary.md`: public integration contract and license boundary.
- `20-router/band-selector.md`: Wi-Fi band-aware profile switching behavior.
- `20-router/m4-passive-notifications.md`: passive channel recommendation notifications.
- `20-router/qos-flow-mvp.md`: router QoS MVP plan (design reference, not release validation).

## 90-archive

- `90-archive/testing-results-history.md`: historical benchmark log for older versions.
- `90-archive/scoring-snippets-legacy.md`: legacy scoring notes and scratch snippets.

## Maintenance Rules

1. Keep active release/runtime docs in `00` to `30` folders only.
2. Move old benchmarks and scratch notes to `90-archive`.
3. When a release is prepared, update:
   - `module.prop`
   - `update.json`
   - `CHANGELOG.md`
   - local release notes under `Docs/gui-reference-local/`
4. Avoid adding new docs at `Docs/` root (exception: `plan.md` as release roadmap).
5. Keep private or in-progress guides under `Docs/gui-reference-local/` (gitignored; not published).
