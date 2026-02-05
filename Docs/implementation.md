# Implementation Notes

This page keeps deeper implementation details out of the main README, while documenting how Kitsunping is structured internally.

## Boot stages (Magisk)

- `scripts/post-fs-data.sh`: early boot stage
  - Sets permissions / prepares the module environment.
  - Runs `service.sh` (and restores SELinux state afterwards).
- `scripts/service.sh`: late boot stage
  - Waits for `sys.boot_completed=1`.
  - Applies baseline network tuning.
  - Starts the daemon.

## Runtime components

### Daemon (monitor)

- Script: `addon/daemon/daemon.sh`
- Purpose:
  - Monitors default interface and Wi‑Fi ↔ mobile transitions.
  - Computes `wifi.score` and `mobile.score` from link/IP/egress, and enriches Wi‑Fi scoring with RSSI + optional probes.
  - When mobile is the egress path, samples radio signal quality and writes `cache/signal_quality.json`.
  - Emits events and spawns the executor asynchronously.

### Policy executor (applier)

- Script: `addon/policy/executor.sh`
- Purpose:
  - Applies the target profile when it differs from the current profile.
  - Runs calibration conditionally (cooldown + low-score streak) and applies BEST_* results via `resetprop`.
  - Emits `cache/policy.event.json` for future UI/APK polling.

### Policy selection (optional)

- Script: `addon/policy/network_policy.sh`
- Purpose:
  - Reads `cache/daemon.state` + `cache/daemon.last` and chooses a profile via `addon/policy/decide_profile.sh`.
  - Writes the chosen profile to `cache/policy.target` (atomically) for the executor to apply.

## Provider mapping / calibration data

- Directory: `addon/Net_Calibrate/data/`
  - Country/provider JSONs for DNS/ping targets.
  - Includes an `unknown.json` fallback when carrier/country cannot be detected.

## Common state files

Stored under `cache/`:

- `daemon.state`: last computed state (iface/transport + wifi.* + mobile.* + composite values)
- `daemon.pid`: daemon process ID
- `daemon.last`: last emitted event (text)
- `event.last.json`: last event (JSON)
- `signal_quality.json`: radio sampling output (JSON)
- `policy.request`: informational “desired profile” written by the daemon
- `policy.target`: target profile for executor to apply
- `policy.current`: last applied profile
- `policy.event.json`: executor summary (for APK polling)
- `calibrate.state`, `calibrate.ts`, `calibrate.streak`: calibration lifecycle

## Tools and fallbacks

Kitsunping tries to be resilient across ROMs:

- Prefers system `ping` / `ip` when available.
- Ships helper binaries (e.g., `jq`, `bc`) and checks executability.
- Uses atomic writes for state files to avoid partial reads.
