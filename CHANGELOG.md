# Kitsunping Changelog

All notable changes to this project will be documented in this file.

## 5.0

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
