#!/system/bin/sh
# speed_profile: profile orientated to throughput/balanced usage

LOG_OUT="${SERVICES_LOGS:-/dev/null}"
echo "[PROFILE] speed start" >> "$LOG_OUT"

# Setting core: maximize throughput with balanced latency
apply_param_set <<'EOF'
1|/proc/sys/net/core/bpf_jit_enable|bpf_jit basic
0|/proc/sys/net/core/bpf_jit_harden|bpf_jit_harden disabled (compatibility)
1|/proc/sys/net/core/bpf_jit_kallsyms|bpf_jit_kallsyms
33554432|/proc/sys/net/core/bpf_jit_limit|bpf_jit_limit 32MiB
0|/proc/sys/net/core/busy_poll|busy_poll disabled (stable)
0|/proc/sys/net/core/busy_read|busy_read disabled
fq|/proc/sys/net/core/default_qdisc|default qdisc: fq (balanced)
256|/proc/sys/net/core/dev_weight|dev_weight
4096|/proc/sys/net/core/netdev_max_backlog|netdev_max_backlog
16777216|/proc/sys/net/core/wmem_max|wmem_max (16MiB)
16777216|/proc/sys/net/core/rmem_max|rmem_max (16MiB)
262144|/proc/sys/net/core/wmem_default|wmem_default (256KiB)
262144|/proc/sys/net/core/rmem_default|rmem_default (256KiB)
262144|/proc/sys/net/core/optmem_max|optmem_max
4096|/proc/sys/net/core/somaxconn|somaxconn
1|/proc/sys/net/core/tstamp_allow_data|tstamp_allow_data
EOF

# TCP: prioritize throughput with stability
apply_param_set <<'EOF'
0|/proc/sys/net/ipv4/tcp_ecn|ECN disabled for stability
1|/proc/sys/net/ipv4/tcp_sack|SACK enabled
1|/proc/sys/net/ipv4/tcp_fack|FACK enabled
1|/proc/sys/net/ipv4/tcp_window_scaling|Window scaling enabled
4096 87380 16777216|/proc/sys/net/ipv4/tcp_rmem|tcp_rmem (max 16MiB)
4096 65536 16777216|/proc/sys/net/ipv4/tcp_wmem|tcp_wmem (max 16MiB)
8388608 16777216 33554432|/proc/sys/net/ipv4/tcp_mem|tcp_mem (moderate)
cubic|/proc/sys/net/ipv4/tcp_congestion_control|use CUBIC by default
1|/proc/sys/net/ipv4/tcp_moderate_rcvbuf|moderate rcvbuf enabled
0|/proc/sys/net/ipv4/tcp_slow_start_after_idle|disabled
1|/proc/sys/net/ipv4/tcp_autocorking|autocorking enabled
0|/proc/sys/net/ipv4/tcp_mtu_probing|disabled (avoid overhead)
1|/proc/sys/net/ipv4/tcp_timestamps|timestamps enabled
1|/proc/sys/net/ipv4/tcp_tw_reuse|tw_reuse enabled
EOF

# IPv4: conservative parameters for throughput without compromising security
apply_param_set <<'EOF'
1|/proc/sys/net/ipv4/conf/default/rp_filter|rp_filter by default
1024 65535|/proc/sys/net/ipv4/ip_local_port_range|local ports
16777216|/proc/sys/net/ipv4/ipfrag_high_thresh|ipfrag_high_thresh 16MiB
12582912|/proc/sys/net/ipv4/ipfrag_low_thresh|ipfrag_low_thresh 12MiB
4096|/proc/sys/net/ipv4/udp_rmem_min|udp_rmem_min
4096|/proc/sys/net/ipv4/udp_wmem_min|udp_wmem_min
4096 87380 16777216|/proc/sys/net/ipv4/udp_mem|udp_mem (moderate)
EOF

# IPv6: conservative values and moderate increases if applicable
apply_param_set <<'EOF'
1|/proc/sys/net/ipv6/ip6frag_high_thresh|ip6frag_high_thresh 16MiB
12582912|/proc/sys/net/ipv6/ip6frag_low_thresh|ip6frag_low_thresh 12MiB
EOF

# adjust VM/FS for throughput (conservative values)
apply_param_set <<'EOF'
20|/proc/sys/vm/dirty_background_ratio|dirty_background_ratio
40|/proc/sys/vm/dirty_ratio|dirty_ratio
20000|/proc/sys/vm/dirty_expire_centisecs|dirty_expire_centisecs
5000|/proc/sys/vm/dirty_writeback_centisecs|dirty_writeback_centisecs
60|/proc/sys/vm/swappiness|swappiness (prefer RAM, moderate)
0|/proc/sys/vm/zone_reclaim_mode|zone_reclaim_mode disabled
EOF

# Specific optimization for wireless interfaces (if any)
echo "[PROFILE] applying WiFi optimizations (if applicable)" >> "$LOG_OUT"
for wifi_dir in /sys/class/net/*/wireless; do
	if [ -d "$wifi_dir" ]; then
		interface=$(dirname "$(dirname "$wifi_dir")")
		interface=$(basename "$interface")
		# increase tx_queue_len moderately
		if [ -e "/sys/class/net/$interface/tx_queue_len" ]; then
			echo "1000" > "/sys/class/net/$interface/tx_queue_len" 2>/dev/null || true
		fi
	fi
done

echo "[PROFILE] speed done" >> "$LOG_OUT"