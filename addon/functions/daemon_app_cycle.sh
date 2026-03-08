daemon_run_app_event_cycle() {
    if command -v network__app__event_cycle >/dev/null 2>&1; then
        network__app__event_cycle "$@"
    elif command -v network_app_event_cycle >/dev/null 2>&1; then
        network_app_event_cycle "$@"
    fi
}

daemon_run_pairing_sync_cycle() {
    if command -v network__app__pairing_sync_cycle >/dev/null 2>&1; then
        network__app__pairing_sync_cycle "$@"
    elif command -v network_app_pairing_sync_cycle >/dev/null 2>&1; then
        network_app_pairing_sync_cycle "$@"
    fi
}

daemon_run_target_profile_cycle() {
    if command -v network__app__target_profile_cycle >/dev/null 2>&1; then
        network__app__target_profile_cycle "$@"
    elif command -v network_app_target_profile_cycle >/dev/null 2>&1; then
        network_app_target_profile_cycle "$@"
    fi
}

daemon_run_router_status_push_cycle() {
    if command -v network__app__router_status_push_cycle >/dev/null 2>&1; then
        network__app__router_status_push_cycle "$@"
    elif command -v network_app_router_status_push_cycle >/dev/null 2>&1; then
        network_app_router_status_push_cycle "$@"
    fi
}

normalize_target_token() {
    if command -v network__app__normalize_target_token >/dev/null 2>&1; then
        network__app__normalize_target_token "$@"
    fi
}

target_prop_lookup_profile() {
    if command -v network__app__target_prop_lookup_profile >/dev/null 2>&1; then
        network__app__target_prop_lookup_profile "$@"
    fi
}

daemon_detect_foreground_package() {
    if command -v network__app__detect_foreground_package >/dev/null 2>&1; then
        network__app__detect_foreground_package "$@"
    fi
}

target_request_emit_allowed() {
    if command -v network__app__target_request_emit_allowed >/dev/null 2>&1; then
        network__app__target_request_emit_allowed "$@"
    fi
}

read_pairing_json_field() {
    if command -v network__app__read_pairing_json_field >/dev/null 2>&1; then
        network__app__read_pairing_json_field "$@"
    fi
}

daemon_get_wifi_client_mac() {
    if command -v network__app__get_wifi_client_mac >/dev/null 2>&1; then
        network__app__get_wifi_client_mac "$@"
    fi
}

router_send_module_status() {
    if command -v network__app__router_send_module_status >/dev/null 2>&1; then
        network__app__router_send_module_status "$@"
    fi
}
