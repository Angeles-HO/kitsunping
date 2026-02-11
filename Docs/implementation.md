# Implementation Notes

This page keeps deeper implementation details out of the main README, while documenting how Kitsunping is structured internally.

## Boot stages (Magisk)

- `scripts/post-fs-data.sh`: early boot stage
  - Sets permissions / prepares the module environment.
  - Does early boot prep only; does not start runtime services.
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
  - Emits `cache/policy.event.json` for future UI/APK polling, now including `props_failed` + `props_failed_list` so clients know exactly which properties were rejected.
  - The JSON contract (`ts`, `target`, `applied_profile`, `props_applied`, `props_failed`, `props_failed_list`, `calibrate_state`, `calibrate_ts`, `event`) is treated as stable so an eventual broadcast intent can reuse it.

## Timing knobs (summary)

Key time-based controls used by the daemon and executor:

- `kitsunping.daemon.interval`: main daemon loop interval (seconds).
- `persist.kitsunping.event_debounce_sec`: event debounce window (seconds), auto-raised to at least the loop interval.
- `SIGNAL_POLL_INTERVAL`: mobile signal sampling cadence (loops).
- `NET_PROBE_INTERVAL`: Wi-Fi probe cadence (loops).
- `CALIBRATE_COOLDOWN`: minimum seconds between calibrations.
- `CALIBRATE_LOW_STREAK`: consecutive low-score count required to allow calibration.
- `CALIBRATE_DELAY`: delay passed into `calibrate_network_settings`.
- `CALIBRATE_TIMEOUT`: maximum runtime for calibration.
- `CALIBRATE_SETTLE_MARGIN`: reserved post-run settle window.

### Policy selection (optional)

- Script: `addon/policy/network_policy.sh`
- Purpose:
  - Reads `cache/daemon.state` + `cache/daemon.last` and chooses a profile via `addon/policy/decide_profile.sh`.
  - Writes the chosen profile to `cache/policy.request` (informational) and triggers the executor via a `PROFILE_CHANGED` context.

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
- `policy.target`: target profile written by the executor before applying
- `policy.current`: last applied profile written by the executor
- `policy.event.json`: executor summary (for APK polling)
- `calibrate.state`, `calibrate.ts`, `calibrate.streak`: calibration lifecycle
- `calibrate.best.env`, `calibrate.best.meta`: calibration cache (provider-keyed BEST_* values)

## Tools and fallbacks

Kitsunping tries to be resilient across ROMs:

- Prefers system `ping` / `ip` when available.
- Ships helper binaries (e.g., `jq`, `bc`) and checks executability.
- Uses atomic writes for state files to avoid partial reads.

### SELinux / ping preflight

- `check_and_prepare_ping()` now performs two quick probes: a loopback ping (validates `CAP_NET_RAW`) and an external ping (default `8.8.8.8`).
- If loopback fails, logs advise running `setcap cap_net_raw+ep <ping>` or `restorecon -RF <dir>` so bundled binaries retain the proper context on enforcing ROMs.
- Failing the external probe surfaces a clear warning and aborts calibration early instead of silently timing out.

### CALIBRATE_TIMEOUT Adjustment
The `CALIBRATE_TIMEOUT` value was reduced from **1200 seconds** to **600 seconds**. This decision was made after analyzing the calibration process, which takes a maximum of **462 seconds** under all configurations. The new value provides a reasonable buffer while optimizing the timeout duration for better performance.
