# Beta-2 Runtime Hardening Evidence

Run date: 2026-08-12

Scope: `network.discovery/v1` lifecycle and sidecar binary replacement on the
rooted SM-S901E Android 15 test device. This is a bounded hardening record. It
does not promote another Rust-first surface, start a soak, enable runtime
instrumentation, alter network state, or create a release tag.

## Candidate and Evidence

The candidate sidecar is:

```text
SHA-256: 37f63fe46a1d847d0899676a50e9e06445f9342bf3f6b6507bd3ad7909b070bc
Path:    /data/adb/modules/Kitsunping/bin/kitsunpingd
Mode:    0755
Context: u:object_r:system_file:s0
```

The root-owned device evidence was copied without modification to:

```text
_workspace/artifacts/beta-2-runtime-hardening-20260812/
```

`SHA256SUMS` in that directory is the local manifest for the copied evidence.

## Results

```text
BETA-2 HARDENING

PASS
  lifecycle: separate Bash and native supervisors observed after reboot
  pid: PID re-publication and recovery verified after SIGTERM, SIGKILL, reboot,
       binary downgrade, upgrade, rollback, and final restoration
  lock: live lock owner matched each replacement sidecar PID
  supervisor: restarted the identified sidecar after every tested termination
  SIGTERM: prior PID 15088 stopped; PID 25009 and a 4-second snapshot recovered
  SIGKILL: prior PID 25009 stopped; PID 26162 and a 5-second snapshot recovered
  reboot: boot ID changed, sys.boot_completed=1, Bash daemon and native sidecar
          ran, and the native snapshot was 10 seconds old
  upgrade: 5ee35d8... -> 37f63fe... recovered as PID 32363 with a 7-second
           snapshot
  rollback: 37f63fe... -> 5ee35d8... recovered as PID 1386 with a 6-second
            snapshot
  final restore: 37f63fe... restored as PID 2116 with a 4-second snapshot
  stdout contract: host black-box contract test passed
  stderr diagnostics: host black-box contract test passed for [B] diagnostics
  snapshot atomicity: Rust unit and black-box contract tests passed
  fallback: incomplete native discovery fixture passed and selected Bash
            collectors for omitted required fields
  SHA: final device binary matched 37f63fe46a1d847d0899676a50e9e06445f9342bf3f6b6507bd3ad7909b070bc

UNCONFIRMED
  suspend/resume: `cmd power` exposed no suspend command. Screen-off input is
                  not sufficient evidence of a real suspend/Doze/resume cycle,
                  so this case was not represented as passed.

BLOCKED
  packaging: no complete Magisk ZIP installation or module upgrade/rollback was
             performed. The tested operation was precisely an atomic sidecar
             binary replacement under the running module.

FAIL
  none observed in the executed scope
```

## Device Sequence

1. Sent `SIGTERM` to the identified sidecar. The supervisor started a new PID;
   the new lock owner and fresh native state matched it.
2. Sent `SIGKILL` to the identified sidecar. The supervisor removed stale
   lifecycle files, started a new PID, and published a fresh native state.
3. Rebooted the device. `sys.boot_completed=1`, boot ID
   `e9fd0f0d-dd4a-4fc7-820d-4745b06d2506`, Bash daemon, native supervisor, and
   sidecar all appeared healthy. The state declared `v1`, `BINARY`, and
   `SHELL` for `network.discovery`.
4. Preserved the candidate and atomically replaced it with verified prior
   artifact `5ee35d8c2afff00446a8db36ef1439e6e8f4f64edf90b1fc553ecccaf22f9382`.
   The sidecar restarted coherently.
5. Restored Beta-2, then repeated the replacement as a rollback to the prior
   artifact. Both sides restarted with matching PID, lock, SHA, and snapshot
   checks.
6. Restored the Beta-2 artifact last. The device is left on the candidate SHA,
   with mode `0755` and context `u:object_r:system_file:s0`.

## Host Validation

The following checks passed on the host:

```sh
cargo test --manifest-path Kitsunpingd/Cargo.toml
sh Kitsunpingd/tests/test_public_contract.sh
sh Kitsunping/testing/runtime/test_network_utils_native_incomplete_fallback.sh
sh -n Kitsunping/installer/service.sh
```

The Rust suite reported 25 passing tests. The public contract test covers
`--once`, native declarations, PID/lock lifecycle, graceful termination,
adaptive output, and exact diagnostic behavior. The fallback fixture proves
that missing `iface`, `wifi.egress`, or `mobile.egress` rejects the native
result and preserves the original Bash collectors.

## Final Hardening Review

The final review found one lifecycle defect in the Shell native supervisor.
With `set -e` active, an unguarded `wait "$native_child"` exited the supervisor
subshell immediately when the sidecar returned a nonzero status. That prevented
the existing diagnostic from recording the exit code and prevented the intended
five-second restart path.

`installer/service.sh` now captures the result using `if wait ...; then`, which
is safe under `set -e`. The existing warning remains the diagnostic surface:

```text
[SYS][SERVICE][WARN] Native snapshot sidecar exited rc=<status>; restarting in 5s
```

This line goes to the module service log. It does not add native binary output
or alter the binary's machine-readable stdout contract. The focused public
fixture `testing/runtime/test_native_snapshot_supervisor_recovery.sh` forces a
child exit of `23` and verifies that the warning and recovery path are reached.

After this correction, the focused checks passed:

```sh
sh testing/runtime/test_native_snapshot_supervisor_recovery.sh
sh -n installer/service.sh
cargo test --manifest-path ../Kitsunpingd/Cargo.toml
sh ../Kitsunpingd/tests/test_public_contract.sh
```

The complete `testing/run.sh` and `tools/test_all_local.sh` runs both reached
the same pre-existing failure in
`testing/runtime/test_network_utils_native_snapshot.sh`. That fixture is an
untracked, documented exception: its disabled-metrics assertion exits early
under `set -e`. It is independent of this supervisor change, and no test outside
that known exception failed in either full run.

## Final Device Recovery

The corrected `service.sh` was deployed atomically to the S901E test module:

```text
service.sh SHA-256: 99c376039e6f6727103d93d11c750c3a4480978818ec0c5e3102ba1eb4b77f5d
kitsunpingd SHA-256: 37f63fe46a1d847d0899676a50e9e06445f9342bf3f6b6507bd3ad7909b070bc
```

An isolated harness extracted the native-supervisor functions from the deployed
hook and used an independent temporary module root. Its first sidecar launch
exited `23`; its second launch executed the deployed ELF. The observed chain was:

```text
sidecar PID A: 16561
exit code:     23
supervisor:    16550, alive after the failed wait
diagnostic:    Native snapshot sidecar exited rc=23; restarting in 5s
sidecar PID B: 16763
lock owner:    16763:1786578889
snapshot age:  0 seconds
```

The temporary supervisor and all harness sidecars were removed. The production
sidecar was then restarted through its supervisor and recovered from PID `2116`
to `19565`, with a matching lock and a zero-second snapshot. Final device
read-back recorded a one-second snapshot, live supervisor and sidecar, no
harness sidecars, and contract `v1/BINARY/SHELL`.

The device evidence and a verified local checksum manifest are retained under:

```text
_workspace/artifacts/beta-2-runtime-hardening-20260812/final-supervisor-device/
```

### Full-Suite Classification

| Check | Classification | Result |
| --- | --- | --- |
| `cargo test` | PASS | 25 Rust tests passed |
| `Kitsunpingd/tests/test_public_contract.sh` | PASS | stdout contract, `[B]` stderr diagnostic, lock/PID lifecycle passed |
| `testing/runtime/test_native_snapshot_supervisor_recovery.sh` | PASS | nonzero child exit reaches diagnostic and recovery path |
| `testing/runtime/test_network_utils_native_incomplete_fallback.sh` | PASS | incomplete native state selects Bash fallback |
| `sh -n installer/service.sh` | PASS | corrected hook parses |
| `testing/run.sh` | WAIVED | only `test_network_utils_native_snapshot.sh` failed |
| `tools/test_all_local.sh` | WAIVED | same single documented fixture defect propagated from `testing/run.sh` |

The waiver is narrow: `test_network_utils_native_snapshot.sh` is an untracked
historical fixture whose disabled-metrics assertion exits early under `set -e`.
It was documented as non-passing before this hardening iteration and was not
modified here. The waiver does not apply to any new regression, environment
failure, or unknown result; no such failure was observed.

## Release Decision

```text
BETA-2 HARDENING

lifecycle:         PASS
debuggability:      PASS
contract:           PASS
fallback:           PASS
device_recovery:    PASS
full_suite:         WAIVED
packaging:          BLOCKED
suspend_resume:     UNCONFIRMED
release_candidate:  YES

decision:           PASS
```

`RELEASE_CANDIDATE: YES` applies only to the bounded runtime hardening gate. It
does not claim that a Magisk ZIP lifecycle passed: packaging remains `BLOCKED`
and must be validated independently before publication. Suspend/resume remains
`UNCONFIRMED`. Do not create `v7.1-beta-2` or tag a release from this record.

**BETA-2 HARDENING = FROZEN.** Keep `network.discovery/v1` quiet and leave the
runtime in ordinary use for several days. Wireshark/SG2008 work, if authorized,
is a separate network-reality investigation and must not be interpreted as
Beta-2 runtime validation.

## Packaging And Clean-Install Follow-Up

Follow-up date: 2026-09-01

The previously blocked packaging layer was validated independently using the
workspace `pack_module.py` release packager. The packager synchronized the
official Android sidecar build, staged the Magisk layout, applied the release
`setup.sh` to `customize.sh` transform, and passed its required-file, path,
ignore-rule, and binary-checksum audits.

```text
ZIP:             Kitsunping.zip
ZIP SHA-256:     926529bbfad0056049ed2f2d4f5301df99b673149ac76c7ab4b489eff78cab03
ZIP size:        2725733 bytes
archive files:   124
sidecar SHA-256: b33389846040f76dac96fcb0ffdc16f2594d23805dcaeccecb95bb56b971583d
service SHA-256: 99c376039e6f6727103d93d11c750c3a4480978818ec0c5e3102ba1eb4b77f5d
```

The ZIP was installed as a clean module installation on the rooted SM-S901E
Android 15 test device through `magisk --install-module`. The device-side ZIP
hash matched the host artifact before installation. After reboot, Magisk
promoted `modules_update/Kitsunping` to `modules/Kitsunping`, Android reported
`sys.boot_completed=1`, and root remained available.

The first daemon validation found initial state templates that did not satisfy
the current format, backed them up, rebuilt them, and deliberately exposed
`[STARTING]`. A later healthy cycle promoted the visible status to `ok` without
entering safe mode. Final read-back showed:

```text
enabled:          YES
safe mode:        OFF
Bash daemon:      RUNNING
native sidecar:   RUNNING
native supervisor: RUNNING
discovery:        v1 / BINARY primary / SHELL fallback
conflict risk:    none
```

The historical full-suite waiver above is also closed by this follow-up. The
native snapshot fixture now asserts the disabled return path safely under
`set -e` and checks metrics before disabling and cleaning the metrics window.
`tools/test_all_local.sh` completed all 29 runtime fixture scripts successfully;
the Rust suite passed 25 tests and the native public-contract fixture passed.

This follow-up validates packaging, clean installation, reboot activation, and
initial runtime health. It does not create a release tag or change the frozen
Beta-2 scope.