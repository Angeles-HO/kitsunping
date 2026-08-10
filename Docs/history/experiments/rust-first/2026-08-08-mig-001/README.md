# MIG-001 Historical Record

Status: COMPLETED for the Bash reference; Rust arm INVALID as a reference

## Objective

Establish a first runtime measurement reference before selecting another Rust
migration.

## Recorded outcome

- Bash reached 460 ticks and was treated as the valid reference.
- Its CSV and SQLite exports were considered valid.
- Tracefs synchronization was validated.
- Closure was `manual_stop_after_minimum_threshold`.
- The configured `max_records` limit did not produce the expected
  `session_end` record; this is an infrastructure limitation, not evidence that
  the capture was cleanly auto-finalized.
- Rust was stopped before it became a reference; it reached only 6 ticks and
  428 records.

## Decision

Do not use the Rust arm of MIG-001 for performance comparison, promotion, or
rollback. Keep its raw artifacts as historical diagnostics only.

## Evidence

Raw campaign files remain in the external local evidence store. Their path and
hashes must be recorded in a campaign manifest before any relocation. This Git
summary intentionally does not invent absent raw metrics.