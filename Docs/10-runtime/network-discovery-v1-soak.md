# network.discovery/v1 Soak

Status: active, read-only stabilization phase

Started: 2026-08-11

## Scope

`network.discovery/v1` is frozen as the pilot Rust-first contract:

```text
valid, fresh, complete snapshot -> consume native
missing, stale, incomplete, malformed, or invalid snapshot -> Bash fallback
```

No migration is selected during this phase. RSSI, extended Wi-Fi, foreground
package, adaptive sampling, scoring, properties, router work, SG2008, and
packet capture remain outside the soak scope.

## Observation Method

The soak uses an external read-only observer. It does not source module code,
enable the Runtime Observatory, enable snapshot metrics, mutate properties, or
collect traffic. It records a periodic health row with:

- Bash daemon and native sidecar liveness;
- snapshot presence, age, and basic required-field completeness;
- `network.discovery/v1` declarations;
- interface and link/IP/egress state;
- process RSS values.

`fallback_used` and `fallback_reason` are recorded as `unknown` during this
phase because collecting them would require enabling additional runtime
instrumentation. This is intentional: an unknown signal is not reported as
zero fallbacks.

## Duration and Review

The initial window is 24 hours. At 24 hours, review the health file and decide
whether to extend to 48 and then 72 hours without modifying the contract.

The soak is invalidated or paused only for a real safety concern, daemon loss,
snapshot corruption, device-access loss, or an operator stop. Any such event
must be retained as evidence and not converted into a successful soak result.

## Success Criteria

This phase can establish `CONTRACT STABLE`, not "Rust finished". Review for:

- daemon and sidecar continuity;
- fresh, structurally valid snapshots;
- absence of snapshot corruption and repeated lifecycle failures;
- interface, IP, egress, and transport transitions that remain coherent;
- bounded process memory and no orphan processes;
- correct behavior through normal suspend/wake, reconnection, and reboot events
  that happen during ordinary use.

Performance, energy, packet reality, and next migration selection are separate
questions and remain paused until this soak is reviewed.