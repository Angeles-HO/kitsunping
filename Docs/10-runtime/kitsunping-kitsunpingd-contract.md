# Kitsunping and kitsunpingd Contract

Status: implementation audit

Last review: 2026-08-10

## Purpose and Scope

This document defines the implemented boundary between the Kitsunping shell
runtime and the `kitsunpingd` Rust binary. It is an implementation audit, not
a roadmap and not a performance claim.

The contract is intentionally narrow. Rust publishes observations; Bash
validates and consumes selected observations. Bash remains the authority for
policy, profile changes, calibration, properties, router interaction, and all
network mutation.

The terms in this document are precise:

- **Published** means that `kitsunpingd` writes a field.
- **Enforced** means that a Bash reader parses and validates the field before
  using it in production control flow.
- **Rust-first** means a valid native result returns before the equivalent Bash
  collector runs.
- **Fallback** means Bash is invoked only after a native load or validation
  failure.
- **Shadow** means a field is diagnostic or mirrors Bash-owned state; it is not
  an independent Rust authority.

## Runtime Boundary

`installer/service.sh` defines the native binary as
`$MODDIR/bin/kitsunpingd`. At boot it starts a native supervisor separate from
the Bash daemon supervisor. The native supervisor derives its interval from
`kitsunping.daemon.interval`, defaults to 10 seconds, and restarts an exited
binary after five seconds. Before each launch it removes the native PID and
lock files, allowing recovery after an ungraceful termination.

The binary accepts:

```text
kitsunpingd [--root MODULE_ROOT] [--interval-seconds N] [--once]
```

For one normal iteration it writes the following files below
`$MODDIR/cache`:

| File | Producer role | Consumer role | Authority |
| --- | --- | --- | --- |
| `kitsunpingd.pid` | Native PID publication | Native supervisor liveness check | Lifecycle only |
| `kitsunpingd.lock` | Single-instance ownership | Native binary and supervisor recovery | Lifecycle only |
| `runtime.capabilities.json` | Capability inventory | No production Bash reader found | Shadow diagnostic |
| `kitsunpingd.snapshot.json` | JSON snapshot of interfaces, route, transport, and capabilities | No production Bash reader found | Shadow diagnostic |
| `daemon.native.state` | Line-oriented native state | Bash snapshot loader and bridge | Contract carrier |

Rust obtains the active IPv4 route using `NETLINK_ROUTE`, reads interface and
link information from `/proc` and `/sys`, and uses configured backend helpers
for Wi-Fi and mobile metadata. It also invokes `dumpsys activity activities`
for the foreground-package field. Therefore, `kitsunpingd` is native-first for
the promoted discovery fields, but it is not a claim that every published field
is free of subprocess execution.

## Publication and Atomicity

The Rust writer creates a PID-specific temporary file with exclusive creation,
writes the full payload, calls `fsync`, and renames it to the final filename.
Readers therefore observe either the previous complete state or the next
complete state, not a partially written state. The same mechanism is used for
the PID, capability JSON, diagnostic JSON, and native state files.

`kitsunpingd` creates `kitsunpingd.lock` with exclusive creation and records
`PID:epoch`. Its drop handler removes the lock only if it still owns the
recorded contents. `SIGTERM` and `SIGINT` request a cooperative stop, after
which the PID file is removed and the lock is released. A `SIGKILL` can leave a
lock behind; the supervisor deliberately removes stale native PID and lock
files before it launches a replacement.

The publication format for `daemon.native.state` is newline-separated
`key=value` pairs. It has no escaping layer. Published values must therefore
remain single-line scalar values. This is an interface constraint for every
future field, not merely an implementation detail.

## Enforced Rust-First Contract: network.discovery/v1

The promoted contract covers only active-interface discovery and Wi-Fi/mobile
link, IPv4, and default-route state. The producer includes these declaration
fields:

```text
daemon.sample_mode=native_primary
network.discovery.contract=v1
network.discovery.primary=BINARY
network.discovery.fallback=SHELL
```

It also publishes the discovery payload:

```text
iface
wifi.iface, wifi.link, wifi.ip, wifi.egress
mobile.iface, mobile.link, mobile.ip, mobile.egress
native.ts_epoch
```

### Consumer Acceptance Rules

`snapshot_loader.sh` reads `daemon.native.state` and accepts the file only
when `native.ts_epoch` is decimal and no older than
`KITSUNPINGD_SNAPSHOT_MAX_AGE_SEC`. The default maximum age is 25 seconds. A
clock value earlier than the native timestamp is treated as age zero rather
than rejected.

`snapshot_bridge.sh` then validates the fields used by discovery:

| Value | Accepted domain |
| --- | --- |
| Interface | `none`, or letters, digits, `_`, `.`, `:`, and `-` only |
| Link | `UP`, `DOWN`, or `UNKNOWN` |
| IPv4 flag | `0` or `1` |
| Egress flag | `0` or `1` |

The bridge does not trust the producer's free-form reason string. It derives
`link_down`, `no_ip`, `no_default_route`, or `usable_route` from the validated
link/IP/egress tuple.

The native result becomes authoritative only in these paths:

| Public Bash reader | Valid native result | Failure behavior |
| --- | --- | --- |
| `get_current_iface` | Returns `iface` immediately | Calls `legacy_get_current_iface` |
| `get_wifi_status` | Returns the validated Wi-Fi tuple and derived reason | Calls `legacy_get_wifi_status` |
| `get_mobile_status` | Returns the validated mobile tuple only when the requested and native interfaces agree | Calls `legacy_get_mobile_status` |

On a valid result these paths record an optional snapshot hit and return before
their legacy collectors. They do not run Bash first or in parallel for
comparison. On a missing file, stale timestamp, malformed value, incomplete
tuple, or mobile-interface mismatch, they record a miss/fallback when the
profiler hooks are present and execute the existing Bash collector.

### Important Versioning Limitation

The declaration fields above are **published but not enforced by the current
Bash loader or bridge**. `snapshot_loader.sh` does not parse
`network.discovery.contract`, `network.discovery.primary`, or
`network.discovery.fallback`, and `snapshot_bridge.sh` does not validate them.
A fresh payload with valid discovery fields is accepted even if those
declaration fields are absent or have a different value.

Consequently, the implemented compatibility gate is the validated semantic
subset above, not a version handshake. `v1` is valuable documentation and is
emitted by the binary, but it does not yet protect readers from an incompatible
future schema. Any incompatible schema change must either preserve the current
keys and domains or add explicit declaration parsing and rejection before a
reader is promoted.

### Loader Cache Constraint

The loader memoizes a successfully loaded snapshot in shell variables.
`get_native_current_iface` resets that cache before loading, while the other
native bridge readers reuse a successful load. Freshness is therefore checked
when the state is loaded, not on every individual bridge call. The normal
runtime reaches current-interface discovery in its cycle, but a future caller
must not assume that a long-lived shell process reloads the file automatically.
Changing reader order or adding a long-running direct consumer requires a
freshness regression test.

## Published Extensions Outside the Promoted Contract

The binary publishes more state than discovery. Publication alone does not
transfer ownership.

| Surface | Current classification | Current consumer behavior | Limitation |
| --- | --- | --- | --- |
| Wi-Fi RSSI | Mixed | A present native value returns before `/proc/net/wireless` or `dumpsys` fallback | No numeric/range contract is certified |
| Extended Wi-Fi metadata | Mixed | Nonempty native BSSID or SSID for the requested interface returns before `iw`/`dumpsys` fallback | BSSID, SSID, channel, and width values are not field-validated as a versioned contract |
| Mobile signal | Mixed | Mobile cycle accepts native RSRP/SINR when mobile egress is active; otherwise it calls `get_signal_quality` | Active-mobile device parity remains open |
| Foreground package | Mixed | Valid native package returns before Bash `dumpsys` parsing | Rust currently calls `dumpsys`; this avoids duplicate Bash collection, not the command itself |
| Capability and JSON snapshots | Shadow | No production reader found | Diagnostic only |
| Scores, profile, target, link context | Shadow | Native state may expose them | They are derived from, or mirror, Bash cache and do not grant Rust policy authority |
| Latency, jitter, loss, probes, scoring, policy, profiles, calibration, properties, router, ONNX | Bash-only | Bash remains the production authority | No native contract is promoted |

The Rust fields `profile`, `target.state`, `target.state.reason`,
`target.state.ts`, and link-context counters are read from Bash cache files.
They are not independently refreshed or freshness-validated by native readers.
They must not be used as a source of truth for policy decisions.

## Observability and Measurement Boundary

`snapshot_metrics.sh` is opt-in. When disabled it removes its own metrics
artifacts and adds no normal-path metric writes. When enabled it records an
estimated avoided external-work count for a helper; it is an operational metric,
not proof of a process-level measurement.

The required performance comparison is:

```text
Bash baseline
versus
Rust-first discovery with Bash fallback
```

A candidate must not run the equivalent Bash discovery collector
preventatively. Bash/Rust equivalence belongs in host fixtures and controlled
device campaigns, not in the production tick.

The preliminary cut is retained in
`KitsunpingRuntimeProfiler/artifacts/network-discovery-v1/rust-first-discovery-ab-20260809-000413/analysis-snapshot-20260810/AB_ANALYSIS.md`.
The completed comparison is recorded in
`KitsunpingRuntimeProfiler/artifacts/network-discovery-v1/rust-first-discovery-ab-20260809-000413/final-analysis-20260810/AB_FINAL_ANALYSIS.md`.
It verifies functional Rust-first consumption over 360 candidate ticks, but
defers a performance-improvement decision because of a recovered candidate
session, higher sampled process cost, baseline stalls, and absent tracefs data.

## Regression Evidence

The contract has focused host coverage for its principal control-flow rules:

| Test | Evidence |
| --- | --- |
| `testing/runtime/test_network_utils_native_contract_validation.sh` | Malformed interface/link/flag fields reject native data and select legacy collectors |
| `testing/runtime/test_network_utils_native_no_parallel_fallback.sh` | Valid native interface, Wi-Fi, mobile, RSSI, and extended Wi-Fi values do not invoke legacy collectors |
| `testing/runtime/test_network_utils_native_snapshot.sh` | Covers fresh snapshot reading, mobile interface matching, mixed readers, and opt-in metrics behavior; it is currently not passing (see test limitation below) |
| `testing/runtime/test_mobile_cycle_native_signal.sh` | Valid native mobile signal avoids `get_signal_quality` in the cycle fixture |
| `testing/runtime/test_target_engine_native_foreground.sh` | Valid native package skips the Bash `dumpsys` fallback; absent native package falls back |
| `Kitsunpingd` Rust unit tests | Lock exclusivity and native-state declaration emission, among other binary behavior |

Host tests establish parsing and control flow. They do not establish modem
parity, vendor compatibility, SELinux behavior, native producer cost, or
performance improvement on a device.

### Current Test Limitation

As of this review, `test_network_utils_native_snapshot.sh` exits early at its
disabled-metrics assertion. The fixture runs with `set -e` and calls
`kitsunpingd_metrics_enabled` inside command substitution before it can append
the expected nonzero status; the function correctly returns `1` when metrics
are disabled, but the subshell exits before `echo $?` runs. This test is
therefore retained as intended coverage, but is not counted as passing evidence
until its assertion is written in a `set -e`-safe form. The other focused
contract tests must remain independent of this fixture failure.

## Change Rules

1. Do not widen Rust authority by adding a published field alone.
2. Preserve the discovery keys and domains until an explicit, enforced schema
   version gate is deployed with negative fixtures.
3. For a new Rust-first surface, define the producer domain, loader parsing,
   semantic validation, exact fallback, host negative tests, device parity,
   rollback artifact, and comparable baseline before promotion.
4. Keep automatic actions separate from diagnostics. Rust observation must not
   silently change profiles, properties, calibration, router state, or network
   configuration.
5. Treat a valid fallback as resilience, never as permission to execute Bash
   preventatively after a native acceptance.
6. Do not interpret a native hit as a performance win. Close a comparable
   campaign and analyze it before changing the classification or selecting the
   next migration.

## Implementation References

- `Kitsunping/installer/service.sh`: separate native and Bash supervisors.
- `Kitsunpingd/src/main.rs`: CLI, single-instance lock, state production,
  publication, signal handling, and atomic writer.
- `Kitsunping/addon/functions/snapshot_loader.sh`: parsing and timestamp gate.
- `Kitsunping/addon/functions/snapshot_bridge.sh`: discovery semantic checks and
  mixed-reader helpers.
- `Kitsunping/addon/functions/network_utils.sh`: Rust-first public discovery
  readers and legacy fallback selection.
- `Kitsunping/network/mobile/cycle.sh`: mobile signal mixed path.
- `Kitsunping/network/app/target_engine.sh`: foreground package mixed path.
- `Docs/10-runtime/rust-first-promotion-audit.md`: promotion classification and
  device-parity scope.
- `Docs/00-overview/v7.1-stable-plan.md`: release boundary and Rust-first
  invariant.