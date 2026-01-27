#!/system/bin/sh
# decide_profile.sh - selecciona perfil de red basado en el estado de Wi-Fi
# Parte de Kitsunping - daemon.sh

# Variables de entorno esperadas:
#   wifi_state   - estado actual de Wi-Fi (connected/disconnected)
#   iface        - interfaz de red Wi-Fi (ej. wlan0)
#   details      - detalles adicionales del estado Wi-Fi (ej. no_default_route, no_ip)
#   last_event   - último evento detectado (opcional)
#   event_details - detalles del último evento (opcional)
#   Retorna: 
#     escribe el perfil decidido en $MODDIR/cache/policy.target (speed/balanced/stable)
pick_profile() {
    wifi_state="$1" # estado actual de Wi-Fi
    iface="$2" # interfaz Wi-Fi actual
    details="$3"   # por ahora puede venir vacío
    wifi_details="$4" # detalles adicionales del estado Wi-Fi
    last_event="$5" # último evento detectado (opcional)

    case "$wifi_state" in
        connected)
            # Si hay Wi-Fi pero no es claramente bueno → balanced
            case "$details" in
                *no_default_route*|*no_ip*)
                    echo "balanced"
                    ;;
                *)
                    echo "speed"
                    ;;
            esac
            ;;
        disconnected)
            echo "stable"
            ;;
        *)
            echo "stable"
            ;;
    esac
}