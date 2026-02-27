#!/system/bin/sh
# gaming_profile (safe): profile orientate to low latency for gaming
# This version applies conservative values to avoid overloading CPU/memory.
# It is recommended to measure before/after and adjust incrementally.
# exist a better profile to low lñatenc but with more risk of instability variables.
# Part of Kitsunping - addon/policy/net_profiles
# When sourced by executor/profile_runner, preserve caller-provided NEWMODPATH.
if [ -z "${NEWMODPATH:-}" ] || [ ! -d "${NEWMODPATH:-/}" ]; then
	_caller_dir="${0%/*}"
	case "$_caller_dir" in
		*/net_profiles) NEWMODPATH="${_caller_dir%/net_profiles}" ;;
		*) NEWMODPATH="${_caller_dir%/*}" ;;
	esac
fi

profile_aplicated="${NEWMODPATH}/logs/profile_aplicated.log"

# Executor defines MODDIR as module root; prefer it when available.
if [ -n "${MODDIR:-}" ] && [ -d "${MODDIR:-/}" ]; then
	profile_aplicated="${MODDIR}/logs/profile_aplicated.log"
fi

mkdir -p "$(dirname "$profile_aplicated")" 2>/dev/null || true

echo "[PROFILE] gaming (safe) start" >> "$profile_aplicated"

apply_param_set <<'EOF'
1|/proc/sys/net/core/bpf_jit_enable|bpf_jit_enable optimized for gaming
1|/proc/sys/net/core/bpf_jit_harden|bpf_jit_harden enabled (security)
1|/proc/sys/net/core/bpf_jit_kallsyms|bpf_jit_kallsyms enabled
16777216|/proc/sys/net/core/bpf_jit_limit|bpf_jit_limit=16MiB (conservative)
0|/proc/sys/net/core/busy_poll|busy_poll disabled for CPU/battery savings
50|/proc/sys/net/core/busy_read|busy_read enabled for lower latency
fq_codel|/proc/sys/net/core/default_qdisc|default_qdisc changed to fq_codel
100|/proc/sys/net/core/dev_weight|dev_weight optimized
2|/proc/sys/net/core/dev_weight_rx_bias|dev_weight_rx_bias moderately increased
2|/proc/sys/net/core/dev_weight_tx_bias|dev_weight_tx_bias moderately increased
255|/proc/sys/net/core/flow_limit_cpu_bitmap|flow_limit_cpu_bitmap optimized (decimal)
8192|/proc/sys/net/core/flow_limit_table_len|flow_limit_table_len
20|/proc/sys/net/core/max_skb_frags|max_skb_frags increased
20|/proc/sys/net/core/message_burst|message_burst moderately increased
10|/proc/sys/net/core/message_cost|message_cost adjusted
600|/proc/sys/net/core/netdev_budget|netdev_budget optimized
2000|/proc/sys/net/core/netdev_budget_usecs|netdev_budget_usecs (µs) moderate
1000|/proc/sys/net/core/netdev_max_backlog|netdev_max_backlog moderately increased
0|/proc/sys/net/core/netdev_tstamp_prequeue|netdev_tstamp_prequeue disabled for latency
12582912|/proc/sys/net/core/wmem_max|wmem_max=12MiB
12582912|/proc/sys/net/core/rmem_max|rmem_max=12MiB
262144|/proc/sys/net/core/rmem_default|rmem_default=256KB
262144|/proc/sys/net/core/wmem_default|wmem_default=256KB
131072|/proc/sys/net/core/optmem_max|optmem_max=128KB
16384|/proc/sys/net/core/rps_sock_flow_entries|rps_sock_flow_entries activated (conservative)
1024|/proc/sys/net/core/somaxconn|somaxconn increased
1|/proc/sys/net/core/tstamp_allow_data|tstamp_allow_data enabled
1800|/proc/sys/net/core/xfrm_acq_expires|xfrm_acq_expires conservative
30|/proc/sys/net/core/xfrm_aevent_etime|xfrm_aevent_etime conservative
32|/proc/sys/net/core/xfrm_aevent_rseqth|xfrm_aevent_rseqth conservative
1|/proc/sys/net/core/xfrm_larval_drop|xfrm_larval_drop enabled

EOF

echo "[PROFILE] gaming (safe) done" >> "$profile_aplicated"

# TCP / IP / UDP conservative tunings (safe, incremental)
apply_param_set <<'EOF'
1|/proc/sys/net/ipv4/tcp_ecn|tcp_ecn enabled (conservative)
1|/proc/sys/net/ipv4/tcp_sack|tcp_sack enabled
1|/proc/sys/net/ipv4/tcp_fack|tcp_fack enabled
1|/proc/sys/net/ipv4/tcp_window_scaling|tcp_window_scaling enabled
4096 87380 12582912|/proc/sys/net/ipv4/tcp_rmem|tcp_rmem (min,default,max=12MiB)
4096 87380 12582912|/proc/sys/net/ipv4/tcp_wmem|tcp_wmem (min,default,max=12MiB)
262144 524288 1048576|/proc/sys/net/ipv4/tcp_mem|tcp_mem conservative
1|/proc/sys/net/ipv4/tcp_no_metrics_save|tcp_no_metrics_save enabled
3|/proc/sys/net/ipv4/tcp_fastopen|tcp_fastopen enabled (if supported)
3|/proc/sys/net/ipv4/tcp_retries1|tcp_retries1 reduced
8|/proc/sys/net/ipv4/tcp_retries2|tcp_retries2 moderate
2097152|/proc/sys/net/ipv4/tcp_limit_output_bytes|tcp_limit_output_bytes=2MiB (conservative)
2|/proc/sys/net/ipv4/tcp_orphan_retries|tcp_orphan_retries conservative
2048|/proc/sys/net/ipv4/tcp_max_syn_backlog|tcp_max_syn_backlog increased
32768|/proc/sys/net/ipv4/tcp_max_orphans|tcp_max_orphans conservative
5|/proc/sys/net/ipv4/tcp_fin_timeout|tcp_fin_timeout reduced moderate
30|/proc/sys/net/ipv4/tcp_keepalive_time|tcp_keepalive_time moderate
5|/proc/sys/net/ipv4/tcp_keepalive_intvl|tcp_keepalive_intvl moderate
3|/proc/sys/net/ipv4/tcp_keepalive_probes|tcp_keepalive_probes
1|/proc/sys/net/ipv4/tcp_syncookies|tcp_syncookies enabled
1|/proc/sys/net/ipv4/tcp_timestamps|tcp_timestamps enabled
0|/proc/sys/net/ipv4/tcp_tw_recycle|tcp_tw_recycle disabled (for security)
1|/proc/sys/net/ipv4/tcp_low_latency|tcp_low_latency enabled (conservative)
1|/proc/sys/net/ipv4/tcp_mtu_probing|tcp_mtu_probing enabled
1|/proc/sys/net/ipv4/tcp_frto|tcp_frto enabled
2|/proc/sys/net/ipv4/tcp_frto_response|tcp_frto_response conservative
1|/proc/sys/net/ipv4/tcp_moderate_rcvbuf|tcp_moderate_rcvbuf enabled
1|/proc/sys/net/ipv4/tcp_early_retrans|tcp_early_retrans enabled
3|/proc/sys/net/ipv4/tcp_early_demux|tcp_early_demux enabled
1|/proc/sys/net/ipv4/conf/default/rp_filter|rp_filter strict
0|/proc/sys/net/ipv4/conf/default/accept_redirects|accept_redirects disabled
0|/proc/sys/net/ipv4/conf/default/accept_source_route|accept_source_route disabled
1|/proc/sys/net/ipv4/fwmark_reflect|fwmark_reflect enabled
0|/proc/sys/net/ipv4/icmp_echo_ignore_all|icmp_echo_ignore_all disabled
1|/proc/sys/net/ipv4/icmp_echo_ignore_broadcasts|icmp_echo_ignore_broadcasts enabled
200|/proc/sys/net/ipv4/icmp_msgs_burst|icmp_msgs_burst conservative
500|/proc/sys/net/ipv4/icmp_msgs_per_sec|icmp_msgs_per_sec conservative
100|/proc/sys/net/ipv4/icmp_ratelimit|icmp_ratelimit conservative
1|/proc/sys/net/ipv4/udp_early_demux|udp_early_demux enabled
262144 524288 1048576|/proc/sys/net/ipv4/udp_mem|udp_mem conservative
4096|/proc/sys/net/ipv4/udp_rmem_min|udp_rmem_min conservative
4096|/proc/sys/net/ipv4/udp_wmem_min|udp_wmem_min conservative
1024 65000|/proc/sys/net/ipv4/ip_local_port_range|ip_local_port_range wide
0 2147483647|/proc/sys/net/ipv4/ping_group_range|ping_group_range optimized
EOF

# Conditional: enable BBR only if kernel supports it
if [ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]; then
	if grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
		echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || true
		echo "[PROFILE] gaming: tcp_congestion_control set to bbr" >> "$profile_aplicated"
	else
		echo "[PROFILE] gaming: bbr not available; leaving congestion_control as-is" >> "$profile_aplicated"
	fi
fi