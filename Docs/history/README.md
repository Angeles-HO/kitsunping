# Historical Experiments

This directory is the Git-tracked index for completed, partial, invalid, and
paused experimental work. It preserves provenance and decisions; it does not
turn raw development captures into module release content.

## Evidence policy

1. Preserve raw files before classification.
2. Store campaign summaries, hashes, manifests, and repository snapshots here.
3. Keep large TSV, CSV, SQLite, and tracefs files in the external local
   `KitsunpingRuntimeProfiler/artifacts/` evidence store unless a future
   repository policy explicitly admits them.
4. A partial or aborted campaign is never a performance reference.
5. `CURRENT`, `EXPERIMENTAL`, `HISTORICAL`, and `RETIRED` are status labels, not
   deletion instructions.

## Index

- `experiments/rust-first/2026-08-08-mig-001/`: legacy Bash/Rust measurement
  attempt; Bash reference valid, Rust arm not a reference.
- `experiments/rust-first/2026-08-10-network-discovery-ab/`: completed
  Rust-first functional A/B and its performance limits.
- `experiments/rust-first/2026-08-10-network-discovery-ab-paused/`: later
  309-tick baseline paused by operator; incomplete.
- `decisions/`: scope and pause decisions.
- `decisions/2026-08-10-paused-worktree-exceptions.md`: preserved binary,
  fixture, and ignore-rule exceptions not committed during the pause.
- `snapshots/`: Git and device identity snapshots made during archival.

## Current Classification

| Area | Classification |
| --- | --- |
| `network.discovery/v1` runtime contract | CURRENT, limited Rust-first |
| RSSI, extended Wi-Fi, mobile signal, foreground package | EXPERIMENTAL / MIXED |
| Adaptive sampling and property work | EXPERIMENTAL / PAUSED |
| Campaign artifacts and parity runs | HISTORICAL |
| Superseded campaign launch scripts | RETIRED tooling, preserved by manifest |