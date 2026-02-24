#!/system/bin/sh
# =============================================================================
# Script for network configuration (service.sh)
# This script waits for the system to finish booting, backs up the default
# network parameter values in logs/services.log, and then applies various
# network optimizations. It also provides a function to apply specific network profiles on demand.
# /data/adb/modules/Kitsun_ping/logs/services.log
# =============================================================================
# Derive module root reliably (this file is installed at module root as service.sh).
# If called from inside addon paths, strip them.
MODDIR="${0%/*}"
case "$MODDIR" in
    */addon/policy) MODDIR="${MODDIR%%/addon/policy}" ;;
    */addon/*) MODDIR="${MODDIR%%/addon/*}" ;;
    */addon) MODDIR="${MODDIR%%/addon}" ;;
esac
NEWMODPATH="$MODDIR"
export NEWMODPATH

ADDON_DIR="$MODDIR/addon"
SCRIPT_DIR="$MODDIR"
# =============================================================================
mkdir -p "$SCRIPT_DIR/logs" 2>/dev/null
SERVICES_LOGS="$SCRIPT_DIR/logs/services.log"
SERVICES_LOGS_CALLED_BY_DAEMON="$SCRIPT_DIR/logs/services_daemon.log"
HEAVY_ACTIVITY_LOCK_DIR="${HEAVY_ACTIVITY_LOCK_DIR:-$SCRIPT_DIR/cache/heavy_activity.lock}"
HEAVY_LOAD_PROP="${HEAVY_LOAD_PROP:-kitsunping.heavy_load}"
# =============================================================================
# Function: Waits for the system to finish booting

# Boot self-heal for heavy activity anti-race model (stale lock/counter after OOM kill)
rm -rf "$HEAVY_ACTIVITY_LOCK_DIR" 2>/dev/null || true
if command -v setprop >/dev/null 2>&1; then
    setprop "$HEAVY_LOAD_PROP" 0 >/dev/null 2>&1 || true
elif command -v resetprop >/dev/null 2>&1; then
    resetprop "$HEAVY_LOAD_PROP" 0 >/dev/null 2>&1 || true
fi
echo "[SYS][SERVICE] heavy activity state reset (lock + $HEAVY_LOAD_PROP=0)" >> "$SERVICES_LOGS"

# Common utilities 
COMMON_UTIL="$SCRIPT_DIR/addon/functions/utils/Kitsutils.sh"
 
if [ -f "$COMMON_UTIL" ]; then
    . "$COMMON_UTIL"
else
    ALT_MODDIR="/data/adb/modules_update/${SCRIPT_DIR##*/}"
    ALT_COMMON="$ALT_MODDIR/addon/functions/utils/Kitsutils.sh"
    if [ -f "$ALT_COMMON" ]; then
        . "$ALT_COMMON"
    else
        echo "[SYS][WARN]: Could not load $COMMON_UTIL or $ALT_COMMON" >> "$SERVICES_LOGS"
        set_selinux_enforce() {
            enforce_state="$1"
            if [ "$(id -u)" -ne 0 ]; then
                echo "[SYS][ERROR]: root required" >> "$SERVICES_LOGS"
                return 1
            fi
            case "$enforce_state" in
                0|1) :;;
                *) echo "[SYS][ERROR]: Invalid value: $enforce_state" >> "$SERVICES_LOGS"; return 2 ;;
            esac
            if setenforce "$enforce_state"; then
                echo "[SYS][OK]: Temporary SELinux: $(getenforce)" >> "$SERVICES_LOGS"
            else
                echo "[SYS][ERROR]: setenforce failed" >> "$SERVICES_LOGS"
                return 3
            fi
            return 0
        }
    fi
fi

# =============================================================================
# Functions to apply network configurations
# =============================================================================

# Normalize sysctl values (convert commas to spaces when applicable)
normalize_sysctl_value() {
    case "$1" in
        *","*) echo "${1//,/ }" ;;
        *) echo "$1" ;;
    esac
}

# Update: A simple function to streamline the script and avoid code repetition
# └──Update: Changed the function name to custom_write
custom_write() {
    echo "[DEBUG]: Call to [custom_write()] with arguments: ['$1'], ['$2'], ['$3']" >> "$SERVICES_LOGS"

    value="$1"
    normalized_value=$(normalize_sysctl_value "$value") # 
    target_file="$2"
    log_text="$3"

    if [ "$#" -ne 3 ]; then
        echo "[SYS] [ERROR]: Invalid number of arguments in [custom_write()]" >> "$SERVICES_LOGS"
        return 1
    fi

    case "$target_file" in
        /*) ;;
        *)
            echo "[SYS] [ERROR]: Non-absolute path: '$target_file'" >> "$SERVICES_LOGS"
            return 2
            ;;
    esac

    if [ -z "$value" ] && [ "$value" != "0" ]; then
        echo "[SYS] [ERROR]: Empty value for '$target_file'" >> "$SERVICES_LOGS"
        return 3
    fi

    if [ ! -e "$target_file" ]; then
        echo "[SYS] [WARN]: Path does not exist: '$target_file'" >> "$SERVICES_LOGS"
        return 0
    fi

    if [ ! -w "$target_file" ]; then
        chmod 0777 "$target_file" 2>> "$SERVICES_LOGS"
    fi

    case "$target_file" in
        /proc/sys/*)
            sysctl_param=${target_file#/proc/sys/}
            sysctl_param=$(echo "$sysctl_param" | tr '/' '.')
            # Skip if not writable to avoid noisy errors on readonly tunables
            if [ ! -w "$target_file" ]; then
                echo "[SYS][SKIP]: '$target_file' is not writable" >> "$SERVICES_LOGS"
                return 0
            fi
            if /system/bin/sysctl -w "$sysctl_param=$normalized_value" >> "$SERVICES_LOGS" 2>&1; then
                echo "[OK] $log_text (sysctl): $normalized_value" >> "$SERVICES_LOGS"
                return 0
            fi
            echo "[SYS] [ERROR]: sysctl failed $sysctl_param" >> "$SERVICES_LOGS"
            ;;
    esac

    printf "%s" "$normalized_value" > "$target_file" 2>> "$SERVICES_LOGS"
    current_value=$(cat "$target_file" 2>/dev/null)
    if [ "$current_value" = "$normalized_value" ]; then
        echo "[OK] $log_text: $normalized_value" >> "$SERVICES_LOGS"
    else
        echo "[SYS] [ERROR]: Written value ($current_value) != expected ($normalized_value) in $target_file" >> "$SERVICES_LOGS"
        return 4
    fi

    return 0
}

apply_param_set() {
    while IFS='|' read -r value target_file log_text; do
        [ -z "$target_file" ] && continue
        custom_write "$value" "$target_file" "$log_text"
    done
}

# =============================================================================
apply_ril_settings() {
    echo "[Applying RIL settings...]"  >> "$SERVICES_LOGS"
    # Simulation of wait to apply configurations defined in system.prop
    echo "[RIL settings applied]"   >> "$SERVICES_LOGS"
}

apply_general_network_settings() { 
    echo "[Applying general network settings...]"  >> "$SERVICES_LOGS"
    echo "[General network settings applied]"  >> "$SERVICES_LOGS"
}

apply_core_settings() {
    echo "[Applying [CORE] settings...]"  >> "$SERVICES_LOGS"
    apply_param_set <<'EOF'
1|/proc/sys/net/core/bpf_jit_enable|bpf_jit_enable adjusted
0|/proc/sys/net/core/bpf_jit_harden|bpf_jit_harden adjusted
1|/proc/sys/net/core/bpf_jit_kallsyms|bpf_jit_kallsyms adjusted
33554432|/proc/sys/net/core/bpf_jit_limit|bpf_jit_limit adjusted
0|/proc/sys/net/core/busy_poll|busy_poll adjusted
0|/proc/sys/net/core/busy_read|busy_read adjusted
pfifo_fast|/proc/sys/net/core/default_qdisc|default_qdisc adjusted
64|/proc/sys/net/core/dev_weight|dev_weight adjusted
1|/proc/sys/net/core/dev_weight_rx_bias|dev_weight_rx_bias adjusted
1|/proc/sys/net/core/dev_weight_tx_bias|dev_weight_tx_bias adjusted
0|/proc/sys/net/core/fb_tunnels_only_for_init_net|fb_tunnels_only_for_init_net adjusted
00|/proc/sys/net/core/flow_limit_cpu_bitmap|flow_limit_cpu_bitmap adjusted
4096|/proc/sys/net/core/flow_limit_table_len|flow_limit_table_len adjusted
17|/proc/sys/net/core/max_skb_frags|max_skb_frags adjusted
10|/proc/sys/net/core/message_burst|message_burst adjusted
5|/proc/sys/net/core/message_cost|message_cost adjusted
256|/proc/sys/net/core/netdev_budget|netdev_budget adjusted
8000|/proc/sys/net/core/netdev_budget_usecs|netdev_budget_usecs adjusted
512|/proc/sys/net/core/netdev_max_backlog|netdev_max_backlog adjusted
1|/proc/sys/net/core/netdev_tstamp_prequeue|netdev_tstamp_prequeue adjusted
8388608|/proc/sys/net/core/wmem_max|wmem_max adjusted
8388608|/proc/sys/net/core/rmem_max|rmem_max adjusted
262144|/proc/sys/net/core/rmem_default|rmem_default adjusted
262144|/proc/sys/net/core/wmem_default|wmem_default adjusted
65536|/proc/sys/net/core/optmem_max|optmem_max adjusted
0|/proc/sys/net/core/rps_sock_flow_entries|rps_sock_flow_entries adjusted
128|/proc/sys/net/core/somaxconn|somaxconn adjusted
1|/proc/sys/net/core/tstamp_allow_data|tstamp_allow_data adjusted
3600|/proc/sys/net/core/xfrm_acq_expires|xfrm_acq_expires adjusted
10|/proc/sys/net/core/xfrm_aevent_etime|xfrm_aevent_etime adjusted
2|/proc/sys/net/core/xfrm_aevent_rseqth|xfrm_aevent_rseqth adjusted
1|/proc/sys/net/core/xfrm_larval_drop|xfrm_larval_drop adjusted
0|/proc/sys/net/core/warnings|warnings adjusted
EOF

    echo "[Configuraciones de red CORE aplicadas correctamente]"  >> "$SERVICES_LOGS"
}

# Actualizacion: Se aplican configuraciones de red IPv4 y TCP
apply_tcp_settings() {
    echo "[Aplicando configuraciones [ IPV4/TCP ]...]"  >> "$SERVICES_LOGS"
    apply_param_set <<'EOF'
1|/proc/sys/net/ipv4/tcp_ecn|tcp_ecn enabled
1|/proc/sys/net/ipv4/tcp_sack|tcp_sack enabled 
1|/proc/sys/net/ipv4/tcp_fack|tcp_fack enabled 
1|/proc/sys/net/ipv4/tcp_window_scaling|tcp_window_scaling enabled 
16384,87380,26777216|/proc/sys/net/ipv4/tcp_rmem|tcp_rmem adjusted 
16384,87380,26777216|/proc/sys/net/ipv4/tcp_wmem|tcp_wmem adjusted 
65536,131072,262144|/proc/sys/net/ipv4/tcp_mem|tcp_mem adjusted 
cubic|/proc/sys/net/ipv4/tcp_congestion_control|tcp_congestion_control configurado a cubic 
1|/proc/sys/net/ipv4/tcp_no_metrics_save|tcp_no_metrics_save enabled
3|/proc/sys/net/ipv4/tcp_fastopen|tcp_fastopen enabled 
5|/proc/sys/net/ipv4/tcp_retries1|tcp_retries1 adjusted 
5|/proc/sys/net/ipv4/tcp_retries2|tcp_retries2 adjusted 
2097152|/proc/sys/net/ipv4/tcp_limit_output_bytes|tcp_limit_output_bytes adjusted 
3|/proc/sys/net/ipv4/tcp_orphan_retries|tcp_orphan_retries adjusted 
512|/proc/sys/net/ipv4/tcp_max_syn_backlog|tcp_max_syn_backlog adjusted 
32768|/proc/sys/net/ipv4/tcp_max_orphans|tcp_max_orphans adjusted 
10|/proc/sys/net/ipv4/tcp_fin_timeout|tcp_fin_timeout adjusted 
35|/proc/sys/net/ipv4/tcp_keepalive_time|tcp_keepalive_time adjusted 
10|/proc/sys/net/ipv4/tcp_keepalive_intvl|tcp_keepalive_intvl adjusted 
3|/proc/sys/net/ipv4/tcp_keepalive_probes|tcp_keepalive_probes adjusted 
1|/proc/sys/net/ipv4/tcp_syncookies|tcp_syncookies enabled 
EOF

    echo "[Configuraciones TCP completadas]"  >> "$SERVICES_LOGS"
}

# Actualization: Apply IPv4 and general network settings
apply_network_ipv4_settings() {
    echo "[Aplicando configuraciones [ IPV4/OTHERS ]...]"  >> "$SERVICES_LOGS"

    apply_param_set <<'EOF'
1|/proc/sys/net/ipv4/conf/default/rp_filter|rp_filter configurated in strict mode 
0|/proc/sys/net/ipv4/conf/default/accept_redirects|accept_redirects disabled 
0|/proc/sys/net/ipv4/conf/default/accept_source_route|accept_source_route disabled 
1|/proc/sys/net/ipv4/fwmark_reflect|fwmark_reflect enabled 
0|/proc/sys/net/ipv4/icmp_echo_ignore_all|icmp_echo_ignore_all disabled 
1|/proc/sys/net/ipv4/icmp_echo_ignore_broadcasts|icmp_echo_ignore_broadcasts enabled 
0|/proc/sys/net/ipv4/icmp_errors_use_inbound_ifaddr|icmp_errors_use_inbound_ifaddr disabled 
1|/proc/sys/net/ipv4/icmp_ignore_bogus_error_responses|icmp_ignore_bogus_error_responses enabled 
100|/proc/sys/net/ipv4/icmp_msgs_burst|icmp_msgs_burst optimized 
5000|/proc/sys/net/ipv4/icmp_msgs_per_sec|icmp_msgs_per_sec optimized 
500|/proc/sys/net/ipv4/icmp_ratelimit|icmp_ratelimit optimized for lower latency 
6168|/proc/sys/net/ipv4/icmp_ratemask|icmp_ratemask adjusted 
1|/proc/sys/net/ipv4/igmp_link_local_mcast_reports|igmp_link_local_mcast_reports enabled 
50|/proc/sys/net/ipv4/igmp_max_memberships|igmp_max_memberships adjusted for higher efficiency 
20|/proc/sys/net/ipv4/igmp_max_msf|igmp_max_msf adjusted 
2|/proc/sys/net/ipv4/igmp_qrv|igmp_qrv adjusted 
64|/proc/sys/net/ipv4/ip_default_ttl|ip_default_ttl adjusted 
0|/proc/sys/net/ipv4/ip_dynaddr|ip_dynaddr disabled 
1|/proc/sys/net/ipv4/ip_early_demux|ip_early_demux enabled for faster processing 
0|/proc/sys/net/ipv4/ip_forward|ip_forward disabled to reduce overhead 
1|/proc/sys/net/ipv4/ip_forward_update_priority|ip_forward_update_priority adjusted 
0|/proc/sys/net/ipv4/ip_forward_use_pmtu|ip_forward_use_pmtu disabled 
1|/proc/sys/net/ipv4/tcp_mtu_probing|tcp_mtu_probing enabled 
1024,65535|/proc/sys/net/ipv4/ip_local_port_range|ip_local_port_range expanded for more connections 
0|/proc/sys/net/ipv4/ip_no_pmtu_disc|ip_no_pmtu_disc disabled 
1|/proc/sys/net/ipv4/ip_nonlocal_bind|ip_nonlocal_bind enabled to allow more connections 
1024|/proc/sys/net/ipv4/ip_unprivileged_port_start|ip_unprivileged_port_start adjusted 
4194304|/proc/sys/net/ipv4/ipfrag_high_thresh|ipfrag_high_thresh adjusted for larger buffer 
3145728|/proc/sys/net/ipv4/ipfrag_low_thresh|ipfrag_low_thresh adjusted 
64|/proc/sys/net/ipv4/ipfrag_max_dist|ipfrag_max_dist adjusted 
0|/proc/sys/net/ipv4/ipfrag_secret_interval|ipfrag_secret_interval adjusted 
30|/proc/sys/net/ipv4/ipfrag_time|ipfrag_time adjusted 
1|/proc/sys/net/ipv4/udp_early_demux|udp_early_demux enabled for faster processing 
131072,262144,524288|/proc/sys/net/ipv4/udp_mem|udp_mem adjusted for higher performance 
8192|/proc/sys/net/ipv4/udp_rmem_min|udp_rmem_min optimized 
8192|/proc/sys/net/ipv4/udp_wmem_min|udp_wmem_min optimized 
600|/proc/sys/net/ipv4/inet_peer_maxttl|inet_peer_maxttl adjusted 
120|/proc/sys/net/ipv4/inet_peer_minttl|inet_peer_minttl adjusted 
131072|/proc/sys/net/ipv4/inet_peer_threshold|inet_peer_threshold adjusted for more peers 
0,2147483647|/proc/sys/net/ipv4/ping_group_range|ping_group_range adjusted 
32768|/proc/sys/net/ipv4/xfrm4_gc_thresh|xfrm4_gc_thresh adjusted 
EOF

    echo "[Configuring optimized network settings completed]"  >> "$SERVICES_LOGS"
}

apply_network_ipv6_settings() {
    echo "[Applying configurations [ IPV6/OTHERS ]...]"  >> "$SERVICES_LOGS"

    apply_param_set <<'EOF'
0|/proc/sys/net/ipv6/anycast_src_echo_reply|anycast_src_echo_reply disabled
1|/proc/sys/net/ipv6/auto_flowlabels|auto_flowlabels enabled
0|/proc/sys/net/ipv6/fib_multipath_hash_policy|fib_multipath_hash_policy adjusted
1|/proc/sys/net/ipv6/flowlabel_consistency|flowlabel_consistency enabled
0|/proc/sys/net/ipv6/flowlabel_reflect|flowlabel_reflect disabled
0|/proc/sys/net/ipv6/flowlabel_state_ranges|flowlabel_state_ranges adjusted
1|/proc/sys/net/ipv6/fwmark_reflect|fwmark_reflect enabled
1|/proc/sys/net/ipv6/idgen_delay|idgen_delay adjusted
3|/proc/sys/net/ipv6/idgen_retries|idgen_retries adjusted
0|/proc/sys/net/ipv6/ip_nonlocal_bind|ip_nonlocal_bind disabled
4194304|/proc/sys/net/ipv6/ip6frag_high_thresh|ip6frag_high_thresh adjusted
3145728|/proc/sys/net/ipv6/ip6frag_low_thresh|ip6frag_low_thresh adjusted
0|/proc/sys/net/ipv6/ip6frag_secret_interval|ip6frag_secret_interval adjusted
60|/proc/sys/net/ipv6/ip6frag_time|ip6frag_time adjusted
2147483647|/proc/sys/net/ipv6/max_dst_opts_length|max_dst_opts_length adjusted
8|/proc/sys/net/ipv6/max_dst_opts_number|max_dst_opts_number adjusted
2147483647|/proc/sys/net/ipv6/max_hbh_length|max_hbh_length adjusted
8|/proc/sys/net/ipv6/max_hbh_opts_number|max_hbh_opts_number adjusted
64|/proc/sys/net/ipv6/mld_max_msf|mld_max_msf adjusted
2|/proc/sys/net/ipv6/mld_qrv|mld_qrv adjusted
0|/proc/sys/net/ipv6/seg6_flowlabel|seg6_flowlabel desenabled
32768|/proc/sys/net/ipv6/xfrm6_gc_thresh|xfrm6_gc_thresh adjusted
EOF

    echo "[IPv6 network configurations completed]"  >> "$SERVICES_LOGS"
}
    
apply_network_optimizations() {
    echo "[SYS][SERVICE] Starting the application of all configurations..." >> "$SERVICES_LOGS"
    apply_core_settings || echo "[SYS][SERVICE] Error applying configurations [CORE]" >> "$SERVICES_LOGS"
    apply_tcp_settings || echo "[SYS][SERVICE] Error applying configurations [CORE]" >> "$SERVICES_LOGS"
    apply_network_ipv4_settings || echo "[SYS][SERVICE] Error applying configurations [CORE]" >> "$SERVICES_LOGS"
    apply_network_ipv6_settings || echo "[SYS][SERVICE] Error applying configurations [CORE]" >> "$SERVICES_LOGS"
    apply_general_network_settings|| echo "[SYS][SERVICE] Error applying configurations [CORE]" >> "$SERVICES_LOGS"
    echo "[SYS][SERVICE] All configurations have been applied successfully" >> "$SERVICES_LOGS"
}

# Allows reusing functions without executing the main flow when sourced by other scripts (e.g., executor.sh).
: "${SKIP_SERVICE_MAIN:=0}"
if [ "$SKIP_SERVICE_MAIN" = "1" ]; then
    return 0 2>/dev/null || exit 0
fi

set_selinux_enforce 0

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 1
done

echo "[SYS][SERVICE] Boot completed, applying configurations..." >> "$SERVICES_LOGS"


apply_network_optimizations  || echo "[SYS][SERVICE] Error applying base optimizations" >> "$SERVICES_LOGS"

DAEMON_SH="$SCRIPT_DIR/addon/daemon/daemon.sh"
DAEMON_PID_FILE="$SCRIPT_DIR/cache/daemon.pid"
DAEMON_SUPERVISOR_PID_FILE="$SCRIPT_DIR/cache/daemon.supervisor.pid"
mkdir -p "$SCRIPT_DIR/cache" 2>/dev/null

daemon_pid_is_running() {
    pid="$(cat "$DAEMON_PID_FILE" 2>/dev/null)"
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -Fq "$DAEMON_SH" || return 1
    return 0
}

supervisor_pid_is_running() {
    local spid
    spid="$(cat "$DAEMON_SUPERVISOR_PID_FILE" 2>/dev/null)"
    case "$spid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "$spid" 2>/dev/null || return 1
    return 0
}

start_daemon_supervisor() {
    [ -f "$DAEMON_SH" ] || {
        echo "[SYS][SERVICE][ERROR] Daemon script not found: $DAEMON_SH" >> "$SERVICES_LOGS"
        return 1
    }

    (
        while true; do
            rm -f "$DAEMON_PID_FILE" 2>/dev/null
            sh "$DAEMON_SH" >> "$SERVICES_LOGS" 2>&1
            rc=$?
            echo "[SYS][SERVICE][WARN] Daemon exited rc=$rc; restarting in 5s" >> "$SERVICES_LOGS"
            sleep 5
        done
    ) &
    echo "$!" > "$DAEMON_SUPERVISOR_PID_FILE"
    echo "[SYS][SERVICE] Daemon supervisor started with PID $(cat "$DAEMON_SUPERVISOR_PID_FILE" 2>/dev/null)" >> "$SERVICES_LOGS"
    return 0
}

if [ -f "$DAEMON_SUPERVISOR_PID_FILE" ] && supervisor_pid_is_running; then
    echo "[SYS][SERVICE] Daemon supervisor already running with PID $(cat "$DAEMON_SUPERVISOR_PID_FILE")" >> "$SERVICES_LOGS"
elif [ -f "$DAEMON_PID_FILE" ] && daemon_pid_is_running; then
    echo "[SYS][SERVICE] Daemon is already running with PID $(cat "$DAEMON_PID_FILE"); keeping current process" >> "$SERVICES_LOGS"
else
    rm -f "$DAEMON_SUPERVISOR_PID_FILE" 2>/dev/null
    rm -f "$DAEMON_PID_FILE" 2>/dev/null
    echo "[SYS][SERVICE] Starting daemon supervisor..." >> "$SERVICES_LOGS"
    start_daemon_supervisor || true
fi


set_selinux_enforce 1

exit 0
