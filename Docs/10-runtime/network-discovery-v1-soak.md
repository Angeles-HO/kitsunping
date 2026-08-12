# network.discovery/v1 Soak

Status: completed observer window, inconclusive soak result

Started: 2026-08-11

## Outcome

The 24-hour observer window completed, but it does not establish `CONTRACT
STABLE`. The observer expected 289 samples at a five-minute interval and
recorded only 32. The health data contains 29 valid samples and three stale
samples; no invalid or missing snapshots were recorded, and neither daemon nor
sidecar was observed non-running.

The maximum recorded snapshot age was 1,058 seconds and the maximum gap between
samples was 22,075 seconds. The passive observer did not explain whether that
gap was device suspension, observer scheduling, or another lifecycle event.
Do not treat the low sample count as evidence that the contract survived the
whole window uninterrupted.

The evidence is preserved outside the module release tree at:

`KitsunpingRuntimeProfiler/artifacts/network-discovery-v1/network-discovery-v1-soak-20260811/read-only-soak/`

The copied `health.tsv` SHA-256 is:

```text
74773a9265ff556b89977adde8d021209b10b1a5a1e721859611eec6f42decd5
```

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

The initial window was 24 hours. It completed with insufficient coverage, so
there is no automatic extension to 48 or 72 hours and no authorization for
packet capture. A future operator must decide whether to diagnose observer
coverage or launch a new soak window.

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