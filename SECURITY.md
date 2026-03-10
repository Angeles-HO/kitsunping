# Security Policy

This document explains how to report security issues responsibly and how
security-sensitive contributions are handled in this repository.

## Reporting a Vulnerability

If you discover a security vulnerability, do not open a public issue.

- Contact maintainers privately at `angelesho@pm.me`.
- Include clear reproduction steps, affected Android/device details, and
  expected vs actual behavior.
- If available, include logs, proof-of-concept, and impact assessment.

We will acknowledge receipt as soon as practical and follow up privately.

## Disclosure Process

- Initial triage: validate impact and scope.
- Mitigation: prepare and test a fix.
- Coordinated disclosure: publish details after a fix is available when
  possible.

Please avoid public disclosure before maintainers have time to patch.

## Scope

Security reports are especially relevant for:

- Privilege escalation opportunities in installer/runtime scripts.
- Unsafe file/path handling (symlink/path traversal risks).
- Network/authentication weaknesses in router/app integration.
- Data leakage from logs/cache or unintended persistence of sensitive data.

## Policy for Binaries (Important)

To reduce supply-chain risk, contributions should avoid adding or modifying
prebuilt binaries unless strictly necessary.

If a PR adds or updates binaries (for example under `addon/`), the PR must
include all of the following:

- Why the binary is required and why a script/source alternative is not enough.
- Exact origin (official project/repository URL and version/tag).
- License and redistribution rights.
- Integrity details (recommended: SHA-256 checksums).
- Build/reproducibility notes when possible.
- Any security implications for users (permissions, runtime behavior).

Maintainers may reject binary updates that do not provide sufficient provenance
or justification.

## Hardening Recommendations for Contributors

- Prefer POSIX `sh`-compatible code and safe quoting of variables.
- Validate all paths and external inputs before use.
- Avoid storing credentials/tokens in repository files.
- Keep logs free of sensitive values.

## Supported Versions

Security fixes are typically applied to the latest maintained branch/version.
Older versions may receive fixes at maintainer discretion.
