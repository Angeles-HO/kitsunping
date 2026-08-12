# Read-only Soak Observer Diagnostic

Run ID: `network-discovery-v1-soak-20260811`

Classification: **D) CAUSE_UNDETERMINED**

## Frozen Result

```text
network.discovery/v1
STATUS: FROZEN / KEEP
SOAK: INCONCLUSIVE
MIGRATION: NO-GO
PACKET CAPTURE: NO-GO
```

This diagnostic does not reinterpret the soak as contract success or contract
failure. It explains only whether the missing observer coverage has a proven
cause.

## Data Preserved

| Field | Observed value |
| --- | ---: |
| Nominal observer window | 24 h / 86,400 s |
| Configured interval | 300 s |
| Expected samples | 289 |
| Observed samples | 32 |
| Native valid | 29 |
| Native stale | 3 |
| Native invalid | 0 |
| Native missing | 0 |
| Daemon non-running | 0 |
| Sidecar non-running | 0 |
| Maximum snapshot age | 1,058 s |
| Maximum sample gap | 22,075 s |
| First to last health sample span | 80,330 s |

`health.tsv` SHA-256:

```text
74773a9265ff556b89977adde8d021209b10b1a5a1e721859611eec6f42decd5
```

The observer source recorded on the device and the tracked source have the
same SHA-256:

```text
5a5f631c9314ec9c1efc645052a8da7f924a6fe7ad568c18ca1c92f2d2ec0955
```

Relevant artifact hashes:

```text
summary.env          b43f0ccae6d93a5db5a5a16459a0e119876b4855bc95c88627d42dd42b4793e2
summary.metrics.env  5bcfc173e278f3fb0a7e0892b1ea5e05f48645e2df2b3d09256c29f8799cd963
metadata.env         e82e74971a6a5ddd1f15eee99612ee87fbd26ee3b11d3d7afc49138bd4e9c01a
observer.log         e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

## Timestamp Evidence

The observer began at epoch `1786406563` and its metadata records completion at
`1786494433`. Its final health row is at `1786486893`, 7,540 seconds before the
completion timestamp. The final observer loop therefore returned after a gap
rather than recording a final sample.

The first 23 samples follow the intended approximately-300-second cadence. The
subsequent observed gaps are:

```text
5,654 s
1,605 s
14,802 s
22,075 s
11,886 s
14,677 s
2,400 s
```

The three stale rows occur after the long-gap regime. They report both daemon
and sidecar as `running`, with Wi-Fi `UP`, IP and egress present, but snapshot
ages of 869, 1,058, and 870 seconds.

## Lifecycle Evidence

- The active boot epoch calculated from current uptime is `1786051889`, before
  the soak start. This excludes a device reboot during this observer window.
- The current boot reason and `/proc/last_kmsg` refer to boot lifecycle data,
  but do not provide an event correlated to any soak-gap timestamp.
- `observer.log` is empty.
- No observer process survived after closure; the PID file alone has no start,
  parent, exit-code, freezer, or scheduler history.
- Existing module logs contain no soak run ID, observer PID, OOM, kill, suspend,
  resume, or restart event correlated to the gaps.
- Existing logcat suspension/wake messages were observed after the soak window,
  so they cannot be used to explain its coverage loss.

## Conclusion

The evidence proves only that the observer did not achieve its requested
cadence and that snapshots were stale at three later observations. It does not
prove whether the observer was suspended, frozen, delayed by scheduler/lifecycle
behavior, or otherwise lost execution time. It also does not prove that the
native producer failed during every observer gap.

Classification is therefore **D) CAUSE_UNDETERMINED**. No new soak, packet
capture, Runtime Observatory change, profiler, tracefs, migration, property
change, router action, SG2008, or Wireshark work is authorized by this result.

## Evidence Location

Raw files remain immutable in:

`KitsunpingRuntimeProfiler/artifacts/network-discovery-v1/network-discovery-v1-soak-20260811/read-only-soak/`