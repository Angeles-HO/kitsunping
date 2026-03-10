# Kitsunping Changelog

All notable changes to this project will be documented in this file.


## 6.0 - Beta

- [new] Router-aware app/module flow hardened with pairing-gated remote operations while keeping local profiles always functional.
- [new] Channel recommendation and channel-change request flow integrated from app to daemon with explicit user confirmation path.
- [new] Runtime observability improved with richer cache/state exports and local telemetry counters.
- [updated] Wi-Fi decision logic tuned with anti-churn guards, hold period handling, and improved 2.4GHz/5GHz behavior.
- [updated] Installer/runtime shell compatibility hardening for broader `sh` portability.
- [fix] Critical POSIX incompatibilities removed from install/uninstall paths and key selector utilities.
- [fix] Local test workflow improved with reproducible checks (`tools/check_posix_compat.sh`, `tools/test_all_local.sh`, `tools/test_wifi_parsing.sh`).

## 5.01 - Release

- [new] New integration with future KitsunApp for better user experience and easier configuration.
- [new] Better stability on network changes with improved detection and handling of Wi‑Fi and mobile data transitions.
- [refac] Internal code cleanup and re-organization for easier maintenance and less duplicated code.
- [fix] Fixes some issues with the previous beta related to path detection and background runs, improving stability and battery usage.
- [fix] Improved installation process to ensure all components are properly installed and configured across different devices and Android versions.

> Note: The 5.01 release includes all the improvements and fixes from the 5.0 beta, so if you were using the beta, you should see a smoother experience with the final release. If you were not using the beta, you will benefit from all the new features and stability improvements right away with the 5.01 release. Also, this version have better suport for the future Application, so if you want to use it, make sure to update to 5.01 or later.
 
## 5.0 - Beta

- [new] More accurate connection-quality detection to adjust automatically on Wi‑Fi and mobile data.
- [new] Smarter calibration: if you stay on the same operator/provider, it reuses previous results to avoid repeating tests on every reboot.
- [new] Fewer unnecessary changes: better control over when changes are applied for improved stability.
- [updated] More stable switching between Wi‑Fi and mobile data (less jumping and inconsistent decisions).
- [updated] Better efficiency during measurement/calibration so results stay accurate.
- [updated] More reliable installation across devices (fixes internal permission issues that could break module functions).
- [updated] Updated tuning with more conservative values to prioritize compatibility and stability.
- [fix] Prevents duplicate background runs, improving stability and battery usage.
- [fix] Improved internal path detection when running components (fewer failures from wrong paths).
- [refactor] Internal cleanup and re-organization for easier maintenance and less duplicated code.

## 4.86

- Fixed missing congestion control settings in service script.
- Refactored update-binary script for better clarity.
- Fix some issues on calling scripts.

## 4.85

- Initial release of Kitsunping.
