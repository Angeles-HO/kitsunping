#!/system/bin/sh

network__mobile__cycle() {
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

network__mobile__transport_cycle() {
    if [ "$transport" = "mobile" ]; then
        signal_loop_count=$((signal_loop_count + 1))
        if [ "$signal_loop_count" -ge "$SIGNAL_POLL_INTERVAL" ]; then
            signal_loop_count=0
            signal_info=$(get_native_mobile_signal_quality 2>/dev/null || true)
            if [ -z "$signal_info" ]; then
                command -v runtime_profiler_snapshot_miss >/dev/null 2>&1 && runtime_profiler_snapshot_miss
                command -v runtime_profiler_fallback >/dev/null 2>&1 && runtime_profiler_fallback
                signal_info=$(get_signal_quality)
            else
                command -v runtime_profiler_snapshot_hit >/dev/null 2>&1 && runtime_profiler_snapshot_hit
                # The native signal payload replaces the direct telephony
                # registry dump; parser work remains intentionally uncounted.
                kitsunpingd_metrics_record "mobile_signal" 0 0 1 0
            fi
            echo "$signal_info" | atomic_write "$MODDIR/cache/signal_quality.json"

            signal_score=""
            signal_source=""
            native_rsrp_score=""
            native_sinr_score=""
            rsrp=""
            sinr=""
            if [ -n "$JQ_BIN" ]; then
                signal_score=$(echo "$signal_info" | "$JQ_BIN" -r 'try .quality_score // empty' 2>/dev/null)
                rsrp=$(echo "$signal_info" | "$JQ_BIN" -r 'try .rsrp_dbm // empty' 2>/dev/null)
                sinr=$(echo "$signal_info" | "$JQ_BIN" -r 'try .sinr_db // empty' 2>/dev/null)
                signal_source=$(echo "$signal_info" | "$JQ_BIN" -r 'try .source // empty' 2>/dev/null)
                native_rsrp_score=$(echo "$signal_info" | "$JQ_BIN" -r 'try .rsrp_score // empty' 2>/dev/null)
                native_sinr_score=$(echo "$signal_info" | "$JQ_BIN" -r 'try .sinr_score // empty' 2>/dev/null)
            else
                signal_score=$(echo "$signal_info" | awk -F: '/quality_score/ {gsub(/[^0-9-\.]/,"",$2); print $2; exit}')
                rsrp=$(echo "$signal_info" | awk -F: '/rsrp_dbm/ {gsub(/[^0-9-\.]/,"",$2); print $2; exit}')
                sinr=$(echo "$signal_info" | awk -F: '/sinr_db/ {gsub(/[^0-9-\.]/,"",$2); print $2; exit}')
                signal_source=$(echo "$signal_info" | awk -F'"' '/"source"/ {print $4; exit}')
                native_rsrp_score=$(echo "$signal_info" | awk -F: '/"rsrp_score"/ {gsub(/[^0-9-]/,"",$2); print $2; exit}')
                native_sinr_score=$(echo "$signal_info" | awk -F: '/"sinr_score"/ {gsub(/[^0-9-]/,"",$2); print $2; exit}')
            fi

            rsrp_score=0
            sinr_score=0
            if [ "$signal_source" = "kitsunpingd" ] && echo "$native_rsrp_score" | grep -Eq '^[0-9]+$'; then
                rsrp_score="$native_rsrp_score"
            elif [ -n "$rsrp" ]; then
                rsrp_score=$(score_rsrp_cached "$rsrp")
            fi
            if [ "$signal_source" = "kitsunpingd" ] && echo "$native_sinr_score" | grep -Eq '^[0-9]+$'; then
                sinr_score="$native_sinr_score"
            elif [ -n "$sinr" ]; then
                sinr_score=$(score_sinr_cached "$sinr")
            fi

            # SINR scoring already reflects poor/negative values via score_sinr_cached.
            # Do not apply an additional fixed penalty here to avoid double punishment.

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

            AUTO_REQUEST_FILE="$MODDIR/cache/policy.auto_request"
            printf '%s' "$profile" > "$AUTO_REQUEST_FILE" 2>/dev/null || true

            if [ -f "$MODDIR/cache/target.override.active" ]; then
                log_debug "target override active; skipping auto mobile profile write"
                # shellcheck disable=SC2104
                continue
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

network_mobile_cycle() {
    network__mobile__cycle "$@"
}

network_mobile_transport_cycle() {
    network__mobile__transport_cycle "$@"
}
