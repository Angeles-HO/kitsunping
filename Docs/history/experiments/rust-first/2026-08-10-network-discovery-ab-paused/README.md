# network.discovery/v1 A/B Pause Record

Run ID: `rust-first-discovery-ab-20260810-172133`

Status: PAUSED / ABORTED-BY-OPERATOR

Classification: PARTIAL / INCOMPLETE

## Scope at pause

This was a new Bash-only baseline intended to reach 360 completed ticks with a
separate tracefs fork/exec capture. The sidecar was absent, the profiler was
enabled for the campaign, and tracefs was synchronized before collection.

The operator paused the campaign at 309 completed ticks. The profiler and
tracefs were stopped, and the partial TSV was copied with a SHA-256 checksum.

## Decision

This run is not a benchmark, not an A/B baseline, and not a performance
reference. It is retained for infrastructure and stall investigation only.

## Evidence

Device archive at pause:

`/data/adb/modules/Kitsunping/cache/validation/rust-first-discovery-ab-20260810-172133/baseline/`

Expected preserved files include `samples.partial.tsv`, its SHA-256 file,
`status.env`, tracefs raw output/state, deployed hashes, provenance, and the
external finalizer log.