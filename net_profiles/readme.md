# Network Profile Configuration Process by User Choice

This directory contains scripts to configure specific network profiles based on user needs. The available profiles are:

- **speed_profile.sh**: Optimizes network settings to maximize download and upload speed, prioritizing throughput over latency.
- **latency_profile.sh**: Adjusts network settings to minimize latency, ideal for real-time applications such as gaming and video calls.
- **balanced_profile.sh**: Provides a balance between speed and latency, suitable for most general uses.

Note that the speed and latency profiles increase system memory usage due to adjustments in TCP buffers, which may result in a slight decrease in battery life, but significantly improve network performance.

Each script adjusts various system parameters related to TCP, such as congestion control, memory buffers, and TCP window scaling. Users can select the profile that best suits their specific network needs.

The configurations are also compatible with Qualcomm-based Android devices, ensuring broad compatibility.

The logic for profile selection in the main script is yet to be implemented; for now, this remains an idea for future improvements.

You are welcome to submit a PR if you wish to contribute this functionality.
