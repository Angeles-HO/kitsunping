# Kitsunping Magisk Network Optimizer

Magisk module that tunes radio/network properties based on detected carrier (MCC/MNC) and country, applies provider-specific DNS and ping targets, and calibrates RIL categories to improve stability and throughput on rooted Android devices.

![License](https://img.shields.io/badge/license-MIT-green)

## Problem

- Default radio/RIL properties are generic and often suboptimal for specific carriers and regions.
- Devices may pick slow or distant DNS, increasing latency and packet loss.
- Some devices lack reliable MCC/MNC detection during boot, making automation brittle.
- Bundled tools (ping, jq, ip) can be missing or linked against unavailable libs on certain ROMs.

## Solution Approach

- Detect country (ISO) and carrier (MCC/MNC) and map to provider entries (JSON per country) with DNS and ping targets.
- Calibrate key RIL properties (HSUPA/HSDPA/LTE/LTEA/NR) via iterative ping scoring to pick best values for current network type.
- Fallbacks: if MCC/MNC/ISO unavailable, use default `unknow.json` provider with safe DNS/ping.
- Logging and caching: write best values to cache and system.prop; keep tracing logs under `/sdcard/trace_log*.log` and module logs in `logs/`.
- Resilience: prefer system `ping`; bundled static `jq` for parsing; permission/bootstrap handled in `post-fs-data.sh`.

## Quick Start

1) Flash the module ZIP in Magisk
2) Reboot
3) Check logs in `logs/` (especially `logs/services.log`, `logs/daemon.log`, `logs/policy.log`)

The module applies baseline network tuning in late boot and then starts a daemon that monitors Wi‑Fi/mobile state. When conditions change, it triggers the policy executor to apply profiles and (optionally) run calibration.

## Documentation

- Architecture + daemon flow: [Docs/Daemon.md](Docs/Daemon.md)
- Wi‑Fi / system properties reference: [Docs/wifiProps.md](Docs/wifiProps.md)
- Scoring math (RSRP/SINR/composite): [Docs/helpful.md](Docs/helpful.md)
- Profile notes (concepts): [Docs/speedProfiles.md](Docs/speedProfiles.md)
- Benchmarks / test runs: [Docs/testingResults.md](Docs/testingResults.md)
- Implementation notes (detection, mapping, caching): [Docs/implementation.md](Docs/implementation.md)

## Tests / Benchmarks

Test runs (tables + Mermaid charts) are kept in: [Docs/testingResults.md](Docs/testingResults.md)

---

## Borrowed / Credits / External

This module includes or is inspired by external tools and resources:

- **Keycheck binary**  
  Source and credits:  
  [/addon/Volume-Key-Selector/README.md#credits](/addon/Volume-Key-Selector/README.md#credits)  
  Compiled by **Zackptg5**
- **Static bc binary**
  Source and credits:
  [/addon/bc/README.md#credits](/addon/bc/README.md#credits)  
  Compiled by **Zackptg5** 


All credits belong to their respective authors.

---

## Contributing

Contributions are welcome and appreciated.

You can contribute in the following ways:

- Report bugs or unexpected behavior
- Open issues with suggestions or improvements
- Share test results (before / after) for different carriers or regions
- Contribute carrier/provider data (DNS, MCC/MNC mappings)
- Submit pull requests with fixes, optimizations, or documentation improvements



### Carrier / Provider Data

Network behavior varies significantly by country and carrier.  
If you want to help improve accuracy and stability, please open an **issue** with:

- Country (ISO code)
- Carrier name
- MCC / MNC
- Detected DNS (e.g. `getprop net.dns*`, or similar you can search on build.prop / system.prop with getprop)
- Optional: before / after latency or throughput results

All data sharing is **voluntary**.

---

## Privacy

This module does **not** collect, transmit, or upload any user data.

- No telemetry
- No remote logging
- No background uploads
- No location/GPS access; only reads mcc/mnc from system properties

All logs and cache files remain local on the device unless the user chooses to share them manually.

---

## Other Notes

If you want to read more about parameters, features, or implementation details, start here:

- [Docs/wifiProps.md](Docs/wifiProps.md)
- [Docs/Daemon.md](Docs/Daemon.md)

---

## License

This project is released under the MIT License.  
See the `LICENSE` file for more details.
