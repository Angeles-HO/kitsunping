# Network Profiles

Kitsunping can apply different “profiles” (sets of tunables) depending on current connectivity and quality.

Profiles are implemented as shell scripts and are applied by the policy executor.

## Available profiles

These are the profiles currently present in this repo:

- **speed**: prioritizes throughput (download/upload).
- **stable**: prioritizes stability and safe defaults.
- **gaming**: intended for lower latency / responsiveness (still evolving).

Profile scripts live in: `net_profiles/`

## How a profile gets selected

High-level flow:

1) The daemon monitors Wi‑Fi/mobile status and writes state to `cache/daemon.state`.
2) When an event happens (Wi‑Fi join/leave, iface change, degraded signal), the daemon triggers the executor.
3) If a profile decision is made (built-in or via `addon/policy/decide_profile.sh`), a `PROFILE_CHANGED` event is emitted.
4) The executor writes/reads `cache/policy.target`, compares it vs `cache/policy.current`, and applies changes when needed.

See the full flow diagram in Docs/Daemon.md.

## Trade-offs / notes

- Profiles that increase TCP buffers or aggressive tuning may increase RAM usage and slightly affect battery.
- Some tunables can be vendor/ROM dependent (Qualcomm vs MediaTek behavior differs).
- If you want to add a new profile, keep it:
	- idempotent (safe to re-run),
	- defensive (skip missing files/props),
	- quiet unless debug is enabled.

## Contributing

PRs are welcome:

- New profile scripts under `net_profiles/`
- Improvements to selection logic (policy)
- Better documentation per-device (MTK vs QCOM)
