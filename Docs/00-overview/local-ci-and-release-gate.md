# Local CI and Release Gate

Last update: 2026-06-03

This guide defines the minimum validation path before publishing changes.

## Goals

- Keep CI deterministic in GitHub-hosted runners.
- Detect metadata/changelog mismatches before release publication.
- Keep local and remote checks aligned.

## Validation Layers

1. Fast syntax and compatibility checks.
2. Parsing and fixture tests that do not require a physical device.
3. Release metadata gate (version, versionCode, changelog, zipUrl consistency).

## Main Commands

Run full local verification (same base used by CI):

sh tools/test_all_local.sh

Run release gate without tests (metadata only):

sh tools/release_gate_local.sh --skip-tests

Run release gate with tests:

sh tools/release_gate_local.sh

## What CI Runs

Workflow file: .github/workflows/ci.yml

- Trigger: push to main and pull_request.
- Runner: ubuntu-latest.
- Python setup for HTTP fixture mock tests.
- Command executed: sh ./tools/test_all_local.sh

When CI fails, logs are uploaded as artifact local-suite-logs.

## Failure Triage

1. Open CI logs and locate the first [FAIL] marker.
2. Reproduce locally with the same script shown in logs.
3. If failure is in runtime fixtures:
   - Run: sh testing/run.sh
   - Then run only the failing script under testing/runtime or testing/network.
4. If failure is in release metadata:
   - Compare module.prop, update.json, and CHANGELOG.md.

## Release Checklist

1. Update module.prop version and versionCode.
2. Update update.json version, versionCode, and zipUrl tag.
3. Add changelog section header in CHANGELOG.md:
   - ## <version> - ...
4. Run sh tools/release_gate_local.sh.
5. Push and confirm GitHub workflow success.

## v7.0-beta stabilization gate

Before tagging v7.0-beta, complete all checks below.

1. Execute kickoff baseline from `Docs/00-overview/v7-beta-kickoff-checklist.md`.
2. Confirm scope freeze alignment from `Docs/00-overview/v7-beta-scope-freeze-2026-06-30.md`.
3. Run `sh tools/test_all_local.sh` and `sh testing/run.sh` with no unresolved failures.
4. Run `sh tools/release_gate_local.sh` successfully.
5. Confirm docs coherence:
   - index updated in `Docs/README.md`,
   - active runtime docs are in `Docs/00-overview`, `Docs/10-runtime`, `Docs/20-router`,
   - old references moved to `Docs/90-archive`.
6. Validate upgrade path on lab device:
   - install from current stable baseline,
   - reboot,
   - verify daemon healthy startup and no false disable state.

## Notes

- Runtime fixture tests are host-based and intentionally independent from Android services.
- Keep test fixtures under testdata and testing tracked in git for reproducibility.
