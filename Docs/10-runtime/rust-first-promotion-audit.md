# Rust-First Promotion Audit

Status: completed for current native consumers

Last review: 2026-08-08

## Scope

This audit records whether existing `kitsunpingd` outputs are actually consumed
as production primaries. It separates contract validation from Bash/Rust parity:
the runtime validates and consumes native data; fixtures and controlled device
campaigns compare native and legacy collectors outside the production tick.

The Runtime Observatory is frozen and was not changed for this audit.

## Rust-First Compliance Result

The audited consumers do not run their equivalent Bash collector after
accepting a valid native result. This is a production control-flow property,
not a claim that every native producer is already free of process launches.

| Reader | Valid native result | Bash collector after acceptance | Result |
| --- | --- | --- | --- |
| `get_current_iface` | returns the validated native interface | `legacy_get_current_iface` is not called | compliant |
| `get_wifi_status` | returns validated native link/IP/egress state | `legacy_get_wifi_status` is not called | compliant |
| `get_mobile_status` | returns validated native link/IP/egress state | `legacy_get_mobile_status` is not called | compliant |
| `get_wifi_rssi_dbm` | returns a present native RSSI value | `/proc/net/wireless` and `dumpsys wifi` fallbacks are skipped | compliant flow; numeric contract still unpromoted |
| `get_wifi_extended_info` | returns nonempty native metadata | `iw`, `dumpsys`, and neighbor fallbacks are skipped | compliant flow; metadata contract still unpromoted |
| mobile signal cycle | accepts native signal JSON | `get_signal_quality` is not called | compliant flow; active-mobile device parity remains open |
| foreground package | accepts native package | Bash `dumpsys window/activity` is not called | compliant flow; Rust currently spawns `dumpsys` itself |

Focused host fixtures cover the first five network readers, malformed discovery
contracts, mobile signal fallback, and foreground fallback. The device evidence
for `network.discovery/v1` remains the deployed binary, strict bridge, rollback
archive, and 20/20 parity run on active Wi-Fi with `mobile=none`.

## Classification

| Surface | Classification | Production behavior | Evidence and gap |
| --- | --- | --- | --- |
| `network.discovery/v1`: active interface, Wi-Fi link/IP/egress, mobile link/IP/egress | RUST-FIRST | `get_current_iface`, `get_wifi_status`, and `get_mobile_status` consume a fresh, validated `daemon.native.state`; Bash collectors run only on unavailable, stale, malformed, or incomplete native data. | Host fixture covers malformed values and legacy fallback. Device parity recorded 20/20 for active interface, active Wi-Fi, and `mobile=none`. A mobile-active device campaign remains required before claiming equivalent mobile-radio coverage. |
| Wi-Fi RSSI | MIXED | `get_wifi_rssi_dbm` consumes a present native value immediately and falls back to `/proc/net/wireless` or `dumpsys` only when native data is absent. | No parallel Bash collector was found. The numeric/range contract is not yet certified; the current native value may be unavailable or device-specific. |
| Extended Wi-Fi information | MIXED | `get_wifi_extended_info` accepts native metadata first, then `iw`, `dumpsys`, and neighbor parsing only when native data is absent. | No parallel collector executes after a nonempty native result, but BSSID/SSID/channel field validation needs a dedicated contract before promotion. |
| Mobile signal quality | MIXED | The mobile transport cycle uses native signal JSON when complete, otherwise calls `get_signal_quality`. | Host coverage exists; an active-mobile device parity campaign is still missing. |
| Foreground package | MIXED | The target engine consumes the native package and returns before its Bash `dumpsys` fallback. | Native collection currently invokes `dumpsys` from Rust. It removes duplicate Bash collection but is not yet a no-command native backend. |
| Adaptive sampling | BASH-FIRST | The local wrapper can invoke `kitsunpingd --adaptive-sampling` with strict output validation and Bash fallback. | The deployed module does not contain that wrapper, so it is not a production Rust-first route. |
| `kitsunpingd.snapshot.json` and `runtime.capabilities.json` | SHADOW | The sidecar writes them for diagnostics. | No runtime consumer was found in the module. |
| Native `wifi.score`, `mobile.score`, profile, target, link-context fields | SHADOW | `daemon.native.state` exposes these fields, but policy and state authority remain Bash. Some values are copied from Bash cache state. | They must not be treated as independent native contracts. |
| Wi-Fi probes, latency/jitter/loss windows, scoring, transition state, target policy, profiles, calibration, properties, router protocol, ONNX | BASH-ONLY | Bash remains the production authority. | No equivalent validated Rust contract is consumed by these paths. |

## Contract Requirements

`network.discovery/v1` accepts a snapshot only when all required values are
valid:

- `native.ts_epoch` is numeric and no older than the configured freshness limit;
- interface names are `none` or contain only letters, digits, `_`, `.`, `:`, or
  `-`;
- link state is `UP`, `DOWN`, or `UNKNOWN`;
- IP and egress flags are `0` or `1`.

The bridge derives the reason code from validated link/IP/egress values instead
of trusting a free-form snapshot reason. Any violation returns failure to the
public helper and selects the legacy Bash collector.

## Promotion Rule

No new migration is selected from this document. A `MIXED` surface may become
`RUST-FIRST` only after it has a versioned contract, negative fixtures, a
comparable device baseline, an equivalent Rust-first campaign, and a rollback
artifact. A fallback is not a reason to run Bash proactively.

The next work is measurement, not MIG-002, property changes, Runtime
Observatory changes, or network traffic analysis. The comparable campaign is
`Bash baseline` versus `Rust-first + Bash fallback`; SG2008/Wireshark work starts
only after that architecture is stable and the measurement decision is made.