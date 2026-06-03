# Band-Aware WiFi Profile Selector

## Overview

`network__wifi__transport_cycle` (in `network/wifi/cycle.sh`) selects between
`stable` and `speed` profiles based on a composite WiFi score. On 2.4 GHz the
thresholds are raised to reduce flip-flop caused by channel congestion.

---

## Thresholds by Band

| Parameter | 5 GHz / 6 GHz | 2.4 GHz | Config var (2 GHz adj) |
|---|---|---|---|
| **UP threshold** (score needed to enter `speed`) | **75** | **82** (+7) | `WIFI_BAND_2G_UP_ADJ` (default 7) |
| **DOWN threshold** (score below which drops to `stable`) | **67** | **74** (+7) | same adj applied |
| **Streak required** (consecutive cycles confirming intent) | **2** | **3** (+1) | `WIFI_BAND_2G_STREAK_ADJ` (default 1) |
| **Hold (min seconds between switches)** | **45 s** | **45 s** | `WIFI_SWITCH_MIN_HOLD_SEC` |

Base thresholds are tunable via:

```
WIFI_SPEED_UP_THRESHOLD=75        # default, 5 GHz baseline
WIFI_SPEED_DOWN_THRESHOLD=67      # default (UP - 8)
WIFI_SWITCH_STREAK_REQUIRED=2     # default, 5 GHz baseline
```

---

## Decision Flow

```
wifi_score input
       │
       ▼
   band == 2g?
   ├─ YES → threshold += 7, streak += 1
   └─ NO  → use base thresholds
       │
       ▼
   score >= UP_THRESHOLD  → preferred = speed
   score  < DOWN_THRESHOLD → preferred = stable
   otherwise               → preferred = <unchanged>
       │
       ▼
   probe_ok == 0 && preferred == speed?
   └─ YES → preferred = stable  (probe guard)
       │
       ▼
   preferred == current_profile?
   ├─ YES → clear streak/candidate
   └─ NO  → streak++
              streak >= STREAK_REQUIRED  &&  elapsed >= HOLD?
              ├─ YES → commit profile switch → emit PROFILE_CHANGED
              └─ NO  → keep current (building streak)
```

---

## Guards

### probe_ok guard
Added in L2.5. If `wifi_probe_ok=0` (last network probe failed), promotion to
`speed` is suppressed regardless of score. The probe fires every
`NET_PROBE_INTERVAL` cycles and sets `wifi_probe_ok`.

### boot hold guard
Added in L2.5. The timestamp in `cache/policy.boot.ts` (written during boot) is
treated as a recent switch, so the hold period is respected after device reboot
before the selector can move away from the boot profile.

### app override guard
When `cache/target.override.active` exists (set by an app override), the
`gaming`/`benchmark_gaming`/`benchmark_speed` override profile is treated as `stable` for hold-timer
purposes, enabling a fast restore once the override is released.

---

## Configuration

All tunables live in `configs/default.conf` (or a config overlay):

```conf
# Band hysteresis — 2.4 GHz
WIFI_BAND_2G_UP_ADJ=7        # extra points added to UP threshold on 2g
WIFI_BAND_2G_STREAK_ADJ=1    # extra streak cycles required on 2g

# Base thresholds
WIFI_SPEED_UP_THRESHOLD=75
WIFI_SWITCH_STREAK_REQUIRED=2
WIFI_SWITCH_MIN_HOLD_SEC=45
```

---

## Test coverage

`tools/test_wifi_band_ab.sh` exercises four scenarios:

| Test | Band | Score | probe_ok | Cycles run | Expected |
|---|---|---|---|---|---|
| A | 2.4 GHz | 78 | 1 | 1 | `stable` (78 < 82) |
| B | 5 GHz | 76 | 1 | 2 | `speed` (76 ≥ 75, streak met) |
| C | 5 GHz | 76 | 0 | 2 | `stable` (probe guard) |
| D | 2.4 GHz | 83 | 1 | 3 | `speed` (83 ≥ 82, streak met) |

