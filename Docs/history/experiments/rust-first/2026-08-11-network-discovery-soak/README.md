# network.discovery/v1 Read-only Soak

Run ID: `network-discovery-v1-soak-20260811`

Status: COMPLETED observer window / INCONCLUSIVE soak result

## Method

An external read-only observer sampled the Bash daemon, `kitsunpingd`, native
snapshot presence and age, discovery declarations, link/IP/egress state, and
RSS at five-minute intervals. Runtime Observatory, profiler, tracefs, fallback
metrics, packet capture, properties, and policy changes remained disabled.

## Result

The requested 24-hour observer duration completed. The expected sample count
was 289; the observer recorded 32 samples:

```text
native_valid=29
native_stale=3
native_invalid=0
native_missing=0
daemon_nonrunning=0
sidecar_nonrunning=0
snapshot_age_max_seconds=1058
sample_gap_max_seconds=22075
```

The observer did not determine the cause of its long gap, so this result cannot
establish continuous runtime stability or authorize the packet/network phase.
The device was healthy after closure, with daemon and sidecar running and the
profiler and tracefs disabled.

## Evidence

Raw evidence remains in the external local store:

`KitsunpingRuntimeProfiler/artifacts/network-discovery-v1/network-discovery-v1-soak-20260811/read-only-soak/`

The copied health file SHA-256 is:

```text
74773a9265ff556b89977adde8d021209b10b1a5a1e721859611eec6f42decd5
```

## Decision

No automatic retry, packet capture, or migration follows from this run. Any
future soak must first state how coverage gaps and stale observations will be
interpreted without making runtime instrumentation the primary experiment.