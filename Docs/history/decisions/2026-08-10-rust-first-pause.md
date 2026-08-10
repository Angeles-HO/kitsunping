# Rust-first Research Pause

Decision date: 2026-08-10

Status: ACTIVE PAUSE

## Decision

Pause all Rust/Bash migration, A/B performance campaigns, MIG-002 selection,
property work, Runtime Observatory changes, SG2008, and Wireshark work until
explicit operator direction.

## Rationale

`network.discovery/v1` is functionally promoted only in its documented scope.
The available performance evidence is not sufficient to claim a global runtime
or energy benefit. Historical campaign state has been preserved so future work
can start from Git-tracked facts rather than conversational memory.

## Constraints during the pause

- Do not run native and Bash collectors in parallel during normal runtime.
- Keep Bash fallback strict and reactive.
- Do not select a new migration automatically.
- Preserve device and raw campaign evidence before any future cleanup.