#!/system/bin/sh
# gaming_profile: prioriza latencia baja

LOG_OUT="${SERVICES_LOGS:-/dev/null}"
echo "[PROFILE] gaming start" >> "$LOG_OUT"

apply_param_set <<'EOF'
50|/proc/sys/net/core/busy_poll|Menor latencia en sockets
50|/proc/sys/net/core/busy_read|Respuesta de lectura rápida
128|/proc/sys/net/core/dev_weight|Más paquetes por interrupción
1|/proc/sys/net/ipv4/tcp_low_latency|Prioridad a latencia
0|/proc/sys/net/ipv4/tcp_sack|SACK off para pure latency
1|/proc/sys/net/ipv4/tcp_fastopen|Inicio rápido
5|/proc/sys/net/ipv4/tcp_fin_timeout|Cierre veloz de conexiones muertas
1024|/proc/sys/net/core/netdev_max_backlog|Cola ajustada
EOF

echo "[PROFILE] gaming done" >> "$LOG_OUT"