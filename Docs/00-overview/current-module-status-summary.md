# Kitsunping Current Module Status Summary

Snapshot date: 2026-06-03
Last document refresh: 2026-06-03

## Executive Summary

Kitsunping is currently stable on the `6.30` maintenance line and has accumulated hardening work that is validated by local fixture tests.

Repository focus in this snapshot is the module runtime itself:

- Magisk boot lifecycle (`post-fs-data`, `service`, `uninstall`)
- daemon state and profile orchestration
- policy executor and calibration gating
- router-facing client integration (HTTP push/recommend/apply)
- local diagnostics, failsafe, and recovery behavior

## Current Published Metadata

Current public metadata remains aligned to `6.30`:

- `module.prop`: `version=6.30`, `versionCode=630`
- `update.json`: `version=6.30`, `versionCode=630`, release ZIP URL under `v6.30`
- `CHANGELOG.md`: `6.30 - Release` documented as current stable maintenance line

## What Is Already Landed After 6.01

The current tree includes stable-line hardening work consolidated into `6.30`:

- failsafe and manual rescue behavior
- module-status lifecycle and state signaling
- adaptive sampling
- module conflict detection
- Wi-Fi standard parsing/reporting
- optional local ML logging plus offline ONNX helper tooling
- fixture-based local regression layer for runtime and router HTTP flows

## Validation Snapshot (No Device Required)

Local test runner result at this snapshot:

- command: `sh ./tools/test_all_local.sh`
- status: PASS
- included checks:
  - POSIX compatibility (`compat` and `strict`)
  - Wi-Fi parsing fixtures
  - runtime fixture tests (`testing/run.sh`)
  - router HTTP fixture tests for recommendation/apply/push flows

## Open Work Before 7.0-beta Opening

The formal opening gate remains in `Docs/30-release/7.0-beta-scope-opening.md`.

Key pending milestones:

1. Finalize canonical-path migration boundaries and deprecation packet.
2. Keep stable and beta metadata narratives clearly separated.
3. Publish beta-only release notes with rollback expectations.
4. Run integrated validation before metadata flip.

## Practical Release Guidance (Current Context)

Given the current constraint (no device available for runtime-on-hardware checks):

- safest immediate publication is documentation and project hygiene updates,
- keep runtime metadata on `6.30` until a deliberate beta-opening commit,
- avoid labeling maintenance-only changes as `7.0-beta`.

## Source of Truth Used

This summary was refreshed from the current repository using:

- `module.prop`
- `update.json`
- `CHANGELOG.md`
- `Docs/30-release/7.0-beta-scope-opening.md`
- `tools/test_all_local.sh`
