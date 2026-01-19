#!/system/bin/sh

# Standard configuration for STABLE profile
# Prioritizes stability and low latency, without experimental settings

# TCP ECN: For stability on old networks, better disabled
# echo 0 > /proc/sys/net/ipv4/tcp_ecn # 0 is disabled
# 
# # Less aggressive keepalive
# echo 60 > /proc/sys/net/ipv4/tcp_keepalive_time
# 
# # Sufficient backlog for daily use
# echo 512 > /proc/sys/net/core/netdev_max_backlog
# 
# # Congestion control: keep cubic as default
# echo cubic > /proc/sys/net/ipv4/tcp_congestion_control
# 
# # Early demux: keep enabled
# echo 1 > /proc/sys/net/ipv4/ip_early_demux
# echo 1 > /proc/sys/net/ipv4/udp_early_demux
# 
# # RP Filter: leave at 1 (strict), but if you have connectivity issues, change to 2
# echo 1 > /proc/sys/net/ipv4/conf/default/rp_filter # Change to 2 if you lose mobile data
# 
# 
# 
# apply_param_set <<'EOF'
# cubic|/proc/sys/net/ipv4/tcp_congestion_control|Cubic is the most stable standard
# 0|/proc/sys/net/core/busy_poll|Power saving (CPU idle)
# 64|/proc/sys/net/core/dev_weight|Standard Linux balance
# 4096 87380 16777216|/proc/sys/net/ipv4/tcp_rmem|Balanced buffer (16MB)
# 4096 65536 16777216|/proc/sys/net/ipv4/tcp_wmem|Balanced buffer (16MB)
# 1|/proc/sys/net/ipv4/tcp_sack|SACK enabled for stability on mobile networks
# EOF