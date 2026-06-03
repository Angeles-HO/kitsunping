# Daemon Failsafe + Module Status System

## Overview

The failsafe layer protects the current stable line `6.30` from corrupted runtime state. It can:

- detect invalid `daemon.state` or `link_context.state` at startup,
- enter `safe_mode` for degraded operation,
- expose the current status in `module.prop`,
- allow a manual rescue path without reinstalling the module.

`7.0-beta` is still the next milestone. The current failsafe flow is part of the `6.30` maintenance hardening work.

## Core components

1. `addon/functions/daemon_failsafe.sh`: validation, safe mode, rescue, and module-status helpers.
2. `cache/module_status.json`: centralized status text and disable policy.
3. `cache/daemon.safe_mode`: degraded-mode flag.
4. `cache/daemon.rescue_requested`: manual rescue trigger.
5. `module.prop`: Magisk-visible description updated at runtime.
6. `disable`: standard Magisk disable flag for `broken_environment` only.

## Status types

- `ok`: normal operation, module enabled.
- `startup`: transient state while the daemon is validating runtime files.
- `safe_mode`: corruption detected, degraded operation enabled.
- `conflict_detected`: overlapping modules detected, module still enabled.
- `recovering`: manual rescue in progress.
- `recovery_complete`: state reset completed, module ready to return to `ok` on next healthy startup.
- `broken_environment`: critical failure, module disabled for safety.

## Workflow

### Startup validation

1. Daemon sources `daemon_failsafe.sh`.
2. `daemon_init_safe_mode()` validates `daemon.state`, `link_context.state`, and cache writability.
3. On the first validation failure, failsafe attempts self-heal and keeps the visible state at `startup` to avoid false positives.
4. If the problem repeats, failsafe writes `cache/daemon.safe_mode` and updates `module.prop` to `[SAFE MODE]`.
5. In safe mode the daemon skips expensive app and policy-trigger cycles, but still monitors connectivity.

### Manual rescue

1. User requests rescue by creating `cache/daemon.rescue_requested`.
2. Main loop checks `daemon_check_rescue_request()` before running normal cycles.
3. `daemon_perform_rescue()` backs up current state into `cache/rescue_backup_*`, resets state files, and clears rescue flags.
4. Module status transitions through `recovering` and then `recovery_complete`.
5. The next healthy startup returns the visible state to `ok`.

## Visible module status

Example `module.prop` description flow:

```bash
description=Kitsunping v6.30 - WiFi 2.4G/5G + TCP + LTE/LTE-A + PPC
description=Kitsunping v6.30 [STARTING]
description=Kitsunping v6.30 [SAFE MODE]
description=Kitsunping v6.30 [RECOVERING]
description=Kitsunping v6.30 [RECOVERED]
```

Disable policy:

- `safe_mode`: no `disable` file.
- `conflict_detected`: no `disable` file.
- `broken_environment`: creates `disable`.
- `ok` and `recovery_complete`: remove `disable` if present.

## Runtime API

Validation helpers:

```bash
daemon_validate_state_files()
daemon_is_safe_mode()
daemon_check_rescue_request()
```

Status helpers:

```bash
daemon_set_module_status status_type
daemon_get_status_description status_type
daemon_get_status_details status_type
daemon_should_disable_module status_type
```

Recovery helpers:

```bash
daemon_init_safe_mode()
daemon_perform_rescue()
daemon_write_disable_file()
daemon_remove_disable_file()
```

## Useful commands

Inspect visible status:

```bash
adb shell cat /data/adb/modules/Kitsunping/module.prop | grep '^description='
```

Check safe mode:

```bash
adb shell [ -f /data/adb/modules/Kitsunping/cache/daemon.safe_mode ] && echo on || echo off
```

Request rescue:

```bash
adb shell touch /data/adb/modules/Kitsunping/cache/daemon.rescue_requested
```

Tail failsafe logs:

```bash
adb logcat | grep '\[FAILSAFE\]'
adb shell tail -f /data/adb/modules/Kitsunping/logs/daemon.log
```

## Local regression coverage

Fixture-based shell coverage now lives under `testing/` and includes:

- rescue request behavior,
- safe mode activation and recovery,
- `module.prop` status updates,
- module conflict detection with synthetic fixtures,
- adaptive sampling transitions,
- ML logging opt-in and ONNX helper checks.

Run it with:

```bash
sh testing/run.sh
```