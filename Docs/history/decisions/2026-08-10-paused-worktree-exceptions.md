# Paused Worktree Exceptions

Status date: 2026-08-10

## Purpose

This record identifies preserved files intentionally left outside commits during
the Rust-first pause. They are not cleanup candidates.

## `bin/kitsunpingd`

The local untracked module binary is not committed because its identity differs
from the native `dist/aarch64-linux-android/kitsunpingd` artifact and the
currently deployed device binary. The deployed/dist SHA-256 recorded in the
pause snapshot is:

```text
ad01137e3d23e542303a35996fc46ab186646e14333ae23d1f0ff45565465bdb
```

Do not package, replace, or delete the local binary until its build provenance,
ABI, source commit, and intended deployment chain are resolved.

## `testing/runtime/test_network_utils_native_snapshot.sh`

This fixture is preserved but not committed as passing contract evidence. Its
disabled-metrics assertion invokes a function that correctly returns nonzero
inside a command substitution under `set -e`; the shell exits before the test
can compare the intended status. This is a test-infrastructure defect, not a
proof of discovery-contract failure.

The approved discovery fixtures are committed separately. Repairing this test
is paused with all Rust/Bash migration work.

## `.gitignore`

The pending `.gitignore` change is also deliberately uncommitted. Its broad
`history/*` rule requires a separate review because Git-tracked historical
evidence is now part of the project record.