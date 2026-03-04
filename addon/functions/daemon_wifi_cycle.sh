daemon_run_wifi_cycle() {
    if command -v network__wifi__cycle >/dev/null 2>&1; then
        network__wifi__cycle "$@"
        return $?
    fi
    if command -v network_wifi_cycle >/dev/null 2>&1; then
        network_wifi_cycle "$@"
        return $?
    fi
    return 0
}

daemon_run_wifi_transport_cycle() {
    if command -v network__wifi__transport_cycle >/dev/null 2>&1; then
        network__wifi__transport_cycle "$@"
        return $?
    fi
    if command -v network_wifi_transport_cycle >/dev/null 2>&1; then
        network_wifi_transport_cycle "$@"
        return $?
    fi
    return 0
}
