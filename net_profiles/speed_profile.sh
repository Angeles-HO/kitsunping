#!/system/bin/sh
# speed_profile: prioriza throughput

LOG_OUT="${SERVICES_LOGS:-/dev/null}"
echo "[PROFILE] speed start" >> "$LOG_OUT"

apply_param_set <<'EOF'
bbr|/proc/sys/net/ipv4/tcp_congestion_control|Algoritmo BBR para máxima velocidad
1|/proc/sys/net/ipv4/tcp_window_scaling|Escalado de ventana activado
4096 87380 33554432|/proc/sys/net/ipv4/tcp_rmem|Buffer de lectura (Max 32MB)
4096 65536 33554432|/proc/sys/net/ipv4/tcp_wmem|Buffer de escritura (Max 32MB)
1|/proc/sys/net/ipv4/tcp_mtu_probing|Detección automática de MTU para evitar fragmentación
16384|/proc/sys/net/core/netdev_max_backlog|Cola larga para evitar pérdida en descargas pesadas
EOF

echo "[PROFILE] speed done" >> "$LOG_OUT"