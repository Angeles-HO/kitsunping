# Kitsunping Magisk Network Optimizer

![License](https://img.shields.io/badge/license-MIT-green)

## Introduction

Kitsunping is a Magisk module focused on improving network stability and responsiveness on rooted Android devices.
It runs automatically in the background and adapts settings based on connection state (Wi‑Fi or mobile data).

## Purpose

Its main goal is to reduce unstable behavior, high latency, and inconsistent network performance across carriers/regions
by applying more suitable settings for the active network.

## What it does and what this README contains

### What it does

- Detects network context (for example, transport type and connection state).
- Applies network profiles when state changes.
- Runs calibration when needed.
- Stores diagnostic results in local logs and cache files.

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

## Acknowledgements

Thanks to **Zackptg5** for binaries/contributions used in this project (for example: `ping`, `KeyBin`, `iw`, `bc`).

All credits belong to their respective authors.

## Privacy

Kitsunping does **not** send data to remote servers and does **not** use telemetry.

- No background uploads.
- No remote logging.
- Operational data stays local on the device.

Detailed reference: [Docs/pricacy.md](Docs/pricacy.md)

## License

This project is released under the MIT License.
See [LICENSE](LICENSE).
