#!/system/bin/sh
# GamingProfile: Calculations to optimize latency and connection stability
# Can prioritize latency over download/upload speed




# Settings for GAMING profile
# echo 50 > /proc/sys/net/core/busy_poll # In gaming, you don't want 0. You want the CPU to actively "poll" for packets.
# echo 128 > /proc/sys/net/core/dev_weight # Allows processing more packets per CPU interrupt.
# echo 1 > /proc/sys/net/ipv4/tcp_low_latency # Prioritizes immediate delivery over bandwidth.
# echo 3 > /proc/sys/net/ipv4/tcp_fastopen # Reduces initial handshake.
# echo 5 > /proc/sys/net/ipv4/tcp_fin_timeout # Frees dead connections quickly to avoid saturation.
# echo 2000 > /proc/sys/net/core/netdev_max_backlog # Prevents packet drops during data spikes.
# 
# 
# apply_param_set <<'EOF'
# 50|/proc/sys/net/core/busy_poll|Latency reduction in sockets
# 50|/proc/sys/net/core/busy_read|Improved read response time
# 128|/proc/sys/net/core/dev_weight|Priority to packet processing
# 1|/proc/sys/net/ipv4/tcp_low_latency|Priority to latency over throughput
# 0|/proc/sys/net/ipv4/tcp_sack|Disabling SACK may help with pure latency
# 1|/proc/sys/net/ipv4/tcp_fastopen|Faster connection startup
# 5|/proc/sys/net/ipv4/tcp_fin_timeout|Quick closing of dead connections
# 1024|/proc/sys/net/core/netdev_max_backlog|Optimized input queue
# EOF