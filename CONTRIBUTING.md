# Contributing to Kitsunping

Thanks for your interest in contributing. This file contains short, practical
guidelines to make collaborating smooth and safe for everyone.

## Quick start

- Fork the repository on GitHub.
- Create a feature branch named `feature/short-description` or
  `fix/short-description` from `main`.
- Make small, focused changes and push to your fork.
- Open a Pull Request (PR) against `main`, reference any related issue,
  and include a short description of the change and how to test it.

## Report bugs and suggest features

- For bugs: open an issue with steps to reproduce, device/Android version,
  logs (if available), and expected vs actual behavior.
- For feature requests: explain the motivation, user benefit, and possible
  implementation notes.
- If the issue is sensitive (security, privacy): contact maintainers at
  `angelesho@pm.me` (see `CODE_OF_CONDUCT.md`) instead of posting publicly.

## Code contributions

- Prefer small, reviewable PRs that implement one change at a time.
- Include tests or manual verification steps in the PR description.
- Link the PR to the issue it addresses (use `Fixes #123` when appropriate).
- Maintainers may request changes - please iterate promptly and
  keep communication constructive.

## Coding style & linters

This project contains POSIX-compatible shell scripts. Follow these rules:

- Write POSIX `sh`-compatible code (avoid Bash-only features unless needed).
- Use `set -u` / careful handling of undefined vars; be conservative with
  `set -euo pipefail` in device scripts where appropriate.
- Keep functions small and well-named; prefer explicit checks for files/paths.
- Run `shellcheck` locally and address warnings (install with your package
  manager). Recommended rules: consider fixing the most relevant SC* warnings
  for portability and safety.
- If reformatting, use `shfmt` to keep consistent style.

## Tests and verification

- For scripts that interact with device internals, test on a spare device or
  an emulator; document manual steps in the PR.
- For network-related scripts (e.g., `calibration/calibrate.sh` or
  `addon/Net_Calibrate/calibrate.sh` for legacy compatibility),
  include sample inputs/outputs or a short checklist for verification.
- Add automated checks where possible (linters in CI), but full runtime tests
  that modify device kernel parameters should remain manual.

## Documentation

- Update `README.md` and the `Docs/` folder for any user-facing change.
- If you add commands or utilities, include usage examples and expected
  outputs in the docs.

## Release & packaging notes

- Keep `module.prop` and `update.json` changes coordinated with PR notes.
- If you add or update bundled binaries (in `addon/`), include source,
  licensing info, and a short justification.

## Security & responsible disclosure

- If you discover a security issue, do not open a public issue. Contact the
  maintainers at `angelesho@pm.me` and provide reproducible steps and impact
  details. The maintainers will follow up privately.

## Pull request checklist

- [ ] I have read the `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`.
- [ ] My changes are small and focused.
- [ ] I ran `shellcheck` and fixed issues where practical.
- [ ] I updated documentation as needed.
- [ ] I linked the PR to an issue when appropriate.
