# Architecture Migration - Phase 1 + 2 (non-breaking)

This phase introduces functional layers without breaking existing Magisk/runtime paths.

## Added layers
- `lib/`
  - `logging.sh`
  - `validation.sh`
  - `lock.sh`
  - `json_helpers.sh`
  - `time_helpers.sh`
- `network/`
  - `wifi/cycle.sh`
  - `mobile/cycle.sh`
  - `app/cycle.sh`

## Integration point
- `addon/daemon/daemon.sh` now:
  - sources new `lib/*` files when present.
  - sources `network/*/cycle.sh` wrappers when present.
  - executes `network_*` functions with fallback to original `daemon_run_*` functions.
  - sources `core/runtime.sh` when present and delegates loop orchestration there.

## Phase 2 delivered
- Added `core/runtime.sh` with:
  - `core_daemon_iteration`
  - `core_daemon_main_loop`
- Moved daemon loop orchestration out of `addon/daemon/daemon.sh` into `core/runtime.sh` (with fallback loop kept in daemon).
- Added namespace-style aliases in network layer:
  - `network__wifi__*`
  - `network__mobile__*`
  - `network__app__*`
- Migrated concrete mobile implementation:
  - `daemon_run_mobile_cycle` and `daemon_run_mobile_transport_cycle` logic now lives in `network/mobile/cycle.sh`.
  - `addon/functions/daemon_mobile_cycle.sh` is now a compatibility wrapper delegating to the network layer.
- Migrated concrete Wi-Fi implementation:
  - `daemon_run_wifi_cycle` and `daemon_run_wifi_transport_cycle` logic now lives in `network/wifi/cycle.sh`.
  - `addon/functions/daemon_wifi_cycle.sh` is now a compatibility wrapper delegating to the network layer.
- Migrated concrete app/domain implementation:
  - `daemon_run_app_event_cycle`, `daemon_run_pairing_sync_cycle`, `daemon_run_target_profile_cycle`, and `daemon_run_router_status_push_cycle` logic now lives in `network/app/cycle.sh`.
  - `addon/functions/daemon_app_cycle.sh` is now a compatibility wrapper delegating to the network layer.
- Split policy layer by responsibility:
  - `policy/engine/network_policy.sh`
  - `policy/executor/executor.sh`
  - `policy/executor/profile_runner.sh`
  - `policy/rules/decide_profile.sh`
  - `addon/policy/*.sh` now acts as compatibility wrappers to preserve legacy paths.
- Migrated Net_Calibrate assets to dedicated calibration layer:
  - `calibration/calibrate.sh`
  - `calibration/data/*`
  - `addon/Net_Calibrate/calibrate.sh` now acts as compatibility wrapper.
- Normalized installer layer:
  - `installer/post-fs-data.sh`
  - `installer/service.sh`
  - `installer/uninstall.sh`
  - `scripts/*.sh` now acts as compatibility wrappers to preserve legacy paths.

> Note: `::` in function names is not portable in `sh`/`ash`; using `network__scope__action` keeps compatibility on Android shells.

## Why this approach
- Keeps compatibility with current file layout and packaging.
- Allows progressive migration of implementation from `addon/functions/*` into functional layers.
- Avoids large one-shot move that can break installer/service paths.

## Next phases
1. Continue internal cleanup/consistency passes and remove dead compatibility paths in a future major release.

See detailed retirement checklist in: `Docs/30-release/compatibility-cleanup-major-plan.md`.
