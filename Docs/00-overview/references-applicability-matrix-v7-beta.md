# References Applicability Matrix (v7.0-beta)

Last update: 2026-07-14

## Purpose

This document maps `lib/references/*` topics to the current Kitsunping implementation,
so runtime decisions are based on stable internal references rather than ad-hoc web
searches.

Scope: `v7.0-beta` hardening.

## Evidence baseline

Primary implementation anchors reviewed:

- `network/wifi/cycle.sh`
- `network/app/target_engine.sh`
- `policy/executor/executor.sh`
- `addon/functions/utils/Kitsutils.sh`
- `calibration/calibrate.sh`
- `Docs/10-runtime/daemon.md`
- `Docs/20-router/router-integration-boundary.md`

## Applicability legend

- `direct`: Implemented and actionable now in module/app/router flow.
- `derived`: Not implemented as native feature, but useful as decision pattern.
- `reference-only`: Informational for future architecture, not currently executable.

## Domain matrix

### Wi-Fi concurrency (`lib/references/wifi/concurrency.md`)

- Status: `derived`
- Current fit:
  - Kitsunping does not control Android framework concurrency APIs directly.
  - It does collect band/channel/width and uses router-aware decisioning in
    `network/wifi/cycle.sh`.
- Decision use now:
  - Keep as design guard for router/channel behavior and future app-side controls.

### Wi-Fi onboarding/pairing (`lib/references/wifi/onboarding-pairing.md`)

- Status: `derived`
- Current fit:
  - Pairing boundary is protocol-level (module client <-> router agent), documented in
    `Docs/20-router/router-integration-boundary.md`.
  - No native DPP/TOFU orchestration in module runtime.
- Decision use now:
  - Use as security requirements baseline for pairing UX/API decisions in app/router,
    not as module shell runtime requirement.

### Wi-Fi security (`lib/references/wifi/security.md`)

- Status: `derived`
- Current fit:
  - Profile files include security-related knobs such as `sae_enabled=1` in
    `net_profiles/qcom_*_profile.conf` and are applied through
    `apply_qcom_wcnss_profile`.
  - No direct Passpoint/Carrier Wi-Fi provisioning logic in module.
- Decision use now:
  - Treat WPA3/SAE guidance as chipset/profile policy input.
  - Treat Passpoint/Carrier Wi-Fi as app/router integration roadmap, not beta gate.

### Wi-Fi discovery/ranging (`lib/references/wifi/discovery-ranging.md`)

- Status: `direct` (for probing/scoring), `derived` (for advanced framework APIs)
- Current fit:
  - Runtime already performs active probe/testing and updates latency/jitter/loss windows
    (`network/wifi/cycle.sh`, `calibration/calibrate.sh`).
  - No framework-level RTT API integration from module shell.
- Decision use now:
  - Keep RTT/coex as scoring/selection strategy references.

### Wi-Fi performance/ops (`lib/references/wifi/performance-ops.md`)

- Status: `derived`
- Current fit:
  - Runtime applies profile scripts and resetprops; no direct control over Android
    latency mode APIs or Wi-Fi 7 framework methods.
- Decision use now:
  - Use as vendor/profile tuning guidance and diagnostic vocabulary.

### RIL (`lib/references/ril/RIL.md`, `lib/references/ril/ril.h`)

- Status: `direct`
- Current fit:
  - Calibration and setup actively read/write RIL-related properties (`calibration/calibrate.sh`,
    `setup.sh`, `system.prop`).
  - Runtime monitors radio context (`addon/daemon/iface_monitor.sh`).
- Decision use now:
  - Keep as high-priority operational reference.

### Carrier / cellular advanced / eSIM / UWB / VPN / time

- Status:
  - Time: `derived`
  - Carrier/cellular/eSIM/UWB/VPN: `reference-only` for current module runtime
- Current fit:
  - No direct euicc/UWB/VpnManager/time_detector control path in Magisk shell runtime.
- Decision use now:
  - Use for future app or platform-integration planning only.
  - Do not include as release validation criteria for `v7.0-beta`.

## Internal organization adjustments

1. Keep references as a stable knowledge layer, but separate by execution relevance:
   - operational-now: topics with direct runtime hooks (RIL, probe/scoring, profile application)
   - design-next: topics that guide architecture decisions (pairing/security/concurrency)
   - long-horizon: platform APIs outside current shell scope (eSIM/UWB/VPN manager)

2. Add an applicability marker in each reference front matter:
   - `aplicabilidad: direct | derived | reference-only`
   - `aplica_en: module | app | router | docs`

3. Require evidence path for any “implemented” claim:
   - `evidencia: [path1, path2]`

