# Binary Paths and Resolution

This module now resolves bundled binaries through a centralized helper:

- File: `addon/functions/utils/env_detect.sh`
- Functions: `kp_detect_abi`, `kp_build_bin_path`, `export_kitsunping_bin_path`

## Canonical Search Order

For each tool (`ip`, `ping`, `jq`, `bc`) the resolver uses this order:

1. `addon/bin/<abi>/` (future-ready canonical layout)
2. Existing legacy folders (`addon/ip`, `addon/ping`, `addon/jq/<abi>`, `addon/bc/<abi>`)
3. System binaries (`command -v ...`)

`<abi>` is auto-detected as `arm64` or `arm`.

## Runtime Behavior

- Daemon loads module binary directories into `PATH` after sourcing helpers.
- Calibration uses detector functions (`detect_ip_binary`, `detect_jq_binary`, `check_and_prepare_ping`) instead of hardcoded paths.
- Permission setup already includes `addon/bin` for executable bits.

## Migration Note

You can move binaries gradually to `addon/bin/<abi>/` without breaking old builds.
Legacy locations are still supported.
