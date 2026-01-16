# Kitsunping Magisk Network Optimizer

Magisk module that tunes radio/network properties based on detected carrier (MCC/MNC) and country, applies provider-specific DNS and ping targets, and calibrates RIL categories to improve stability and throughput on rooted Android devices.

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

## What was researched / engineered

- Carrier/provider mapping: country JSONs and `unknow.json` fallback with DNS/ping per provider.
- Detection paths: `gsm.sim.operator.iso-country`, `debug.tracing.mcc`, `debug.tracing.mnc`; fall back to defaults when absent.
- Static jq: built a static jq (arm64) with no external deps to avoid `libandroid-support` issues seen on some ROMs; ensured executable permissions in module install.
- Tooling fallbacks: search for `ping` across common system/vendor paths; verify executability and functionality; warn and bail cleanly if missing.
- SELinux handling: temporary permissive during early boot actions, restored after service completion.
- Caching strategy: per-MCC/MNC cache file with provider/DNS/ping; skip recompute when cache is valid.

## Build/Install Notes

- Magisk module layout with `post-fs-data.sh` (early perms + service launch) and `service.sh` (late network tuning).
- `addon/jq/arm64/jq` is shipped static; ensure 0755 perms (handled by install scripts).
- `setup.sh` drives mode selection (fixed vs automatic calibration) during flashing; outputs results to `system.prop` and logs to `logs/results.env`.
- If bundled `ip`/`ping` are unusable, the scripts prefer system binaries.

## Borrowed / Credits / External

- Keycheck Info: [keycheck binary](/addon/Volume-Key-Selector/README.md#credits)
  - [keycheck binary](/addon/Volume-Key-Selector/README.md#credits) compiled by [Zackptg5](/addon/Volume-Key-Selector/README.md#credits).
