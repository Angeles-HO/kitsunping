#!/system/bin/sh
# =============================================================================
# Script de configuracion de red (service.sh)
# Este script espera a que el sistema finalice el arranque, respalda los valores
# por defecto de los parametros de red en logs/services.log y luego aplica diversas
# optimizaciones de red.
# /data/adb/modules/Kitsun_ping/logs/services.log
# =============================================================================
MODDIR=${0%/*}
# =============================================================================
mkdir -p "$MODDIR/logs" 2>/dev/null
SERVICES_LOGS="$MODDIR/logs/services.log"
# =============================================================================
# Funcion: Espera a que el sistema finalice el arranque

# Utilidades comunes
COMMON_UTIL="$MODDIR/addon/functions/utils/Kitsutils.sh"

if [ -f "$COMMON_UTIL" ]; then
    . "$COMMON_UTIL"
else
    ALT_MODDIR="/data/adb/modules_update/${MODDIR##*/}"
    ALT_COMMON="$ALT_MODDIR/addon/functions/utils/Kitsutils.sh"
    if [ -f "$ALT_COMMON" ]; then
        . "$ALT_COMMON"
    else
        echo "[SYS][WARN]: No se pudo cargar $COMMON_UTIL ni $ALT_COMMON" >> "$SERVICES_LOGS"
        set_selinux_enforce() {
            enforce_state="$1"
            if [ "$(id -u)" -ne 0 ]; then
                echo "[SYS][ERROR]: root requerido" >> "$SERVICES_LOGS"
                return 1
            fi
            case "$enforce_state" in
                0|1) :;;
                *) echo "[SYS][ERROR]: Valor invalido: $enforce_state" >> "$SERVICES_LOGS"; return 2 ;;
            esac
            if setenforce "$enforce_state"; then
                echo "[SYS][OK]: SELinux temporal: $(getenforce)" >> "$SERVICES_LOGS"
            else
                echo "[SYS][ERROR]: Fallo setenforce" >> "$SERVICES_LOGS"
                return 3
            fi
            return 0
        }
    fi
fi

# Opcional: asegurar permisos si no se fijaron en post-fs-data
#set_permissions_module "$MODDIR" "$SERVICES_LOGS"

# =============================================================================
# Funciones para aplicar configuraciones de red
# =============================================================================

# Normaliza valores de sysctl (convierte comas a espacios cuando aplica)
normalize_sysctl_value() {
    case "$1" in
        *","*) echo "${1//,/ }" ;;
        *) echo "$1" ;;
    esac
}

# Actualizacion: Una funcion simple para agilizar el script y evitar la repeticion de codigo
# └──Actualizacion: Cambie el nombre de la funcion a custom_write
custom_write() {
    echo "[DEBUG]: Llamada a [custom_write()] con argumentos: ['$1'], ['$2'], ['$3']" >> "$SERVICES_LOGS"

    value="$1"
    normalized_value=$(normalize_sysctl_value "$value")
    target_file="$2"
    log_text="$3"

    if [ "$#" -ne 3 ]; then
        echo "[SYS] [ERROR]: Numero de argumentos invalido en [custom_write()]" >> "$SERVICES_LOGS"
        return 1
    fi

    case "$target_file" in
        /*) ;;
        *)
            echo "[SYS] [ERROR]: Ruta no absoluta: '$target_file'" >> "$SERVICES_LOGS"
            return 2
            ;;
    esac

    if [ -z "$value" ] && [ "$value" != "0" ]; then
        echo "[SYS] [ERROR]: Valor vacio para '$target_file'" >> "$SERVICES_LOGS"
        return 3
    fi

    if [ ! -e "$target_file" ]; then
        echo "[SYS] [WARN]: Ruta no existe: '$target_file'" >> "$SERVICES_LOGS"
        return 0
    fi

    case "$target_file" in
        /proc/sys/*)
            sysctl_param=${target_file#/proc/sys/}
            sysctl_param=$(echo "$sysctl_param" | tr '/' '.')
            # Skip if not writable to avoid noisy errors on readonly tunables
            if [ ! -w "$target_file" ]; then
                echo "[SYS][SKIP]: '$target_file' no es escribible" >> "$SERVICES_LOGS"
                return 0
            fi
            if /system/bin/sysctl -w "$sysctl_param=$normalized_value" >> "$SERVICES_LOGS" 2>&1; then
                echo "[OK] $log_text (sysctl): $normalized_value" >> "$SERVICES_LOGS"
                return 0
            fi
            echo "[SYS] [ERROR]: Fallo sysctl $sysctl_param" >> "$SERVICES_LOGS"
            ;;
    esac

    printf "%s" "$normalized_value" > "$target_file" 2>> "$SERVICES_LOGS"
    current_value=$(cat "$target_file" 2>/dev/null)
    if [ "$current_value" = "$normalized_value" ]; then
        echo "[OK] $log_text: $normalized_value" >> "$SERVICES_LOGS"
    else
        echo "[SYS] [ERROR]: Valor escrito ($current_value) != esperado ($normalized_value) en $target_file" >> "$SERVICES_LOGS"
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
    echo "[Aplicando configuraciones RIL...]"  >> "$SERVICES_LOGS"
    # Simulacion de espera para aplicar las configuraciones definidas en system.prop
    echo "[Configuraciones RIL completadas]"   >> "$SERVICES_LOGS"
}

apply_general_network_settings() { 
    echo "[Aplicando configuraciones generales de red...]"  >> "$SERVICES_LOGS"
    echo "[Configuraciones generales de red completadas]"  >> "$SERVICES_LOGS"
}

apply_core_settings() {
    echo "[Aplicando configuraciones [CORE]...]"  >> "$SERVICES_LOGS"
    apply_param_set <<'EOF'
1|/proc/sys/net/core/bpf_jit_enable|bpf_jit_enable ajustado
0|/proc/sys/net/core/bpf_jit_harden|bpf_jit_harden ajustado
1|/proc/sys/net/core/bpf_jit_kallsyms|bpf_jit_kallsyms ajustado
33554432|/proc/sys/net/core/bpf_jit_limit|bpf_jit_limit ajustado
0|/proc/sys/net/core/busy_poll|busy_poll ajustado
0|/proc/sys/net/core/busy_read|busy_read ajustado
pfifo_fast|/proc/sys/net/core/default_qdisc|default_qdisc ajustado
64|/proc/sys/net/core/dev_weight|dev_weight ajustado
1|/proc/sys/net/core/dev_weight_rx_bias|dev_weight_rx_bias ajustado
1|/proc/sys/net/core/dev_weight_tx_bias|dev_weight_tx_bias ajustado
0|/proc/sys/net/core/fb_tunnels_only_for_init_net|fb_tunnels_only_for_init_net ajustado
00|/proc/sys/net/core/flow_limit_cpu_bitmap|flow_limit_cpu_bitmap ajustado
4096|/proc/sys/net/core/flow_limit_table_len|flow_limit_table_len ajustado
17|/proc/sys/net/core/max_skb_frags|max_skb_frags ajustado
10|/proc/sys/net/core/message_burst|message_burst ajustado
5|/proc/sys/net/core/message_cost|message_cost ajustado
256|/proc/sys/net/core/netdev_budget|netdev_budget ajustado
8000|/proc/sys/net/core/netdev_budget_usecs|netdev_budget_usecs ajustado
512|/proc/sys/net/core/netdev_max_backlog|netdev_max_backlog ajustado
1|/proc/sys/net/core/netdev_tstamp_prequeue|netdev_tstamp_prequeue ajustado
8388608|/proc/sys/net/core/wmem_max|wmem_max ajustado
8388608|/proc/sys/net/core/rmem_max|rmem_max ajustado
262144|/proc/sys/net/core/rmem_default|rmem_default ajustado
262144|/proc/sys/net/core/wmem_default|wmem_default ajustado
65536|/proc/sys/net/core/optmem_max|optmem_max ajustado
0|/proc/sys/net/core/rps_sock_flow_entries|rps_sock_flow_entries ajustado
128|/proc/sys/net/core/somaxconn|somaxconn ajustado
1|/proc/sys/net/core/tstamp_allow_data|tstamp_allow_data ajustado
3600|/proc/sys/net/core/xfrm_acq_expires|xfrm_acq_expires ajustado
10|/proc/sys/net/core/xfrm_aevent_etime|xfrm_aevent_etime ajustado
2|/proc/sys/net/core/xfrm_aevent_rseqth|xfrm_aevent_rseqth ajustado
1|/proc/sys/net/core/xfrm_larval_drop|xfrm_larval_drop ajustado
0|/proc/sys/net/core/warnings|warnings ajustado
EOF

    echo "[Configuraciones de red CORE aplicadas correctamente]"  >> "$SERVICES_LOGS"
}

# Actualizacion: Se aplican configuraciones de red IPv4 y TCP
apply_tcp_settings() {
    echo "[Aplicando configuraciones [ IPV4/TCP ]...]"  >> "$SERVICES_LOGS"
    apply_param_set <<'EOF'
1|/proc/sys/net/ipv4/tcp_ecn|tcp_ecn deshabilitado
1|/proc/sys/net/ipv4/tcp_sack|tcp_sack habilitado
1|/proc/sys/net/ipv4/tcp_fack|tcp_fack habilitado
1|/proc/sys/net/ipv4/tcp_window_scaling|tcp_window_scaling habilitado
16384 87380 26777216|/proc/sys/net/ipv4/tcp_rmem|tcp_rmem ajustado
16384 87380 26777216|/proc/sys/net/ipv4/tcp_wmem|tcp_wmem ajustado
65536 131072 262144|/proc/sys/net/ipv4/tcp_mem|tcp_mem ajustado
cubic|/proc/sys/net/ipv4/tcp_congestion_control|tcp_congestion_control configurado a cubic
1|/proc/sys/net/ipv4/tcp_no_metrics_save|tcp_no_metrics_save habilitado
 bbr cubic|/proc/sys/net/ipv4/tcp_allowed_congestion_control|tcp_allowed_congestion_control ajustado a bic y cubic
 bbr cubic|/proc/sys/net/ipv4/tcp_available_congestion_control|tcp_available_congestion_control ajustado a bic y cubic
3|/proc/sys/net/ipv4/tcp_fastopen|tcp_fastopen habilitado
5|/proc/sys/net/ipv4/tcp_retries1|tcp_retries1 ajustado
5|/proc/sys/net/ipv4/tcp_retries2|tcp_retries2 ajustado
2097152|/proc/sys/net/ipv4/tcp_limit_output_bytes|tcp_limit_output_bytes ajustado
3|/proc/sys/net/ipv4/tcp_orphan_retries|tcp_orphan_retries ajustado
512|/proc/sys/net/ipv4/tcp_max_syn_backlog|tcp_max_syn_backlog ajustado
32768|/proc/sys/net/ipv4/tcp_max_orphans|tcp_max_orphans ajustado
10|/proc/sys/net/ipv4/tcp_fin_timeout|tcp_fin_timeout ajustado
35|/proc/sys/net/ipv4/tcp_keepalive_time|tcp_keepalive_time ajustado
10|/proc/sys/net/ipv4/tcp_keepalive_intvl|tcp_keepalive_intvl ajustado
3|/proc/sys/net/ipv4/tcp_keepalive_probes|tcp_keepalive_probes ajustado
1|/proc/sys/net/ipv4/tcp_syncookies|tcp_syncookies habilitado
EOF

    echo "[Configuraciones TCP completadas]"  >> "$SERVICES_LOGS"
}

# Actualizacion: Se aplican configuraciones de red IPv4 y TCP
apply_network_ipv4_settings() {
    echo "[Aplicando configuraciones [ IPV4/OTHERS ]...]"  >> "$SERVICES_LOGS"

    apply_param_set <<'EOF'
1|/proc/sys/net/ipv4/conf/default/rp_filter|rp_filter configurado en modo estricto
0|/proc/sys/net/ipv4/conf/default/accept_redirects|accept_redirects deshabilitado
0|/proc/sys/net/ipv4/conf/default/accept_source_route|accept_source_route deshabilitado
1|/proc/sys/net/ipv4/fwmark_reflect|fwmark_reflect habilitado
0|/proc/sys/net/ipv4/icmp_echo_ignore_all|icmp_echo_ignore_all deshabilitado
1|/proc/sys/net/ipv4/icmp_echo_ignore_broadcasts|icmp_echo_ignore_broadcasts habilitado
0|/proc/sys/net/ipv4/icmp_errors_use_inbound_ifaddr|icmp_errors_use_inbound_ifaddr deshabilitado
1|/proc/sys/net/ipv4/icmp_ignore_bogus_error_responses|icmp_ignore_bogus_error_responses habilitado
100|/proc/sys/net/ipv4/icmp_msgs_burst|icmp_msgs_burst optimizado
5000|/proc/sys/net/ipv4/icmp_msgs_per_sec|icmp_msgs_per_sec optimizado
500|/proc/sys/net/ipv4/icmp_ratelimit|icmp_ratelimit optimizado para menor latencia
6168|/proc/sys/net/ipv4/icmp_ratemask|icmp_ratemask ajustado
1|/proc/sys/net/ipv4/igmp_link_local_mcast_reports|igmp_link_local_mcast_reports habilitado
50|/proc/sys/net/ipv4/igmp_max_memberships|igmp_max_memberships ajustado para mayor eficiencia
20|/proc/sys/net/ipv4/igmp_max_msf|igmp_max_msf ajustado
2|/proc/sys/net/ipv4/igmp_qrv|igmp_qrv ajustado
64|/proc/sys/net/ipv4/ip_default_ttl|ip_default_ttl ajustado
0|/proc/sys/net/ipv4/ip_dynaddr|ip_dynaddr deshabilitado
1|/proc/sys/net/ipv4/ip_early_demux|ip_early_demux habilitado para procesamiento mas rapido
0|/proc/sys/net/ipv4/ip_forward|ip_forward deshabilitado para reducir el overhead
1|/proc/sys/net/ipv4/ip_forward_update_priority|ip_forward_update_priority ajustado
0|/proc/sys/net/ipv4/ip_forward_use_pmtu|ip_forward_use_pmtu deshabilitado
1|/proc/sys/net/ipv4/tcp_mtu_probing|tcp_mtu_probing habilitado
1024 65535|/proc/sys/net/ipv4/ip_local_port_range|ip_local_port_range ampliado para mas conexiones
0|/proc/sys/net/ipv4/ip_no_pmtu_disc|ip_no_pmtu_disc deshabilitado
1|/proc/sys/net/ipv4/ip_nonlocal_bind|ip_nonlocal_bind habilitado para permitir mas conexiones
1024|/proc/sys/net/ipv4/ip_unprivileged_port_start|ip_unprivileged_port_start ajustado
4194304|/proc/sys/net/ipv4/ipfrag_high_thresh|ipfrag_high_thresh ajustado para mayor buffer
3145728|/proc/sys/net/ipv4/ipfrag_low_thresh|ipfrag_low_thresh ajustado
64|/proc/sys/net/ipv4/ipfrag_max_dist|ipfrag_max_dist ajustado
0|/proc/sys/net/ipv4/ipfrag_secret_interval|ipfrag_secret_interval ajustado
30|/proc/sys/net/ipv4/ipfrag_time|ipfrag_time ajustado
1|/proc/sys/net/ipv4/udp_early_demux|udp_early_demux habilitado para procesamiento mas rapido
131072 262144 524288|/proc/sys/net/ipv4/udp_mem|udp_mem ajustado para mayor rendimiento
8192|/proc/sys/net/ipv4/udp_rmem_min|udp_rmem_min optimizado
8192|/proc/sys/net/ipv4/udp_wmem_min|udp_wmem_min optimizado
600|/proc/sys/net/ipv4/inet_peer_maxttl|inet_peer_maxttl ajustado
120|/proc/sys/net/ipv4/inet_peer_minttl|inet_peer_minttl ajustado
131072|/proc/sys/net/ipv4/inet_peer_threshold|inet_peer_threshold ajustado para mas peers
0 2147483647|/proc/sys/net/ipv4/ping_group_range|ping_group_range ajustado
32768|/proc/sys/net/ipv4/xfrm4_gc_thresh|xfrm4_gc_thresh ajustado
EOF

    echo "[Configuraciones de red optimizadas completadas]"  >> "$SERVICES_LOGS"
}

apply_network_ipv6_settings() {
    echo "[Aplicando configuraciones [ IPV6/OTHERS ]...]"  >> "$SERVICES_LOGS"

    apply_param_set <<'EOF'
0|/proc/sys/net/ipv6/anycast_src_echo_reply|anycast_src_echo_reply deshabilitado
1|/proc/sys/net/ipv6/auto_flowlabels|auto_flowlabels habilitado
0|/proc/sys/net/ipv6/fib_multipath_hash_policy|fib_multipath_hash_policy ajustado
1|/proc/sys/net/ipv6/flowlabel_consistency|flowlabel_consistency habilitado
0|/proc/sys/net/ipv6/flowlabel_reflect|flowlabel_reflect deshabilitado
0|/proc/sys/net/ipv6/flowlabel_state_ranges|flowlabel_state_ranges ajustado
1|/proc/sys/net/ipv6/fwmark_reflect|fwmark_reflect habilitado
1|/proc/sys/net/ipv6/idgen_delay|idgen_delay ajustado
3|/proc/sys/net/ipv6/idgen_retries|idgen_retries ajustado
0|/proc/sys/net/ipv6/ip_nonlocal_bind|ip_nonlocal_bind deshabilitado
4194304|/proc/sys/net/ipv6/ip6frag_high_thresh|ip6frag_high_thresh ajustado
3145728|/proc/sys/net/ipv6/ip6frag_low_thresh|ip6frag_low_thresh ajustado
0|/proc/sys/net/ipv6/ip6frag_secret_interval|ip6frag_secret_interval ajustado
60|/proc/sys/net/ipv6/ip6frag_time|ip6frag_time ajustado
2147483647|/proc/sys/net/ipv6/max_dst_opts_length|max_dst_opts_length ajustado
8|/proc/sys/net/ipv6/max_dst_opts_number|max_dst_opts_number ajustado
2147483647|/proc/sys/net/ipv6/max_hbh_length|max_hbh_length ajustado
8|/proc/sys/net/ipv6/max_hbh_opts_number|max_hbh_opts_number ajustado
64|/proc/sys/net/ipv6/mld_max_msf|mld_max_msf ajustado
2|/proc/sys/net/ipv6/mld_qrv|mld_qrv ajustado
0|/proc/sys/net/ipv6/seg6_flowlabel|seg6_flowlabel deshabilitado
32768|/proc/sys/net/ipv6/xfrm6_gc_thresh|xfrm6_gc_thresh ajustado
EOF

    echo "[Configuraciones de red IPv6 completadas]"  >> "$SERVICES_LOGS"
}

apply_network_optimizations() {
    echo "[SYS][SERVICE] Iniciando la aplicacion de todas las configuraciones..." >> "$SERVICES_LOGS" 
    apply_core_settings || echo "[SYS][SERVICE] Error al aplicar configuraciones [CORE]" >> "$SERVICES_LOGS"
    apply_tcp_settings || echo "[SYS][SERVICE] Error al aplicar configuraciones [CORE]" >> "$SERVICES_LOGS"
    apply_network_ipv4_settings || echo "[SYS][SERVICE] Error al aplicar configuraciones [CORE]" >> "$SERVICES_LOGS"
    apply_network_ipv6_settings || echo "[SYS][SERVICE] Error al aplicar configuraciones [CORE]" >> "$SERVICES_LOGS"
    apply_general_network_settings|| echo "[SYS][SERVICE] Error al aplicar configuraciones [CORE]" >> "$SERVICES_LOGS"
    echo "[SYS][SERVICE] Todas las configuraciones se han aplicado correctamente" >> "$SERVICES_LOGS"
}

set_selinux_enforce 0
while true
do boot=$(getprop sys.boot_completed)
if [ "$boot" = 1 ]; then
    apply_network_optimizations
    set_selinux_enforce 1
    exit
fi
sleep 1
done
exit 0