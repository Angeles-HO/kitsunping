#!/system/bin/sh
# stable_profile: prioriza estabilidad y bajo riesgo

LOG_OUT="${SERVICES_LOGS:-/dev/null}"
echo "[PROFILE] stable start" >> "$LOG_OUT"

apply_param_set <<'EOF'
cubic|/proc/sys/net/ipv4/tcp_congestion_control|Cubic estable
0|/proc/sys/net/core/busy_poll|Ahorro de CPU
64|/proc/sys/net/core/dev_weight|Balance estándar
4096 87380 16777216|/proc/sys/net/ipv4/tcp_rmem|Buffer lectura balanceado (16MB)
4096 65536 16777216|/proc/sys/net/ipv4/tcp_wmem|Buffer escritura balanceado (16MB)
1|/proc/sys/net/ipv4/tcp_sack|SACK habilitado
EOF

echo "[PROFILE] stable done" >> "$LOG_OUT"