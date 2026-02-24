daemon_run_mobile_cycle() {
    mobile_iface="none"
    if [ "$current_iface" != "none" ] && [ "$current_iface" != "$WIFI_IFACE" ]; then
        case "$current_iface" in
            wl*|wifi*) mobile_iface="none" ;;
            *) mobile_iface="$current_iface" ;;
        esac
    fi
    mobile_readout="$(get_mobile_status "$mobile_iface")"
    mobile_link="DOWN"; mobile_ip=0; mobile_egress=0; mobile_reason="link_down"
    for kv in $mobile_readout; do
        case "$kv" in
            iface=*) mobile_iface="${kv#iface=}" ;;
            link=*) mobile_link="${kv#link=}" ;;
            ip=*) mobile_ip="${kv#ip=}" ;;
            egress=*) mobile_egress="${kv#egress=}" ;;
            reason=*) mobile_reason="${kv#reason=}" ;;
        esac
    done
    if [ "$mobile_link" != "$last_mobile_link" ] || [ "$mobile_ip" -ne "$last_mobile_ip" ] || [ "$mobile_egress" -ne "$last_mobile_egress" ]; then
        mobile_score="$(get_score "$mobile_link" "$mobile_ip" "$mobile_egress")"
        last_mobile_link="$mobile_link"
        last_mobile_ip="$mobile_ip"
        last_mobile_egress="$mobile_egress"
        last_mobile_score="$mobile_score"
    else
        mobile_score="$last_mobile_score"
    fi
    mobile_reason="$(get_reason_from_score "$mobile_score")"

    transport="none"
    if [ "$wifi_egress" -eq 1 ]; then
        transport="wifi"
    elif [ "$mobile_egress" -eq 1 ]; then
        transport="mobile"
    fi
}

daemon_run_mobile_transport_cycle() {
    if [ "$transport" = "mobile" ]; then
        signal_loop_count=$((signal_loop_count + 1))
        if [ "$signal_loop_count" -ge "$SIGNAL_POLL_INTERVAL" ]; then
            signal_loop_count=0
            signal_info=$(get_signal_quality)
            echo "$signal_info" | atomic_write "$MODDIR/cache/signal_quality.json"

            signal_score=""
            rsrp=""
            sinr=""
            if [ -n "$JQ_BIN" ]; then
                signal_score=$(echo "$signal_info" | "$JQ_BIN" -r 'try .quality_score // empty' 2>/dev/null)
                rsrp=$(echo "$signal_info" | "$JQ_BIN" -r 'try .rsrp_dbm // empty' 2>/dev/null)
                sinr=$(echo "$signal_info" | "$JQ_BIN" -r 'try .sinr_db // empty' 2>/dev/null)
            else
                signal_score=$(echo "$signal_info" | awk -F: '/quality_score/ {gsub(/[^0-9-\.]/,"",$2); print $2; exit}')
                rsrp=$(echo "$signal_info" | awk -F: '/rsrp_dbm/ {gsub(/[^0-9-\.]/,"",$2); print $2; exit}')
                sinr=$(echo "$signal_info" | awk -F: '/sinr_db/ {gsub(/[^0-9-\.]/,"",$2); print $2; exit}')
            fi

            rsrp_score=0
            sinr_score=0
            if [ -n "$rsrp" ]; then
                rsrp_score=$(score_rsrp_cached "$rsrp")
            fi
            if [ -n "$sinr" ]; then
                sinr_score=$(score_sinr_cached "$sinr")
            fi

            if printf '%s' "$sinr" | grep -Eq '^-?[0-9]+$' && [ "$sinr" -lt 0 ]; then
                log_debug "SINR negative (${sinr} dB), applying penalty to sinr_score=${sinr_score}"
                sinr_score=$(awk -v s="$sinr_score" 'BEGIN{p=s-10; if(p<0)p=0; printf "%.2f", p}')
            fi

            performance_score="$mobile_score"
            jitter_penalty=0

            composite=$(awk -v a="$LCL_ALPHA" -v b="$LCL_BETA" -v c="$LCL_GAMMA" -v r="$rsrp_score" -v s="$sinr_score" -v p="$performance_score" -v d="$LCL_DELTA" -v j="$jitter_penalty" 'BEGIN{v=a*r + b*s + c*p - d*j; if(v<0) v=0; if(v>100) v=100; printf "%.2f", v }')

            composite_ema_val=$(composite_ema "$composite" "$MODDIR/cache/composite.mobile.ema")
            profile=$(decide_profile "$composite_ema_val")

            if [ -f "$POLICY_DIR/decide_profile.sh" ]; then
                wifi_reason="$wifi_path_reason"
                policy_choice=$(
                    ( . "$POLICY_DIR/decide_profile.sh" && pick_profile "$wifi_state" "$WIFI_IFACE" "$wifi_reason" "$wifi_details" "${LAST_EVENT_FILE}" ) 2>/dev/null
                )
                [ -n "$policy_choice" ] && profile="$policy_choice"
            fi

            POLICY_REQUEST_FILE="$MODDIR/cache/policy.request"
            prev_profile=""
            [ -f "$POLICY_REQUEST_FILE" ] && prev_profile=$(cat "$POLICY_REQUEST_FILE" 2>/dev/null || echo "")
            if [ "$profile" != "$prev_profile" ]; then
                printf '%s' "$profile" > "$POLICY_REQUEST_FILE" 2>/dev/null || true
                emit_event "PROFILE_CHANGED" "from=$prev_profile to=$profile composite=$composite ema=$composite_ema_val rsrp=$rsrp rsrp_score=$rsrp_score sinr=$sinr sinr_score=$sinr_score"
            fi

            degraded_reason=""
            if printf '%s' "$composite" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
                if awk -v v="$composite" 'BEGIN{exit !(v>0 && v<40)}'; then
                    degraded_reason="composite"
                fi
            fi

            if [ -z "$degraded_reason" ] && echo "$signal_score" | grep -Eq '^[0-9]+$'; then
                if [ "$signal_score" -gt 0 ] && [ "$signal_score" -lt 40 ]; then
                    degraded_reason="rsrp"
                fi
            fi

            if [ -n "$degraded_reason" ]; then
                log_info "Poor signal detected ($degraded_reason) comp=$composite rsrp=$rsrp sinr=$sinr"
                emit_event "$EV_SIGNAL_DEGRADED" "reason=$degraded_reason comp=$composite rsrp=$rsrp sinr=$sinr iface=$mobile_iface"
            else
                log_debug "signal ok comp=$composite ema=$composite_ema_val rsrp_score=$rsrp_score sinr_score=$sinr_score"
            fi
        fi
    else
        signal_loop_count=0
    fi
}
