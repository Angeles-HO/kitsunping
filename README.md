# Kitsunping - Android Network Optimizer, Ping Fix & Gaming Latency Reducer (Magisk Module)

![License](https://img.shields.io/badge/license-MIT-green)

## Introduction

Kitsunping is a Magisk module for rooted Android devices that focuses on Android network optimization, lag fix, and lower latency.
It runs automatically in the background and adapts settings based on connection state (Wi‑Fi or mobile data).

## SEO Summary

Kitsunping is a rooted Android network optimizer designed for lower ping, reduced lag spikes, and more stable gaming sessions on Wi‑Fi and mobile data.
It includes automatic profile switching, local diagnostics, and router-aware integration for advanced users.

## Search Intent (Who is this for)

- Users searching for Android ping fix on rooted phones.
- Players looking for lower latency in PUBG Mobile, Free Fire, COD Mobile, Wild Rift, and similar games.
- Users needing Wi‑Fi/mobile transition stability with profile-based tuning.
- Advanced users wanting Magisk network module diagnostics without telemetry.

## Purpose

Its main goal is to reduce unstable behavior, high ping, and inconsistent network performance across carriers/regions
by applying suitable profiles for the active network.

## Features (SEO)

- Reduce ping / latency for online gaming (for example: PUBG Mobile, Wild Rift, Free Fire).
- Android network lag fix for unstable Wi‑Fi and mobile data transitions.
- TCP congestion control optimization references (for example: BBR / Cubic depending on device and kernel support).
- DNS tweak references for faster browsing and reduced DNS lookup delay.
- Bufferbloat reduction strategy through profile-based tuning and safer defaults.
- Automatic profile switching (`speed`, `stable`, `gaming`) based on connectivity events.
- Optional custom profile on boot (`none`, `stable`, `speed`, `gaming`, `benchmark_gaming`, `benchmark_speed`).
- Local logs and cache diagnostics for troubleshooting without telemetry.
- Router protocol client for compatible external router agents via documented HTTP/JSON endpoints.

## Keyword Index

Android lag fix, Android ping reducer, Magisk network module, rooted Android network optimization, mobile gaming latency fix, Wi‑Fi jitter reduction, mobile data stability, bufferbloat mitigation Android, Android TCP optimization, Android DNS latency optimization.

## What it does and what this README contains

### What it does

- Detects network context (for example, transport type and connection state).
- Applies network profiles when state changes.
- Runs calibration when needed.
- Stores diagnostic results in local logs and cache files.

### Technical highlights (from Docs)

- Profile system with `speed`, `stable`, and `gaming` modes (see `Docs/speedProfiles.md`).
- Event-driven daemon flow for profile changes (`PROFILE_CHANGED`) with cache state tracking.
- TCP/IP optimization references including congestion control (`bbr`), TCP window scaling, and SACK.
- MTU optimization references (`ro.ril.set.mtusize`) for mobile data alignment.
- Wi‑Fi and vendor-specific property references (Qualcomm / MediaTek dependent behavior).

> Note: Exact tunables applied at runtime can vary by kernel, ROM, vendor implementation, and device compatibility.

### Quick start

1) Flash the ZIP in Magisk.
2) During installation, choose static or automatic mode.
3) Reboot the device.
4) Check `logs/` and `cache/` to review activity and results.

### Documentation by topic

- Daemon flow and events: [Docs/daemon.md](Docs/daemon.md)
- Internal implementation: [Docs/implementation.md](Docs/implementation.md)
- Wi‑Fi properties: [Docs/wifiProps.md](Docs/wifiProps.md)
- Speed/stability profile notes: [Docs/speedProfiles.md](Docs/speedProfiles.md)
- Test results: [Docs/testingResults.md](Docs/testingResults.md)
- Router/App integration: [Docs/routerIntegration.md](Docs/routerIntegration.md)

> Note: Advanced parameters (technical props/tunables) are documented in the files above to keep this main page simple.

## Router Integration Boundary

Kitsunping includes only the client-side integration needed to exchange data with a compatible router agent.
That integration is limited to documented protocol calls such as authenticated `POST` and `GET` requests.

Router-side implementations, including KitsunpingRouter, are distributed separately, are not part of this MIT repository,
may use a different license, and may evolve independently as long as they remain protocol-compatible.

## GitHub Topics

- `magisk-module`, `android-root`, `network-optimizer`, `ping-fix`, `latency-fix`, `android-gaming`, `sysctl-tweaks`, `tcp-optimization`, `dns-tweaks`, `bufferbloat-reduction`, `wifi-optimization`, `mobile-data-optimization`, `event-driven-daemon`, `local-logs`, `cache-diagnostics`, `router-integration`, `app-integration`, `open-source`, `MIT-license`.


## FAQ

### Does it work on Android 14?

In most cases, yes on rooted devices with compatible kernels/ROMs, but behavior can vary by vendor and security policy.

### Does it always improve ping for gaming?

It can improve consistency and responsiveness, but final ping depends on carrier routing, server region, signal quality, and device modem behavior.

### Does it support both Wi‑Fi and mobile data?

Yes. Kitsunping detects network state and applies profile logic according to current connectivity.

### Is data sent to remote servers?

No. The module works locally and stores operational logs/cache on device only.

## Acknowledgements

Thanks to **Zackptg5** for binaries/contributions used in this project (for example: `ping`, `KeyBin`, `iw`, `bc`).

All credits belong to their respective authors.

## Privacy

Kitsunping does **not** send data to remote servers and does **not** use telemetry.

- No background uploads.
- No remote logging.
- Operational data stays local on the device.

Detailed reference: [Docs/privacy.md](Docs/privacy.md)

## License

This project is released under the MIT License.
This MIT distribution covers the Kitsunping module and its client-side router integration code in this repository only.
Compatible router agents are separate distributions and may use different licensing terms.
See [LICENSE](LICENSE).
