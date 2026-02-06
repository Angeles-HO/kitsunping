# Daemon - Kitsunping

### Description

Daemon is a background service that continuously monitors network connectivity and performance. Kitsunping daemon specifically focuses on pinging predefined servers to assess network latency, packet loss, and overall stability. It helps in determining the quality of the network connection and can trigger events based on the network status.

### Features

- **Continuous Monitoring**: exists 2 type of monitoring, interval-based and event-based. This reduce battery, cpu, ram usage.
- **Customizable Ping Targets**: Users can define which servers to ping for more relevant results.
- **Adaptive Algorithms**: Utilizes algorithms like sigmoid to evaluate network status more accurately in such way that it adapts to changing network conditions in smoother way.
- **Event Emission**: Can emit events based on network status changes, useful for apps that need to respond to connectivity changes.
- **Debugging Support**: Provides detailed logging options for troubleshooting network issues. Allows developers to fine-tune the daemon's performance.
- **Performance Tuning**: Users can adjust parameters like ping timeout and check intervals to balance accuracy and resource consumption.
- **Lightweight**: Designed to have minimal impact on device performance and battery life.
- **Compatibility**: Works across various Android versions and device configurations.
- **Open Source**: Available for customization and improvement by the community.

### Configuration

When the module is installed the user can select Static (Stable) or Dynamic (Adaptive) mode for Kitsunping Daemon from the Kitsunping App settings.

### Usage

The module works whit autonomously once installed and configured. Users can monitor network performance through the Kitsunping logs.

### Simulate ejecution

Below is a mind map showing how the execution of Daemon would be.

Before of installation of Kitsunping.zip and reebot the device the daemon is execute on late-service of android, so the user don't need to do anything else after installation.

Before in the use cotidian every 30 minutes (can be configured by the user) the daemon will check the network status and adapt the parameters to the current network conditions, also if daemon detect a change on the network through the event-based monitoring it will do a check immediately.

When conditions are met, the daemon emits events and spawns the **Executor**. The executor applies the target profile and decides if a calibration should run (cooldown + low-score streak).

When calibration is ongoing, the **executor/calibration pipeline** writes `cache/calibrate.state` and `cache/calibrate.ts`. These files can be read by the Kitsunping App (Not yet implemented) to show the user the current status of the calibration.

To avoid interference between daemon probing and calibration pings, the daemon skips Wi‑Fi probes/penalties while `cache/calibrate.state=running`.

Before apply the best parameters obtained from the last calibration and applycated whit resetprop for not reboot the device, the Executor will write the current profile applied in the policy.current file. The daemon (or an external policy selector) may write the desired profile to policy.request (informational) and trigger the executor.

Executor reads policy.target (target profile) and compares it to policy.current (last applied). If they differ, the executor applies the profile and updates policy.current, plus calibrate.* state to avoid repeated runs.

also if determinate to need change de profile uses decide profile and execute a x_profile.sh script located on Kitsunping/net_profiles/ folder to apply additional configurations for the selected profile.

```mermaid
flowchart TD
    A[System boot] --> B[Magisk stage: post-fs-data.sh]
    B --> C[Magisk stage: service.sh]
    C --> D{sys.boot_completed == 1?}
    D -->|wait| D
    D -->|yes| E[Apply base network tweaks<br/>sysctl + defaults]
    E --> F[Start Kitsunping daemon<br/>addon/daemon/daemon.sh]

    F --> G[Init logs + cache + pidfile]
    G --> H[Detect binaries<br/>ip/ping/jq/bc/resetprop]
    H --> I[Main loop<br/>every INTERVAL]

    I --> J[Read iface + Wi-Fi state]
    I --> K[Read mobile state]
    J --> L[Compute Wi-Fi score<br/>link/ip/egress + RSSI + probe]
    K --> M[Compute mobile score<br/>link/ip/egress]
    M --> MM[If mobile egress: poll signal<br/>write signal_quality.json]
    L --> N[Write daemon.state]
    M --> N

    N --> O{State changed?}
    O -->|iface wifi signal| P[Write event files<br/>daemon.last + event.last.json]
    P --> Q[Spawn executor async<br/>policy executor.sh]
    O -->|no| I

    %% Profile decision:
    %% - Daemon emits PROFILE_CHANGED when desired profile changes
    %% - Executor is the single-writer of policy.target/policy.current
    Q --> R{EVENT_NAME == PROFILE_CHANGED?}
    R -->|yes| S[Write policy.target using atomic]
    R -->|no| T

    T --> TT{policy.target exists?}
    TT -->|no| I
    TT -->|yes| U[Compare policy.target vs policy.current]
    U --> V{Different?}
    V -->|no| I
    V -->|yes| W[Apply profile if available]

    W --> X{Calibration gating<br/>cooldown and low score streak}
    X -->|run| Y[Run calibrate.sh<br/>logs/results.env]
    Y --> Z[Apply BEST values<br/>via resetprop]
    Z --> AA[Update state files<br/>policy.current + calibrate.*]
    AA --> AB[Write policy.event.json]
    AB --> I

    subgraph State_Files[State files cache/]
        SF1[daemon.state]
        SF2[daemon.pid]
        SF3[daemon.last]
        SF4[event.last.json]
        SF5[signal_quality.json]
        SF6[policy.request]
        SF7[policy.target]
        SF8[policy.current]
        SF9[policy.event.json]
        SF10[calibrate.state]
        SF11[calibrate.ts]
        SF12[calibrate.streak]
    end

    subgraph Logs[Logs logs/]
        LG1[daemon.log / daemon.err]
        LG2[policy.log]
        LG3[services.log]
        LG4[results.env]
    end

    N -.-> SF1
    F -.-> SF2
    P -.-> SF3
    P -.-> SF4
    MM -.-> SF5
    S -.-> SF7
    AA -.-> SF8
    AB -.-> SF9
    AA -.-> SF10
    AA -.-> SF11
    AA -.-> SF12
```
---

#### Daemon / Kitsunping Properties
### Debugging and Performance Tuning
- **kitsunping.daemon.interval**: Sets the interval for daemon checks in seconds (default: 10 seconds).
- **persist.kitsunping.debug**: Toggles debug mode for detailed logging (0: disable | 1: enable).
- **persist.kitsunping.ping_timeout**: Tuning value used by calibration/probing (currently used as a ping count in `Net_Calibrate/calibrate.sh`; default: 7).
- **persist.kitsunping.emit_events**: Enables/disables emitting events and spawning the executor (0/1 or false/true; default: true).
- **persist.kitsunping.event_debounce_sec**: Debounce window for events in seconds (integer > 0; default: 5; auto-raised to at least `kitsunping.daemon.interval`).

### Wi‑Fi decision
- **kitsunping.wifi.speed_threshold**: Wi‑Fi quality threshold used to choose profile (score 0–100). If `wifi.score >= threshold` the daemon tends to request `speed`, else `stable`.

### Calibration cache (Net_Calibrate)
- **persist.kitsunping.calibrate_cache_enable**: Enables/disables reusing previous BEST_* values (0/1).
- **persist.kitsunping.calibrate_cache_max_age_sec**: Max cache age before forcing full calibration (seconds).
- **persist.kitsunping.calibrate_cache_rtt_ms**: Max RTT (ms) allowed to reuse cache.
- **persist.kitsunping.calibrate_cache_loss_pct**: Max packet loss (%) allowed to reuse cache.

### Kitsunping daemon functions calibration

- **kitsunping.daemon.algorithm=sigmoid** : Sets the algorithm used for network status evaluation to sigmoid (planned; may be a no-op depending on version).
- **kitsunping.sigmoid.alpha**: Alpha parameter for composite scoring (default fallback is applied if unset).
- **kitsunping.sigmoid.beta**: Beta parameter for composite scoring (default fallback is applied if unset).
- **kitsunping.sigmoid.gamma**: Gamma parameter for composite scoring (default fallback is applied if unset).