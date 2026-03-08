daemon_run_mobile_cycle() {
    if command -v network__mobile__cycle >/dev/null 2>&1; then
        network__mobile__cycle "$@"
        return $?
    fi
    if command -v network_mobile_cycle >/dev/null 2>&1; then
        network_mobile_cycle "$@"
        return $?
    fi
    return 0
}

daemon_run_mobile_transport_cycle() {
    if command -v network__mobile__transport_cycle >/dev/null 2>&1; then
        network__mobile__transport_cycle "$@"
        return $?
    fi
    if command -v network_mobile_transport_cycle >/dev/null 2>&1; then
        network_mobile_transport_cycle "$@"
        return $?
    fi
    return 0
}
