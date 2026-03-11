# Privacy and Telemetry - Kitsunping

This document explains what data Kitsunping reads, how it is used, where it is stored, and whether any telemetry exists.

## Privacy Summary

Kitsunping is designed to work locally on the device.

- It does **not** upload data to remote servers.
- It does **not** include telemetry.
- It does **not** share data with third parties.
- It only reads network/system information required to apply profiles and run calibration.

## What data is used

Kitsunping may read:

- Network state (Wi‑Fi/mobile transport, interface status, signal/score context)
- System properties required for operation (for example carrier/network related props)
- Local test outputs from tools such as `ping`, `ip`, `iw`, `jq`, and `bc`

This data is used only to decide and apply local network optimizations.

## Local storage paths

Operational data is stored locally under the module folder, mainly in:

- Logs: `/data/adb/modules/Kitsunping/logs/`
- Cache/state: `/data/adb/modules/Kitsunping/cache/`
- Config files: `/data/adb/modules/Kitsunping/config/`

Users can inspect these files directly on their device.

## Telemetry Statement

Kitsunping has no telemetry pipeline.

- No analytics endpoint
- No background data upload service
- No remote event reporting

All processing stays on-device unless the user manually exports/shares files.

## App / Module / Router Data Exchange (KitsunRouter)

For router-related features, Kitsunping may exchange data between:

- Kitsunping App (device)
- Kitsunping module (device)
- Compatible router agent (local network)

This exchange only happens when all of the following are true:

- The user has paired/linked Kitsunping with the router.
- The router is explicitly using OpenWrt mode.
- `router_agent.sh` has been installed and is running on the router.

Typical exchanged data can include:

- Router pairing status
- Router identity/fingerprint fields (for example BSSID/signature-derived values)
- Local router connection metadata used by pairing logic
- Optional local control fields needed to keep app/module/router state in sync

Important scope notes:

- This exchange is intended for local operation (device and local router path).
- It is used for functionality (pairing, state sync, capability detection), not analytics.
- It is not a telemetry channel and is not designed to upload user data to third-party servers.

