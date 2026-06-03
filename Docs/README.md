# Kitsunping Documentation Hub

Last update: 2026-06-03

This index is the canonical entry point for project documentation. Files are grouped by lifecycle stage to reduce noise and make release work easier.

## 00-overview

- `00-overview/current-module-status-summary.md`: current repository status snapshot and release readiness notes.
- `00-overview/privacy-and-telemetry.md`: privacy boundaries and local-data behavior.
- `00-overview/runtime-locks-and-heavy-tasks.md`: lock model and heavy-task coordination.

## 10-runtime

- `10-runtime/daemon.md`: daemon behavior and runtime flow.
- `10-runtime/implementation.md`: boot stages, runtime components, and state files.
- `10-runtime/network-profiles.md`: profile model and selection flow.
- `10-runtime/wifi-properties-reference.md`: Wi-Fi property reference.
- `10-runtime/binary-paths.md`: bundled/system binary resolution.
- `10-runtime/failsafe-module-status-reference.md`: failsafe and module-status lifecycle.

## 20-router

- `20-router/router-integration-boundary.md`: public integration contract and license boundary.
- `20-router/band-selector.md`: Wi-Fi band-aware profile switching behavior.
- `20-router/m4-passive-notifications.md`: passive channel recommendation notifications.
- `20-router/qos-flow-mvp.md`: router QoS MVP plan (design reference, not release validation).

## 30-release

- `30-release/7.0-beta-scope-opening.md`: official scope and gate criteria for 7.0-beta opening.
- `30-release/architecture-migration-phase1.md`: migration summary for phase 1/2.
- `30-release/compatibility-cleanup-major-plan.md`: compatibility-wrapper retirement strategy.

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
   - `00-overview/current-module-status-summary.md`
4. Avoid adding new docs at `Docs/` root; place them in the correct section.
5. Keep private or in-progress guides under `Docs/gui-reference-local/` (gitignored; not published).
