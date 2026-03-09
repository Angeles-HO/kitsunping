#!/system/bin/sh
# policy/rules/decide_profile.sh

pick_profile() {
    wifi_state="$1"
    iface="$2"
    details="$3"
    wifi_details="$4"
    last_event="$5"

    case "$wifi_state" in
        connected)
            case "$details" in
                *no_default_route*|*no_ip*)
                    echo "stable"
                    ;;
                *)
                    echo "stable"
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
