#!/system/bin/sh
# SpeedProfile: Calculos para optimizar la velocidad de descarga y carga
# Puede priorizar la velocidad sobre la latencia


# echo "bbr" > /proc/sys/net/ipv4/tcp_congestion_control # Fuerza el uso de BBR para throughput máximo.
# echo "4096 87380 33554432" > /proc/sys/net/ipv4/tcp_rmem # Aumenta el máximo a 32MB para redes 5G.
# echo "4096 65536 33554432" > /proc/sys/net/ipv4/tcp_wmem
# echo 1 > /proc/sys/net/ipv4/tcp_window_scaling # Debe estar en 1.
# echo 1 > /proc/sys/net/ipv4/tcp_mtu_probing # Mantener en 1 para evitar fragmentación en LTE.
# 
# 
# # Better on Qualcomm chipsets
# 
# apply_param_set <<'EOF'
# bbr|/proc/sys/net/ipv4/tcp_congestion_control|Algoritmo BBR para máxima velocidad
# 1|/proc/sys/net/ipv4/tcp_window_scaling|Escalado de ventana activado
# 4096 87380 33554432|/proc/sys/net/ipv4/tcp_rmem|Buffer de lectura (Max 32MB)
# 4096 65536 33554432|/proc/sys/net/ipv4/tcp_wmem|Buffer de escritura (Max 32MB)
# 1|/proc/sys/net/ipv4/tcp_mtu_probing|Detección automática de MTU para evitar fragmentación
# 16384|/proc/sys/net/core/netdev_max_backlog|Cola larga para evitar pérdida en descargas pesadas
# EOF