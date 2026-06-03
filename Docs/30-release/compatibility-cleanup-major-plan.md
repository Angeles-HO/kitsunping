# Compatibility Cleanup Plan (Major Release)

This document tracks compatibility wrappers introduced during the non-breaking migration and defines safe removal criteria for a future major release.

## Goal
- Keep current runtime stable (no breaking changes now).
- Identify wrappers that can be removed once all consumers use new canonical paths.
- Provide explicit checks before deleting each compatibility layer.

## Release target and scope

- Current stable line: `6.30 - Release`
- Next active milestone: `7.0 - Beta`
- `7.0 - Beta` scope:
  1. Keep runtime backward-compatible for existing users.
  2. Finish internal migration so canonical paths are first-class in runtime and docs.
  3. Keep wrappers available, but mark every remaining legacy path with clear deprecation notes.
  4. Publish a validation report (boot, daemon, policy, calibration, uninstall) before opening the beta tag.

## Canonical paths (current)
- Runtime cycles: `network/*`
- Daemon loop orchestration: `core/runtime.sh`
- Policy: `policy/engine`, `policy/executor`, `policy/rules`
- Calibration: `calibration/*`
- Boot/install scripts: `installer/*`

## Compatibility wrappers inventory

### 1) `addon/functions/daemon_*_cycle.sh`
- Status: **KEEP for now**
- Reason: `addon/daemon/daemon.sh` still sources these legacy files.
- Remove when:
  1. `addon/daemon/daemon.sh` no longer sources `addon/functions/daemon_*_cycle.sh`
  2. Runtime uses only `network__*` / `network_*` entrypoints
  3. One full regression pass is green

### 2) `addon/policy/*.sh`
- Status: **KEEP for now**
- Reason: docs and external tooling may still call legacy policy paths.
- Remove when:
  1. No internal shell reference to `addon/policy/` remains
  2. Docs and helper scripts reference only `policy/*`
  3. At least one release cycle has shipped with deprecation notice

### 3) `addon/Net_Calibrate/calibrate.sh`
- Status: **KEEP for now**
- Reason: fallback path in `policy/executor/executor.sh` and possible external callers.
- Remove when:
  1. Fallback in executor is removed
  2. No script/doc references `addon/Net_Calibrate/calibrate.sh`
  3. Calibration path `calibration/calibrate.sh` validated across install + runtime

### 4) `scripts/*.sh`
- Status: **KEEP for now**
- Reason: compatibility bridge to `installer/*`, and potential Magisk/packaging expectations.
- Remove when:
  1. Packaging/install flow is confirmed to use `installer/*` only
  2. No permission/setup logic depends on `scripts/*`
  3. One release cycle published with deprecation warning in changelog

## Pre-removal checks (mandatory)
1. Run grep audit for each legacy path and confirm zero hits in runtime code.
2. Validate module boot lifecycle:
   - post-fs-data phase
   - late_start service
   - daemon start/restart
3. Validate policy + calibration flow:
   - profile change event
   - executor apply
   - calibration run/skip logic
4. Validate uninstall flow and permission setup.
5. Update docs/changelog in same release.

## Recommended deprecation sequence
1. Mark wrappers as deprecated in docs (already started).
2. Remove internal references first (keep wrappers present but unused).
3. Ship one release with wrappers still included.
4. Remove wrappers in next major and update migration notes.

## Execution checklist to 7.0 - Beta

1. Canonical-path audit
  - Confirm daemon/policy/calibration code paths prefer `installer/*`, `policy/*`, `calibration/*`, `network/*`.
2. Wrapper usage report
  - Produce grep-based report of remaining references to `addon/policy/*`, `addon/Net_Calibrate/*`, and `scripts/*`.
3. Direct-install packaging validation
  - Verify release ZIP keeps Magisk hooks at module root (`service.sh`, `post-fs-data.sh`, `uninstall.sh`).
4. Runtime regression pass
  - Validate post-fs-data, service start, daemon loop, profile switch, calibration gate, and uninstall restore.
5. Beta publication gate
  - Update docs/changelog with `7.0 - Beta` notes and publish only after all checks are green.
