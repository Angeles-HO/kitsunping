#!/bin/bash
# Daemon transition logic for Kitsunping. This script is sourced by the main daemon loop and contains functions related to detecting and handling state transitions, such as interface changes, Wi-Fi connectivity changes
daemon_run_transition_cycle() {
    if [ "$current_iface" != "$last_iface" ]; then
        log_info "iface_changed: $last_iface -> $current_iface"
        emit_event "$EV_IFACE_CHANGED" "from=$last_iface to=$current_iface"
        last_iface="$current_iface"
    fi

    if [ "$wifi_state" != "$last_wifi_state" ]; then
        log_info "wifi_state_changed: $last_wifi_state -> $wifi_state ($wifi_details)"
        if [ "$wifi_state" = "connected" ] && [ "$last_wifi_state" != "connected" ]; then
            verify_router_identity_on_wifi_join "$wifi_bssid" "$wifi_band" "$wifi_chan" "$wifi_freq" "$wifi_width" "$wifi_width_source" "$wifi_width_confidence" "$wifi_caps"
        fi
        if [ "$last_wifi_state" = "connected" ] && [ "$wifi_state" = "disconnected" ]; then
            log_info "event: wifi_left -> assume mobile priority"
            emit_event "$EV_WIFI_LEFT" "iface=$WIFI_IFACE $wifi_details"
        elif [ "$last_wifi_state" = "disconnected" ] && [ "$wifi_state" = "connected" ]; then
            emit_event "$EV_WIFI_JOINED" "iface=$WIFI_IFACE $wifi_details"
        fi
        last_wifi_state="$wifi_state"
    fi
}

daemon_run_tick_cycle() {
    local tick_msg selected_score
    loop_count=$((loop_count + 1))
    if [ $loop_count -ge 6 ] || [ "$current_iface" = "none" ]; then
        tick_msg="tick iface=$current_iface wifi=$wifi_state ($wifi_details)"
        if command -v pick_score_from_state >/dev/null 2>&1; then
            selected_score=$(pick_score_from_state "$STATE_FILE" "auto" "${EVENT_NAME:-}" "${EVENT_DETAILS:-}" 2>/dev/null || true)
            if [ -n "$selected_score" ]; then
                tick_msg="$tick_msg selected_score=$selected_score source=${PICK_SCORE_SOURCE:-unknown}"
            fi
        fi
        if [ "$(getprop persist.kitsunping.debug)" -eq 1 ]; then
            log_debug "tick: $tick_msg"
        fi
        loop_count=0
    fi
}
