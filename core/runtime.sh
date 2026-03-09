#!/system/bin/sh

core_daemon_trace_enabled() {
    case "${DAEMON_TRACE:-$(getprop persist.kitsunping.daemon_trace 2>/dev/null | tr -d '\r\n')}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

core_daemon_trace() {
    core_daemon_trace_enabled || return 0
    log_debug "[TRACE] $*"
}

core_daemon_iteration() {
    local pending_event
    pending_event="$(getprop persist.kitsuneping.user_event 2>/dev/null | tr -d '\r\n')"
    [ -n "$pending_event" ] && log_info "core.loop pending_event=$pending_event app_prop=${APP_EVENT_PROP:-unset}"

    core_daemon_trace "before app_event_cycle"
    if command -v network_app_event_cycle >/dev/null 2>&1; then
        network_app_event_cycle
    else
        daemon_run_app_event_cycle
    fi
    core_daemon_trace "after app_event_cycle"

    core_daemon_trace "before pairing_sync_cycle"
    if command -v network_app_pairing_sync_cycle >/dev/null 2>&1; then
        network_app_pairing_sync_cycle
    else
        daemon_run_pairing_sync_cycle
    fi
    core_daemon_trace "after pairing_sync_cycle"

    core_daemon_trace "before get_current_iface"
    current_iface="$(get_current_iface)"
    [ -z "$current_iface" ] && current_iface="none"
    core_daemon_trace "iface current_iface=$current_iface"

    core_daemon_trace "before wifi_cycle"
    if command -v network_wifi_cycle >/dev/null 2>&1; then
        network_wifi_cycle
    else
        daemon_run_wifi_cycle
    fi
    core_daemon_trace "after wifi_cycle"

    core_daemon_trace "before mobile_cycle"
    if command -v network_mobile_cycle >/dev/null 2>&1; then
        network_mobile_cycle
    else
        daemon_run_mobile_cycle
    fi
    core_daemon_trace "after mobile_cycle"

    core_daemon_trace "before wifi_transport_cycle"
    if command -v network_wifi_transport_cycle >/dev/null 2>&1; then
        network_wifi_transport_cycle
    else
        daemon_run_wifi_transport_cycle
    fi
    core_daemon_trace "after wifi_transport_cycle"

    core_daemon_trace "before mobile_transport_cycle"
    if command -v network_mobile_transport_cycle >/dev/null 2>&1; then
        network_mobile_transport_cycle
    else
        daemon_run_mobile_transport_cycle
    fi
    core_daemon_trace "after mobile_transport_cycle"

    core_daemon_trace "before target_profile_cycle"
    if command -v network_app_target_profile_cycle >/dev/null 2>&1; then
        network_app_target_profile_cycle
    else
        daemon_run_target_profile_cycle
    fi
    core_daemon_trace "after target_profile_cycle"

    core_daemon_trace "before router_status_push_cycle"
    if command -v network_app_router_status_push_cycle >/dev/null 2>&1; then
        network_app_router_status_push_cycle
    else
        daemon_run_router_status_push_cycle
    fi
    core_daemon_trace "after router_status_push_cycle"

    # Channel recommendation auto-trigger (M1)
    # Request channel scan if: pairing_ok=1 && wifi_score < threshold && sustained 3+ iterations
    if command -v daemon_run_channel_smart_trigger >/dev/null 2>&1; then
        core_daemon_trace "before channel_smart_trigger"
        daemon_run_channel_smart_trigger
        core_daemon_trace "after channel_smart_trigger"
    fi

    core_daemon_trace "before transition_cycle"
    daemon_run_transition_cycle
    core_daemon_trace "after transition_cycle"
    core_daemon_trace "before tick_cycle"
    daemon_run_tick_cycle
    core_daemon_trace "after tick_cycle"
    core_daemon_trace "before write_state_file"
    daemon_write_state_file
    core_daemon_trace "after write_state_file"
    # Diagnostic JSON export (rate-limited, max once per RUNTIME_EXPORT_INTERVAL_SEC)
    if command -v network__app__runtime_export >/dev/null 2>&1; then
        core_daemon_trace "before runtime_export"
        network__app__runtime_export
        core_daemon_trace "after runtime_export"
    fi
}

core_daemon_main_loop() {
    while true; do
        core_daemon_iteration
        sleep "$INTERVAL"
    done
}
