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

## Notes

- Runtime fixture tests are host-based and intentionally independent from Android services.
- Keep test fixtures under testdata and testing tracked in git for reproducibility.
