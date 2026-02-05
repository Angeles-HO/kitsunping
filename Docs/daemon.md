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

When the conditions are completed, daemon determinate First if is needed to do a calibration of the functions, and later apply the best parameters obtained from the last calibration.

when calibrate is ongoing, Daemon white a file named calibrate.state in the cache folder with the current state of the calibration, and a timestamp in the calibrate.ts file, this files can be read by the Kitsunping App (Not yet implemented) to show the user the current status of the calibration.

Before apply the best parameters obtained from the last calibration and applycated whit resetprop for not reboot the device, Daemon will write the current profile applied in the policy.current file and the desired profile in the policy.request file, this files can be read by the Kitsunping App (Not yet implemented) to show the user the current profile applied.

Before, Executor read policy.current and policy.request files to know when apply a new profile, if this are the same the executor will not do anything, if are different the executor will apply the desired profile and update policy.current file. and write the current profile applied in the policy.current file and coling in the calibrate.state to avoid apply the same profile again and again. this occurred every 30 minutes or when the daemon detect a change on the network through the event-based monitoring.

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

    %% Profile decision happens in 2 ways:
    %% 1) Daemon emits PROFILE_CHANGED (mainly when mobile egress + scoring)
    %% 2) A policy script writes policy.target (e.g., addon/policy/network_policy.sh)
    Q --> R{policy.target exists<br/>or PROFILE_CHANGED event?}
    R -->|yes| S[Set/keep policy.target]
    R -->|no| I

    S --> T[Compare policy.target vs policy.current]
    T --> U{Different?}
    U -->|no| I
    U -->|yes| V[Apply profile if available]

    V --> W{Calibration gating<br/>cooldown and low score streak}
    W -->|run| X[Run calibrate.sh<br/>logs/results.env]
    X --> Y[Apply BEST values<br/>via resetprop]
    Y --> Z[Update state files<br/>policy.current + calibrate.*]
    Z --> AA[Write policy.event.json]
    AA --> I

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
    Z -.-> SF8
    AA -.-> SF9
    Z -.-> SF10
    Z -.-> SF11
    Z -.-> SF12
```
---

#### Daemon / Kitsunping Properties
### Debugging and Performance Tuning
- **kitsunping.daemon.interval**: Sets the interval for daemon checks in seconds (default: 10 seconds).
- **persist.kitsunping.debug**: Toggles debug mode for detailed logging (0: disable | 1: enable).
- **persist.kitsunping.ping_timeout**: Adjusts the ping timeout duration (default: 10 seconds).
- **persist.kitsunping.emit_events**: Configures the time for emitting network status events (default: 10 seconds).

### Kitsunping daemon functions calibration

- **kitsunping.daemon.algorithm=sigmoid** : Sets the algorithm used for network status evaluation to sigmoid.
- **kitsunping.daemon.sigmoid.alpha=0.5** : Alpha parameter for the sigmoid function.
- **kitsunping.daemon.sigmoid.beta=0.1** : Beta parameter for the sigmoid function.
- **kitsunping.daemon.sigmoid.gamma=0.1** : Gamma parameter for the sigmoid function.