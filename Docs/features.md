
# Heavy-task locks and interactions

This section documents the locks, properties, and state files used to coordinate heavy tasks (calibration, profile application, and other daemon work) and how they interact with the executor.

## Overview
Kitsunping uses a small set of filesystem locks and Android/system properties to avoid contention between long-running operations. The executor script and the daemon cooperate via:
- Lock directories (under `cache/`)
- Helper lock functions in `addon/functions/*`
- A few small state files used for gating and starvation protection

## Primary locks and signals

### `EXECUTOR_LOCK_DIR` (runtime: `cache/executor.lock`)
Single-run lock for the executor.
- **Implemented in:** [Kitsunping/addon/policy/executor.sh](Kitsunping/addon/policy/executor.sh#L1-L120)
- **Managed by:** `acquire_executor_lock` / `release_executor_lock`
- **Purpose:** Prevents overlapping executor runs

### `CALIBRATE_LOCK_DIR` (runtime: `cache/calibrate.lock`)
Exclusive calibration lock.
- **Managed by:** `acquire_calibrate_lock` / `release_calibrate_lock` in the executor flow
- **Trap:** `set_lock_trap` ensures the lock is released on EXIT

### Heavy-activity coordination and properties
- **Property:** `HEAVY_LOAD_PROP` (default `kitsunping.heavy_load`): numeric prop set/read by the daemon to signal heavy workload
- **Helpers:** `heavy_activity_lock_acquire` / `heavy_activity_lock_release` (in `addon/functions/*`) act as a global heavy-activity lock to serialize heavy tasks
- **Behavior:** If `heavy_load_now` > `HEAVY_LOAD_MAX_FOR_CALIBRATE`, calibration is postponed unless the starvation guard forces priority

## Starvation guard and calibration priority

### Postpone tracking
The executor records postpones in `calibrate.postpone.count` and `calibrate.postpone.ts` to measure how often calibrations have been delayed.

### Forcing priority
If postpone count or age exceed configured thresholds (`CALIBRATE_FORCE_AFTER_POSTPONES` or `CALIBRATE_FORCE_AFTER_SEC`), the executor sets `CALIBRATE_FORCE_PRIORITY`.
- The executor then requests a daemon yield by writing `kitsunping.calibration.priority` via `calibration_priority_write` (preferred) or `setprop` as a fallback, and attempts to acquire the heavy-activity lock, waiting up to `CALIBRATE_FORCE_LOCK_WAIT_SEC` seconds.
- On completion or exit, the executor clears the priority request (`CALIBRATION_PRIORITY_SET` and the prop are reset to 0).

## Relevant state and output files

- `calibrate.state`, `calibrate.ts`, `calibrate.streak`: calibration state (idle/running/cooling/postponed), last calibration epoch, and consecutive low-score streak
- `calibrate.postpone.count`, `calibrate.postpone.ts`: postpone counters & first-ts used by the starvation guard
- `logs/results.env` (`CALIBRATE_OUT`): calibration output file containing `BEST_*` values; the executor maps those to props and applies them (via `resetprop` when available)

## Key interactions (summary)

- `executor.sh` acquires `EXECUTOR_LOCK_DIR` to ensure a single executor run
- When calibration is possible, the executor acquires `CALIBRATE_LOCK_DIR` to prevent concurrent calibrations
- Before running, the executor checks `HEAVY_LOAD_PROP` and may use `heavy_activity_lock_acquire` to proceed when the daemon reports heavy activity
- If heavy activity blocks calibrate, a postpone is recorded. Repeated postpones trigger the starvation guard, which elevates calibration priority and reattempts to obtain the heavy-activity lock
- All locks and temporary priority props are explicitly cleared at end-of-run; `trap` handlers ensure cleanup on unexpected exit

## Maintenance and references

- **Executor:** [Kitsunping/addon/policy/executor.sh](../addon/policy/executor.sh)
- **Helper functions:** [Kitsunping/addon/functions](../addon/functions)
- **Calibrator:** [Kitsunping/addon/Net_Calibrate/calibrate.sh](../addon/Net_Calibrate/calibrate.sh)
