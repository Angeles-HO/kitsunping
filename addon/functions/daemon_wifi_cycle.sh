daemon_run_wifi_cycle() {
    wifi_readout="$(get_wifi_status)"
    wifi_link="DOWN"; wifi_ip=0; wifi_egress=0
    wifi_path_reason="link_down"
    wifi_rssi_dbm=""
    wifi_rssi_score=""
    wifi_latency_ms=""
    wifi_latency_ema_ms=""
    wifi_latency_score=""
    wifi_bssid=""; wifi_band=""; wifi_caps=""; wifi_freq=""; wifi_chan=""; wifi_ssid=""; wifi_width=""
    wifi_width_source=""; wifi_width_confidence=""
    wifi_link_speed=""; wifi_signal_dbm=""; wifi_rx_rate=""; wifi_tx_rate=""
    wifi_detected_iface="none"
    for kv in $wifi_readout; do
        case "$kv" in
            iface=*) wifi_detected_iface="${kv#iface=}" ;;
            link=*) wifi_link="${kv#link=}" ;;
            ip=*) wifi_ip="${kv#ip=}" ;;
            egress=*) wifi_egress="${kv#egress=}" ;;
            reason=*) wifi_path_reason="${kv#reason=}" ;;
        esac
    done
    if [ -n "$wifi_detected_iface" ] && [ "$wifi_detected_iface" != "none" ]; then
        WIFI_IFACE="$wifi_detected_iface"
    elif [ -z "$WIFI_IFACE" ]; then
        WIFI_IFACE="none"
    fi

    wifi_state="disconnected"
    [ "$wifi_link" = "UP" ] && [ "$wifi_ip" -eq 1 ] && wifi_state="connected"
    if [ "$wifi_link" != "$last_wifi_link" ] || [ "$wifi_ip" -ne "$last_wifi_ip" ] || [ "$wifi_egress" -ne "$last_wifi_egress" ]; then
        wifi_score="$(get_score "$wifi_link" "$wifi_ip" "$wifi_egress")"
        last_wifi_link="$wifi_link"
        last_wifi_ip="$wifi_ip"
        last_wifi_egress="$wifi_egress"
        last_wifi_score="$wifi_score"
    else
        wifi_score="$last_wifi_score"
    fi

    if [ "$wifi_link" = "UP" ] && [ "$wifi_ip" -eq 1 ]; then
        wifi_rssi_dbm="$(get_wifi_rssi_dbm "$WIFI_IFACE")"
        wifi_rssi_score="$(score_wifi_rssi "$wifi_rssi_dbm")"

        if [ "${ROUTER_EXPERIMENTAL:-0}" -eq 1 ]; then
            router_heavy_started=0
            router_heavy_lock_held=0
            router_heavy_allowed=1

            if command -v calibration_priority_read >/dev/null 2>&1; then
                if [ "$(calibration_priority_read)" -eq 1 ]; then
                    router_heavy_allowed=0
                    router_debug_log "calibration_priority active; yielding router-heavy cycle"
                fi
            fi

            if [ "$router_heavy_allowed" -eq 1 ] && command -v heavy_activity_lock_acquire >/dev/null 2>&1; then
                if heavy_activity_lock_acquire; then
                    router_heavy_lock_held=1
                else
                    router_heavy_allowed=0
                    router_debug_log "heavy_activity_lock busy; skipping router-heavy cycle"
                fi
            fi

            if [ "$router_heavy_allowed" -eq 1 ]; then
                if command -v heavy_load_begin >/dev/null 2>&1; then
                    heavy_load_begin >/dev/null 2>&1 || true
                    router_heavy_started=1
                fi

                export ROUTER_INFER_WIDTH
                wifi_extended_info="$(get_wifi_extended_info "$WIFI_IFACE")"
                if [ -n "$wifi_extended_info" ]; then
                router_debug_log "wifi_info_source=${WIFI_INFO_SOURCE:-unknown}"
                if [ "${WIFI_INFO_SOURCE:-}" = "iw" ] && [ -n "${WIFI_RAW_IW_OUT:-}" ]; then
                    router_debug_log "iw_raw=$(router_debug_trunc "$WIFI_RAW_IW_OUT")"
                fi
                if [ "${WIFI_INFO_SOURCE:-}" = "dumpsys" ] && [ -n "${WIFI_RAW_DUMPSYS_OUT:-}" ]; then
                    router_debug_log "dumpsys_raw=$(router_debug_trunc "$WIFI_RAW_DUMPSYS_OUT")"
                fi
                for kv in $wifi_extended_info; do
                    case "$kv" in
                        bssid=*) wifi_bssid="${kv#bssid=}" ;;
                        band=*) wifi_band="${kv#band=}" ;;
                        caps=*) wifi_caps="${kv#caps=}" ;;
                        freq=*) wifi_freq="${kv#freq=}" ;;
                        chan=*) wifi_chan="${kv#chan=}" ;;
                        width=*) wifi_width="${kv#width=}" ;;
                        width_source=*) wifi_width_source="${kv#width_source=}" ;;
                        width_confidence=*) wifi_width_confidence="${kv#width_confidence=}" ;;
                        ssid=*) wifi_ssid="${kv#ssid=}" ;;
                        link_speed=*) wifi_link_speed="${kv#link_speed=}" ;;
                        signal_dbm=*) wifi_signal_dbm="${kv#signal_dbm=}" ;;
                        rx_rate=*) wifi_rx_rate="${kv#rx_rate=}" ;;
                        tx_rate=*) wifi_tx_rate="${kv#tx_rate=}" ;;
                    esac
                done
                if [ -z "$wifi_bssid" ] && [ -n "$wifi_ssid" ]; then
                    wifi_bssid="ssid:${wifi_ssid}"
                fi
                router_debug_log "parsed=bssid=$wifi_bssid band=$wifi_band chan=$wifi_chan freq=$wifi_freq width=$wifi_width width_source=${wifi_width_source:-} width_confidence=${wifi_width_confidence:-} caps=$wifi_caps"
                if [ -n "$wifi_bssid" ]; then
                    wifi_bssid_key=$(printf '%s' "$wifi_bssid" | tr -d ':')
                    router_cache_file="$MODDIR/cache/router_${wifi_bssid_key}.info"
                    router_cache_ttl="${ROUTER_CACHE_TTL:-3600}"
                    router_info_ttl_expired=0
                    if [ -f "$router_cache_file" ]; then
                        cache_ts=$(stat -c %Y "$router_cache_file" 2>/dev/null || echo 0)
                        now_ts=$(now_epoch)
                        case "$cache_ts" in ''|*[!0-9]* ) cache_ts=0 ;; esac
                        case "$now_ts" in ''|*[!0-9]* ) now_ts=0 ;; esac
                        if [ "$router_cache_ttl" -gt 0 ] && [ $((now_ts - cache_ts)) -ge "$router_cache_ttl" ]; then
                            rm -f "$router_cache_file" 2>/dev/null
                            router_info_ttl_expired=1
                        fi
                    fi
                    router_cache_val="$wifi_extended_info"
                    if [ -f "$router_cache_file" ]; then
                        router_cache_cur=$(cat "$router_cache_file" 2>/dev/null | tr -d '\r\n')
                    else
                        router_cache_cur=""
                    fi
                    if [ "$router_cache_cur" != "$router_cache_val" ]; then
                        printf '%s\n' "$router_cache_val" | atomic_write "$router_cache_file"
                    fi
                    if [ "$router_info_ttl_expired" -eq 1 ]; then
                        router_debug_log "router_info_ttl_expired=1 file=$router_cache_file"
                    fi
                fi
            fi
                if [ "$router_heavy_started" -eq 1 ] && command -v heavy_load_end >/dev/null 2>&1; then
                    heavy_load_end >/dev/null 2>&1 || true
                fi
            fi

            if [ "$router_heavy_lock_held" -eq 1 ] && command -v heavy_activity_lock_release >/dev/null 2>&1; then
                heavy_activity_lock_release >/dev/null 2>&1 || true
            fi
        fi

        if [ -n "$wifi_rssi_score" ] && echo "$wifi_rssi_score" | grep -Eq '^[0-9]+$'; then
            wifi_score=$(awk -v b="$wifi_score" -v r="$wifi_rssi_score" 'BEGIN{v=(b*60 + r*40)/100; if(v<0) v=0; if(v>100) v=100; printf "%d", v}')
        fi

        if [ "$wifi_egress" -eq 1 ]; then
            calib_state=""
            [ -f "$MODDIR/cache/calibrate.state" ] && calib_state=$(cat "$MODDIR/cache/calibrate.state" 2>/dev/null | tr -d '\r\n' || true)
            if [ "$calib_state" = "running" ]; then
                wifi_probe_ok=1
                wifi_probe_fail_streak=0
                wifi_probe_loop_count=0
            else
                wifi_probe_loop_count=$((wifi_probe_loop_count + 1))
                if [ "$wifi_probe_loop_count" -ge "$NET_PROBE_INTERVAL" ]; then
                    wifi_probe_loop_count=0
                    if tests_network; then
                        wifi_probe_ok=1
                        wifi_probe_fail_streak=0
                        if [ -n "${NET_LAST_RTT_MS:-}" ] && echo "$NET_LAST_RTT_MS" | grep -Eq '^[0-9]+$'; then
                            wifi_latency_ms="$NET_LAST_RTT_MS"
                            wifi_latency_score="$(score_wifi_latency "$wifi_latency_ms")"
                            if [ -n "$wifi_latency_ms" ]; then
                                wifi_latency_ema_ms="$(composite_ema "$wifi_latency_ms" "$MODDIR/cache/wifi.rtt.ema")"
                            fi
                        fi
                    else
                        wifi_probe_ok=0
                        wifi_probe_fail_streak=$((wifi_probe_fail_streak + 1))
                    fi
                fi

                if [ "$wifi_probe_fail_streak" -ge 2 ]; then
                    wifi_score=$((wifi_score - 20))
                fi
            fi
        else
            wifi_probe_ok=1
            wifi_probe_fail_streak=0
            wifi_probe_loop_count=0
        fi
    else
        wifi_probe_ok=1
        wifi_probe_fail_streak=0
        wifi_probe_loop_count=0
    fi

    [ "$wifi_score" -lt 0 ] && wifi_score=0
    [ "$wifi_score" -gt 100 ] && wifi_score=100

    if [ -n "$wifi_latency_score" ] && echo "$wifi_latency_score" | grep -Eq '^[0-9]+$'; then
        wifi_score=$(awk -v b="$wifi_score" -v l="$wifi_latency_score" 'BEGIN{v=(b*80 + l*20)/100; if(v<0) v=0; if(v>100) v=100; printf "%d", v}')
    fi

    wifi_quality_reason="$(get_reason_from_score "$wifi_score")"
    wifi_details="link=$wifi_link ip=$wifi_ip egress=$wifi_egress reason=$wifi_path_reason quality=$wifi_quality_reason rssi=${wifi_rssi_dbm:--} latency_ms=${wifi_latency_ms:--} latency_ema_ms=${wifi_latency_ema_ms:--} latency_score=${wifi_latency_score:--} probe=$wifi_probe_ok bssid=${wifi_bssid:-} band=${wifi_band:-} chan=${wifi_chan:-} freq=${wifi_freq:-} width=${wifi_width:-} width_source=${wifi_width_source:-} width_confidence=${wifi_width_confidence:-} caps=${wifi_caps:-}"
}

daemon_run_wifi_transport_cycle() {
    if [ "$transport" = "wifi" ]; then
        wifi_composite="$wifi_score"
        wifi_composite_ema_val=$(composite_ema "$wifi_composite" "$MODDIR/cache/composite.wifi.ema")

        WIFI_SPEED_THRESHOLD=${WIFI_SPEED_THRESHOLD:-75}
        case "$WIFI_SPEED_THRESHOLD" in ''|*[!0-9]* ) WIFI_SPEED_THRESHOLD=75;; esac

        profile="stable"
        if [ "$wifi_score" -ge "$WIFI_SPEED_THRESHOLD" ]; then
            profile="speed"
        fi

        if [ -f "$POLICY_DIR/decide_profile.sh" ]; then
            wifi_reason="$wifi_path_reason"
            policy_choice=$(
                ( . "$POLICY_DIR/decide_profile.sh" && pick_profile "$wifi_state" "$WIFI_IFACE" "$wifi_reason" "$wifi_details" "${LAST_EVENT_FILE}" ) 2>/dev/null
            )
            [ -n "$policy_choice" ] && profile="$policy_choice"
        fi

        AUTO_REQUEST_FILE="$MODDIR/cache/policy.auto_request"
        printf '%s' "$profile" > "$AUTO_REQUEST_FILE" 2>/dev/null || true

        if [ -f "$MODDIR/cache/target.override.active" ]; then
            log_debug "target override active; skipping auto wifi profile write"
            composite="$wifi_composite"
            composite_ema_val="$wifi_composite_ema_val"
            rsrp=""; rsrp_score=0
            sinr=""; sinr_score=0
            return 0
        fi

        POLICY_REQUEST_FILE="$MODDIR/cache/policy.request"
        prev_profile=""
        [ -f "$POLICY_REQUEST_FILE" ] && prev_profile=$(cat "$POLICY_REQUEST_FILE" 2>/dev/null || echo "")
        if [ "$profile" != "$prev_profile" ]; then
            printf '%s' "$profile" > "$POLICY_REQUEST_FILE" 2>/dev/null || true
            emit_event "PROFILE_CHANGED" "from=$prev_profile to=$profile transport=wifi wifi_score=$wifi_score wifi_quality=$wifi_quality_reason rssi_dbm=${wifi_rssi_dbm:--} ema=$wifi_composite_ema_val"
        fi

        composite="$wifi_composite"
        composite_ema_val="$wifi_composite_ema_val"
        rsrp=""; rsrp_score=0
        sinr=""; sinr_score=0
    fi
}
