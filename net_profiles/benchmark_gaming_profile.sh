#!/system/bin/sh
# benchmark_gaming_profile: unsafe ping-first profile for minimum queueing

LOG_OUT="${SERVICES_LOGS:-/dev/null}"
echo "[PROFILE] benchmark_gaming start" >> "$LOG_OUT"

apply_param_set <<'EOF'
1|/proc/sys/net/core/bpf_jit_enable|bpf_jit enabled
0|/proc/sys/net/core/bpf_jit_harden|bpf_jit_harden disabled (compat)
1|/proc/sys/net/core/bpf_jit_kallsyms|bpf_jit_kallsyms enabled
16777216|/proc/sys/net/core/bpf_jit_limit|bpf_jit_limit 16MiB
50|/proc/sys/net/core/busy_poll|busy_poll enabled aggressively for minimum latency
50|/proc/sys/net/core/busy_read|busy_read enabled aggressively for minimum latency
fq_codel|/proc/sys/net/core/default_qdisc|default qdisc fq_codel (hard latency bias)
64|/proc/sys/net/core/dev_weight|dev_weight minimized to keep queues short
128|/proc/sys/net/core/netdev_budget|netdev_budget ultra latency bias
300|/proc/sys/net/core/netdev_budget_usecs|netdev_budget_usecs ultra latency bias
256|/proc/sys/net/core/netdev_max_backlog|netdev_max_backlog minimized hard to cut queue growth
4194304|/proc/sys/net/core/wmem_max|wmem_max 4MiB
4194304|/proc/sys/net/core/rmem_max|rmem_max 4MiB
65536|/proc/sys/net/core/wmem_default|wmem_default 64KiB
65536|/proc/sys/net/core/rmem_default|rmem_default 64KiB
16384|/proc/sys/net/core/optmem_max|optmem_max 16KiB
256|/proc/sys/net/core/somaxconn|somaxconn minimized for latency bias
EOF

apply_param_set <<'EOF'
0|/proc/sys/net/ipv4/tcp_ecn|ECN disabled
1|/proc/sys/net/ipv4/tcp_sack|SACK enabled
1|/proc/sys/net/ipv4/tcp_fack|FACK enabled
1|/proc/sys/net/ipv4/tcp_window_scaling|Window scaling enabled
4096 16384 4194304|/proc/sys/net/ipv4/tcp_rmem|tcp_rmem max 4MiB
4096 16384 4194304|/proc/sys/net/ipv4/tcp_wmem|tcp_wmem max 4MiB
131072 262144 524288|/proc/sys/net/ipv4/tcp_mem|tcp_mem ultra latency cap
cubic|/proc/sys/net/ipv4/tcp_congestion_control|CUBIC for stable minimum RTT
1|/proc/sys/net/ipv4/tcp_no_metrics_save|no_metrics_save enabled
2|/proc/sys/net/ipv4/tcp_retries1|retries1 reduced hard
4|/proc/sys/net/ipv4/tcp_retries2|retries2 reduced aggressively
65536|/proc/sys/net/ipv4/tcp_limit_output_bytes|tcp_limit_output_bytes=64KiB to suppress queueing
1|/proc/sys/net/ipv4/tcp_low_latency|low_latency hint enabled
1|/proc/sys/net/ipv4/tcp_mtu_probing|mtu probing enabled
0|/proc/sys/net/ipv4/tcp_autocorking|autocorking disabled for faster flush
0|/proc/sys/net/ipv4/tcp_timestamps|timestamps disabled for minimum packet overhead
1|/proc/sys/net/ipv4/tcp_tw_reuse|tw_reuse enabled
EOF

echo "[PROFILE] benchmark_gaming done" >> "$LOG_OUT"