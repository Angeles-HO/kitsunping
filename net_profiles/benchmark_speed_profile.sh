#!/system/bin/sh
# benchmark_speed_profile: unsafe throughput-first profile even if ping rises

LOG_OUT="${SERVICES_LOGS:-/dev/null}"
echo "[PROFILE] benchmark_speed start" >> "$LOG_OUT"

apply_param_set <<'EOF'
1|/proc/sys/net/core/bpf_jit_enable|bpf_jit enabled
0|/proc/sys/net/core/bpf_jit_harden|bpf_jit_harden disabled (compat)
1|/proc/sys/net/core/bpf_jit_kallsyms|bpf_jit_kallsyms enabled
67108864|/proc/sys/net/core/bpf_jit_limit|bpf_jit_limit 64MiB
0|/proc/sys/net/core/busy_poll|busy_poll disabled
0|/proc/sys/net/core/busy_read|busy_read disabled to favor bulk transfers
fq|/proc/sys/net/core/default_qdisc|default qdisc fq (throughput-first)
384|/proc/sys/net/core/dev_weight|dev_weight increased for burst handling
640|/proc/sys/net/core/netdev_budget|netdev_budget increased for throughput
2200|/proc/sys/net/core/netdev_budget_usecs|netdev_budget_usecs increased for throughput
8192|/proc/sys/net/core/netdev_max_backlog|netdev_max_backlog maximized for burst absorption
33554432|/proc/sys/net/core/wmem_max|wmem_max 32MiB
33554432|/proc/sys/net/core/rmem_max|rmem_max 32MiB
1048576|/proc/sys/net/core/wmem_default|wmem_default 1MiB
1048576|/proc/sys/net/core/rmem_default|rmem_default 1MiB
524288|/proc/sys/net/core/optmem_max|optmem_max 512KiB
4096|/proc/sys/net/core/somaxconn|somaxconn high throughput bias
EOF

apply_param_set <<'EOF'
0|/proc/sys/net/ipv4/tcp_ecn|ECN disabled
1|/proc/sys/net/ipv4/tcp_sack|SACK enabled
1|/proc/sys/net/ipv4/tcp_fack|FACK enabled
1|/proc/sys/net/ipv4/tcp_window_scaling|Window scaling enabled
4096 262144 33554432|/proc/sys/net/ipv4/tcp_rmem|tcp_rmem max 32MiB
4096 262144 33554432|/proc/sys/net/ipv4/tcp_wmem|tcp_wmem max 32MiB
1048576 2097152 4194304|/proc/sys/net/ipv4/tcp_mem|tcp_mem maximized for throughput
1|/proc/sys/net/ipv4/tcp_no_metrics_save|no_metrics_save enabled
3|/proc/sys/net/ipv4/tcp_fastopen|fastopen enabled
4|/proc/sys/net/ipv4/tcp_retries1|retries1 balanced for throughput
8|/proc/sys/net/ipv4/tcp_retries2|retries2 balanced for throughput
4194304|/proc/sys/net/ipv4/tcp_limit_output_bytes|tcp_limit_output_bytes=4MiB for deeper flight queues
1|/proc/sys/net/ipv4/tcp_moderate_rcvbuf|moderate_rcvbuf enabled
0|/proc/sys/net/ipv4/tcp_slow_start_after_idle|slow_start_after_idle disabled
1|/proc/sys/net/ipv4/tcp_autocorking|autocorking enabled
0|/proc/sys/net/ipv4/tcp_mtu_probing|mtu probing disabled to reduce overhead
1|/proc/sys/net/ipv4/tcp_timestamps|timestamps enabled
1|/proc/sys/net/ipv4/tcp_tw_reuse|tw_reuse enabled
EOF

if [ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]; then
	if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
		echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || true
		echo "[PROFILE] benchmark_speed: tcp_congestion_control set to bbr" >> "$LOG_OUT"
	else
		echo "cubic" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || true
		echo "[PROFILE] benchmark_speed: bbr not available; keeping cubic" >> "$LOG_OUT"
	fi
fi

echo "[PROFILE] benchmark_speed done" >> "$LOG_OUT"