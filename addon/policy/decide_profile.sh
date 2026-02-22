#!/system/bin/sh
# Parte de Kitsunping - daemon.sh

# Variables de entorno esperadas:
#   wifi_state   - Current state of Wi-Fi (connected/disconnected)
#   iface        - Wi-Fi network interface (e.g., wlan0)
#   details      - Additional Wi-Fi state details (e.g., no_default_route, no_ip)
#   last_event   - Last detected event (optional)
#   event_details - Details of the last event (optional)
#   Returns: 
#     echoes the decided profile name (speed/balanced/stable)

# TODO: [PENDING] Implement dedicated gaming profile selection logic TODO:
pick_profile() {
    wifi_state="$1" # Current state of Wi-Fi
    iface="$2" # Current Wi-Fi interface
    details="$3"   # For now, can be empty
    wifi_details="$4" # Additional Wi-Fi state details
    last_event="$5" # Last detected event (optional)

    # wifi_state can be "connected", "disconnected", or "unknown"/""/"none". For now, we will use a simple logic:
    case "$wifi_state" in
        connected)
            # If Wi-Fi is present but not clearly good → stable
            case "$details" in
                *no_default_route*|*no_ip*)
                    echo "stable"
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

    # rmnet logic can be added here in the future, for now we will focus on Wi-Fi conditions. The profile can also be influenced by specific events (e.g., "ping_degradation", "signal_loss"), which can be passed via $last_event and $event_details for more dynamic decisions.
    
}