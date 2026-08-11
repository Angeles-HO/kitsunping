# Kitsunping Runtime Status

Status date: 2026-08-10

## Production

Kitsunping's Bash daemon remains the authority for policy, profiles,
calibration, properties, router integration, scoring, probes, and network
mutation.

The approved native binary is `bin/kitsunpingd`. Its device deployment identity
must be verified by SHA-256 before a device operation; the status documents do
not authorize replacing the binary.

## Rust-first

`network.discovery/v1` is the only officially Rust-first contract:

```text
valid native snapshot -> validate -> consume native immediately
missing, stale, incomplete, malformed, or invalid snapshot -> Bash fallback
```

Its scope is limited to active interface and Wi-Fi/mobile link, IPv4, and
egress discovery. A fallback is resilience only. Bash must never run
preventively after a valid native result just to compare it.

The current device-parity evidence is 20/20 for active Wi-Fi and
`mobile=none`. This does not establish active mobile-radio parity.

## Bash fallback

Bash runs only when the native binary is unavailable, a snapshot is absent or
stale, required fields are absent, a field format/domain check fails, or native
collection fails. The consumer derives discovery reason codes from validated
values rather than trusting a producer-provided reason.

## Experimental

The following exist but are not promoted as Rust-first contracts:

- Wi-Fi RSSI and extended Wi-Fi metadata: `MIXED`; contract validation and
  comparable device evidence are incomplete.
- Mobile signal quality: `MIXED`; active-mobile device parity is open.
- Foreground package: `MIXED`; the Rust producer can invoke `dumpsys`, so it is
  not a no-command native backend.
- Adaptive sampling, property research, runtime diagnostics, and performance
  monitor tooling: experimental or development-only.

## Historical

Historical campaign summaries, source snapshots, checksums, and decisions are
under `Docs/history/`. Raw TSV/CSV/SQLite/tracefs evidence remains in the
separate `KitsunpingRuntimeProfiler/artifacts/` store and is referenced by
manifest rather than copied into a module release tree.

## Active Stabilization

The `network.discovery/v1` contract is in an active 24-hour read-only soak.
The external observer records lifecycle and snapshot health without enabling
Runtime Observatory instrumentation or a performance campaign. See
`Docs/10-runtime/network-discovery-v1-soak.md`.

## Paused

Rust migration work is **PAUSED until explicit operator direction**.

- `MIG-002`: **NOT SELECTED**.
- Performance campaigns: **PAUSED**; the read-only soak is not a performance
  campaign.
- Property migration: **PAUSED**.
- Runtime Observatory implementation: **FROZEN**.
- SG2008 and Wireshark work: **PAUSED**.

No historical result authorizes a new migration automatically.

## Next Decision

No implementation task is selected. The next action requires explicit operator
approval after reviewing the historical record and current device state.