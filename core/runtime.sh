#!/system/bin/sh

core_runtime_profiler_load_dev() {
    runtime_profiler_script="${KITSUNPING_RUNTIME_PROFILER_DEV_SCRIPT:-/data/local/tmp/kitsunping_dev/runtime_profiler.sh}"
    runtime_profiler_marker="${KITSUNPING_RUNTIME_PROFILER_DEV_MARKER:-/data/local/tmp/kitsunping_dev/.runtime_profiler.enabled}"
    [ -r "$runtime_profiler_script" ] && [ -r "$runtime_profiler_marker" ] || return 0
    KITSUNPING_RUNTIME_PROFILER_TOGGLE_FILE="$runtime_profiler_marker"
    . "$runtime_profiler_script"
}

core_runtime_profiler_load_dev

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

core_runtime_profiler_tick_begin() {
    command -v runtime_profiler_tick_begin >/dev/null 2>&1 || return 0
    runtime_profiler_tick_begin
}

core_runtime_profiler_tick_end() {
    command -v runtime_profiler_tick_end >/dev/null 2>&1 || return 0
    runtime_profiler_tick_end "${1:-0}"
}

core_runtime_profiler_producer_begin() {
    command -v runtime_profiler_producer_begin >/dev/null 2>&1 || return 0
    runtime_profiler_producer_begin "$1"
}

core_runtime_profiler_producer_end() {
    command -v runtime_profiler_producer_end >/dev/null 2>&1 || return 0
    runtime_profiler_producer_end "${1:-0}"
}

core_daemon_iteration() {
    local pending_event producer_rc
    core_runtime_profiler_tick_begin
    pending_event="$(getprop persist.kitsuneping.user_event 2>/dev/null | tr -d '\r\n')"
    [ -n "$pending_event" ] && log_info "core.loop pending_event=$pending_event app_prop=${APP_EVENT_PROP:-unset}"

    core_runtime_profiler_producer_begin AppEventProducer
    core_daemon_trace "before app_event_cycle"
    if command -v network_app_event_cycle >/dev/null 2>&1; then
        network_app_event_cycle
    else
        daemon_run_app_event_cycle
    fi
    producer_rc=$?
    core_daemon_trace "after app_event_cycle"
    core_runtime_profiler_producer_end "$producer_rc"

    core_runtime_profiler_producer_begin PairingSyncProducer
    core_daemon_trace "before pairing_sync_cycle"
    if command -v network_app_pairing_sync_cycle >/dev/null 2>&1; then
        network_app_pairing_sync_cycle
    else
        daemon_run_pairing_sync_cycle
    fi
    producer_rc=$?
    core_daemon_trace "after pairing_sync_cycle"
    core_runtime_profiler_producer_end "$producer_rc"

    core_runtime_profiler_producer_begin CurrentIfaceProducer
    core_daemon_trace "before get_current_iface"
    current_iface="$(get_current_iface)"
    producer_rc=$?
    [ -z "$current_iface" ] && current_iface="none"
    core_daemon_trace "iface current_iface=$current_iface"
    core_runtime_profiler_producer_end "$producer_rc"

    core_runtime_profiler_producer_begin WiFiProducer
    core_daemon_trace "before wifi_cycle"
    if command -v network_wifi_cycle >/dev/null 2>&1; then
        network_wifi_cycle
    else
        daemon_run_wifi_cycle
    fi
    producer_rc=$?
    core_daemon_trace "after wifi_cycle"
    core_runtime_profiler_producer_end "$producer_rc"

    core_runtime_profiler_producer_begin MobileProducer
    core_daemon_trace "before mobile_cycle"
    if command -v network_mobile_cycle >/dev/null 2>&1; then
        network_mobile_cycle
    else
        daemon_run_mobile_cycle
    fi
    producer_rc=$?
    core_daemon_trace "after mobile_cycle"
    core_runtime_profiler_producer_end "$producer_rc"

    core_runtime_profiler_producer_begin WiFiTransportProducer
    core_daemon_trace "before wifi_transport_cycle"
    if command -v network_wifi_transport_cycle >/dev/null 2>&1; then
        network_wifi_transport_cycle
    else
        daemon_run_wifi_transport_cycle
    fi
    producer_rc=$?
    core_daemon_trace "after wifi_transport_cycle"
    core_runtime_profiler_producer_end "$producer_rc"

    core_runtime_profiler_producer_begin MobileTransportProducer
    core_daemon_trace "before mobile_transport_cycle"
    if command -v network_mobile_transport_cycle >/dev/null 2>&1; then
        network_mobile_transport_cycle
    else
        daemon_run_mobile_transport_cycle
    fi
    producer_rc=$?
    core_daemon_trace "after mobile_transport_cycle"
    core_runtime_profiler_producer_end "$producer_rc"

    core_runtime_profiler_producer_begin TargetProfileProducer
    core_daemon_trace "before target_profile_cycle"
    if command -v network_app_target_profile_cycle >/dev/null 2>&1; then
        network_app_target_profile_cycle
    else
        daemon_run_target_profile_cycle
    fi
    producer_rc=$?
    core_daemon_trace "after target_profile_cycle"
    core_runtime_profiler_producer_end "$producer_rc"

    core_runtime_profiler_producer_begin RouterStatusPushProducer
    core_daemon_trace "before router_status_push_cycle"
    if command -v network_app_router_status_push_cycle >/dev/null 2>&1; then
        network_app_router_status_push_cycle
    else
        daemon_run_router_status_push_cycle
    fi
    producer_rc=$?
    core_daemon_trace "after router_status_push_cycle"
    core_runtime_profiler_producer_end "$producer_rc"

    # Channel recommendation auto-trigger (M1)
    # Request channel scan if: pairing_ok=1 && wifi_score < threshold && sustained 3+ iterations
    if command -v daemon_run_channel_smart_trigger >/dev/null 2>&1; then
        core_runtime_profiler_producer_begin ChannelSmartTriggerProducer
        core_daemon_trace "before channel_smart_trigger"
        daemon_run_channel_smart_trigger
        producer_rc=$?
        core_daemon_trace "after channel_smart_trigger"
        core_runtime_profiler_producer_end "$producer_rc"
    fi

    core_runtime_profiler_producer_begin TransitionProducer
    core_daemon_trace "before transition_cycle"
    daemon_run_transition_cycle
    producer_rc=$?
    core_daemon_trace "after transition_cycle"
    core_runtime_profiler_producer_end "$producer_rc"
    core_runtime_profiler_producer_begin DaemonTickProducer
    core_daemon_trace "before tick_cycle"
    daemon_run_tick_cycle
    producer_rc=$?
    core_daemon_trace "after tick_cycle"
    core_runtime_profiler_producer_end "$producer_rc"
    core_runtime_profiler_producer_begin DaemonStateProducer
    core_daemon_trace "before write_state_file"
    daemon_write_state_file
    producer_rc=$?
    core_daemon_trace "after write_state_file"
    core_runtime_profiler_producer_end "$producer_rc"
    if command -v daemon_promote_startup_status_if_healthy >/dev/null 2>&1; then
        core_runtime_profiler_producer_begin StartupStatusProducer
        daemon_promote_startup_status_if_healthy || true
        producer_rc=$?
        core_runtime_profiler_producer_end "$producer_rc"
    fi
    # Diagnostic JSON export (rate-limited, max once per RUNTIME_EXPORT_INTERVAL_SEC)
    if command -v network__app__runtime_export >/dev/null 2>&1; then
        core_runtime_profiler_producer_begin RuntimeExportProducer
        core_daemon_trace "before runtime_export"
        network__app__runtime_export
        producer_rc=$?
        core_daemon_trace "after runtime_export"
        core_runtime_profiler_producer_end "$producer_rc"
    fi
    if command -v kitsunpingd_metrics_record >/dev/null 2>&1; then
        kitsunpingd_metrics_record "cycle" 0 0 0 0
    fi
    core_runtime_profiler_tick_end 0
}

core_daemon_main_loop() {
    while true; do
        core_daemon_iteration
        sleep "$INTERVAL"
    done
}
