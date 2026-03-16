#!/system/bin/sh

wifi_cycle_trace() {
    command -v core_daemon_trace >/dev/null 2>&1 || return 0
    core_daemon_trace "wifi_cycle: $*"
}

network__wifi__latency_percentile() {
    local samples_file="$1" percentile="$2"
    local sample_count rank

    [ -f "$samples_file" ] || return 1
    case "$percentile" in
        ''|*[!0-9]* ) return 1 ;;
    esac
    [ "$percentile" -ge 1 ] || percentile=1
    [ "$percentile" -le 100 ] || percentile=100

    sample_count="$(grep -Ec '^[0-9]+$' "$samples_file" 2>/dev/null || echo 0)"
    case "$sample_count" in ''|*[!0-9]* ) sample_count=0 ;; esac
    [ "$sample_count" -gt 0 ] || return 1

    rank=$(( (sample_count * percentile + 99) / 100 ))
    [ "$rank" -lt 1 ] && rank=1
    [ "$rank" -gt "$sample_count" ] && rank="$sample_count"

    awk '/^[0-9]+$/{print $1}' "$samples_file" 2>/dev/null | sort -n | awk -v r="$rank" 'NR==r{print; exit}'
}

network__wifi__numeric_window_append() {
    local samples_file="$1" value="$2" max_samples="$3" tmp_file

    case "$value" in ''|*[!0-9]* ) return 0 ;; esac
    case "$max_samples" in ''|*[!0-9]* ) max_samples=120 ;; esac
    [ "$max_samples" -lt 20 ] && max_samples=20

    tmp_file="$samples_file.tmp.$$"
    {
        [ -f "$samples_file" ] && awk '/^[0-9]+$/{print $1}' "$samples_file" 2>/dev/null
        printf '%s\n' "$value"
    } | awk -v m="$max_samples" 'NF{buf[NR]=$0} END{start=NR-m+1; if(start<1) start=1; for(i=start;i<=NR;i++) if(buf[i] ~ /^[0-9]+$/) print buf[i]}' > "$tmp_file"
    mv "$tmp_file" "$samples_file" 2>/dev/null || true
}

network__wifi__latency_window_update() {
    local latency_ms="$1"
    local samples_file max_samples

    case "$latency_ms" in ''|*[!0-9]* ) return 0 ;; esac

    samples_file="$MODDIR/cache/wifi.latency.samples"
    max_samples="${WIFI_LATENCY_WINDOW_SAMPLES:-120}"
    case "$max_samples" in ''|*[!0-9]* ) max_samples=120 ;; esac
    [ "$max_samples" -lt 20 ] && max_samples=20

    network__wifi__numeric_window_append "$samples_file" "$latency_ms" "$max_samples"

    wifi_latency_p95_ms="$(network__wifi__latency_percentile "$samples_file" 95 2>/dev/null || true)"
    wifi_latency_p99_ms="$(network__wifi__latency_percentile "$samples_file" 99 2>/dev/null || true)"
}

network__wifi__jitter_window_update() {
    local jitter_ms="$1"
    local samples_file max_samples

    case "$jitter_ms" in ''|*[!0-9]* ) return 0 ;; esac

    samples_file="$MODDIR/cache/wifi.jitter.samples"
    max_samples="${WIFI_JITTER_WINDOW_SAMPLES:-120}"
    case "$max_samples" in ''|*[!0-9]* ) max_samples=120 ;; esac
    [ "$max_samples" -lt 20 ] && max_samples=20

    network__wifi__numeric_window_append "$samples_file" "$jitter_ms" "$max_samples"
    wifi_jitter_p95_ms="$(network__wifi__latency_percentile "$samples_file" 95 2>/dev/null || true)"
    wifi_jitter_p99_ms="$(network__wifi__latency_percentile "$samples_file" 99 2>/dev/null || true)"
}

network__wifi__loss_trend_update() {
    local loss_pct="$1"
    local samples_file max_samples sample_count

    case "$loss_pct" in ''|*[!0-9]* ) return 0 ;; esac

    samples_file="$MODDIR/cache/wifi.loss.samples"
    max_samples="${WIFI_LOSS_TREND_WINDOW_SAMPLES:-60}"
    case "$max_samples" in ''|*[!0-9]* ) max_samples=60 ;; esac
    [ "$max_samples" -lt 20 ] && max_samples=20

    network__wifi__numeric_window_append "$samples_file" "$loss_pct" "$max_samples"

    sample_count="$(grep -Ec '^[0-9]+$' "$samples_file" 2>/dev/null || echo 0)"
    case "$sample_count" in ''|*[!0-9]* ) sample_count=0 ;; esac
    if [ "$sample_count" -lt 6 ]; then
        wifi_loss_trend_pct=""
        return 0
    fi

    wifi_loss_trend_pct="$(awk '/^[0-9]+$/{a[++n]=$1} END {
        if (n < 6) exit 0
        split = int(n / 2)
        if (split < 1) split = 1
        sum1 = 0; c1 = 0
        for (i = 1; i <= split; i++) { sum1 += a[i]; c1++ }
        sum2 = 0; c2 = 0
        for (i = split + 1; i <= n; i++) { sum2 += a[i]; c2++ }
        if (c1 == 0 || c2 == 0) exit 0
        d = (sum2 / c2) - (sum1 / c1)
        if (d >= 0) printf "+%.0f", d
        else printf "%.0f", d
    }' "$samples_file" 2>/dev/null)"
}

network__wifi__read_selector_state() {
    local state_file="$1"

    selector_last_profile=""
    selector_last_bssid=""
    selector_last_switch_ts=0
    selector_candidate_profile=""
    selector_candidate_streak=0

    [ -f "$state_file" ] || return 0

    selector_last_profile=$(awk -F= '$1=="last_profile" {print substr($0, index($0,"=")+1)}' "$state_file" 2>/dev/null | tail -n1)
    selector_last_bssid=$(awk -F= '$1=="last_bssid" {print substr($0, index($0,"=")+1)}' "$state_file" 2>/dev/null | tail -n1)
    selector_last_switch_ts=$(awk -F= '$1=="last_switch_ts" {print substr($0, index($0,"=")+1)}' "$state_file" 2>/dev/null | tail -n1)
    selector_candidate_profile=$(awk -F= '$1=="candidate_profile" {print substr($0, index($0,"=")+1)}' "$state_file" 2>/dev/null | tail -n1)
    selector_candidate_streak=$(awk -F= '$1=="candidate_streak" {print substr($0, index($0,"=")+1)}' "$state_file" 2>/dev/null | tail -n1)

    case "$selector_last_switch_ts" in ''|*[!0-9]* ) selector_last_switch_ts=0 ;; esac
    case "$selector_candidate_streak" in ''|*[!0-9]* ) selector_candidate_streak=0 ;; esac
}

network__wifi__write_selector_state() {
    local state_file="$1"
    {
        printf 'last_profile=%s\n' "${selector_last_profile:-stable}"
        printf 'last_bssid=%s\n' "${selector_last_bssid:-}"
        printf 'last_switch_ts=%s\n' "${selector_last_switch_ts:-0}"
        printf 'candidate_profile=%s\n' "${selector_candidate_profile:-}"
        printf 'candidate_streak=%s\n' "${selector_candidate_streak:-0}"
    } | atomic_write "$state_file"
}

# -----------------------------------------------------------------------
# Auto-trigger channel scan when WiFi quality is sustained low
# -----------------------------------------------------------------------
network__wifi__channel_scan_trigger() {
    local current_score="$1" current_band="$2"
    local state_file="$MODDIR/cache/channel_scan_auto.state"
    local low_score_streak=0 last_scan_ts=0 now min_interval_sec score_threshold streak_required
    local pairing_ok=0
    
    # Read pairing state
    if [ -f "$MODDIR/cache/pairing.state" ]; then
        pairing_ok=$(awk -F= '$1=="paired" && $2==1 {print 1; exit}' "$MODDIR/cache/pairing.state" 2>/dev/null || echo 0)
    fi
    
    # Only auto-scan if paired
    [ "$pairing_ok" -eq 0 ] && return 0
    
    # Only scan 2.4GHz and 5GHz (skip 6GHz for now)
    case "$current_band" in
        2g|5g) ;;
        *) return 0 ;;
    esac
    
    # Configuration
    score_threshold="${CHANNEL_SCAN_THRESHOLD:-65}"
    streak_required="${CHANNEL_SCAN_STREAK:-3}"
    min_interval_sec="${CHANNEL_SCAN_MIN_INTERVAL_SEC:-300}"  # 5 minutes
    
    # Read state
    if [ -f "$state_file" ]; then
        low_score_streak=$(awk -F= '$1=="low_score_streak" {print $2}' "$state_file" 2>/dev/null || echo 0)
        last_scan_ts=$(awk -F= '$1=="last_scan_ts" {print $2}' "$state_file" 2>/dev/null || echo 0)
    fi
    
    case "$low_score_streak" in ''|*[!0-9]* ) low_score_streak=0 ;; esac
    case "$last_scan_ts" in ''|*[!0-9]* ) last_scan_ts=0 ;; esac
    case "$current_score" in ''|*[!0-9]* ) return 0 ;; esac
    
    now=$(date +%s 2>/dev/null || echo 0)
    case "$now" in ''|*[!0-9]* ) now=0 ;; esac
    [ "$now" -eq 0 ] && return 0
    
    # Update streak
    if [ "$current_score" -lt "$score_threshold" ]; then
        low_score_streak=$((low_score_streak + 1))
    else
        # Score improved, reset streak
        low_score_streak=0
        printf 'low_score_streak=0\nlast_scan_ts=%s\n' "$last_scan_ts" > "$state_file"
        return 0
    fi
    
    # Check if we meet trigger conditions
    if [ "$low_score_streak" -ge "$streak_required" ]; then
        # Check rate-limit
        elapsed=$((now - last_scan_ts))
        if [ "$elapsed" -ge "$min_interval_sec" ]; then
            log_info "channel_scan_auto_trigger score=$current_score streak=$low_score_streak band=$current_band"
            
            # Execute channel scan
            if command -v network__router__channel_recommend_request >/dev/null 2>&1; then
                network__router__channel_recommend_request "$current_band" 0 >/dev/null 2>&1 &
            fi
            
            # Reset streak and update timestamp
            low_score_streak=0
            last_scan_ts="$now"
        fi
    fi
    
    # Write updated state
    printf 'low_score_streak=%s\nlast_scan_ts=%s\n' "$low_score_streak" "$last_scan_ts" > "$state_file"
}

network__wifi__cycle() {
    wifi_cycle_trace "before get_wifi_status"
    wifi_readout="$(get_wifi_status)"
    wifi_cycle_trace "after get_wifi_status readout=$wifi_readout"
    wifi_link="DOWN"; wifi_ip=0; wifi_egress=0
    wifi_path_reason="link_down"
    wifi_rssi_dbm=""
    wifi_rssi_score=""
    wifi_latency_ms=""
    wifi_latency_ema_ms=""
    wifi_latency_p95_ms=""
    wifi_latency_p99_ms=""
    wifi_latency_score=""
    wifi_jitter_ms=""
    wifi_jitter_p95_ms=""
    wifi_jitter_p99_ms=""
    wifi_jitter_score=""
    wifi_loss_pct=""
    wifi_loss_trend_pct=""
    wifi_loss_score=""
    wifi_bssid=""; wifi_band=""; wifi_caps=""; wifi_freq=""; wifi_chan=""; wifi_ssid=""; wifi_width=""
    wifi_width_source=""; wifi_width_confidence=""; wifi_standard=""
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
                export ROUTER_INFER_WIDTH_2G
                wifi_cycle_trace "before get_wifi_extended_info iface=$WIFI_IFACE"
                wifi_extended_info="$(get_wifi_extended_info "$WIFI_IFACE")"
                wifi_cycle_trace "after get_wifi_extended_info info=$wifi_extended_info source=${WIFI_INFO_SOURCE:-unknown}"
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
                            wifi_standard=*) wifi_standard="${kv#wifi_standard=}" ;;
                        esac
                    done
                    if [ -z "$wifi_width" ] && [ "$wifi_band" = "2g" ]; then
                        infer2g_flag="${ROUTER_INFER_WIDTH_2G:-0}"
                        if [ "$infer2g_flag" -ne 1 ] && [ -x /system/bin/getprop ]; then
                            case "$(/system/bin/getprop persist.kitsunping.router.infer_width_2g 2>/dev/null || true)" in
                                1|true|TRUE|yes|YES|on|ON) infer2g_flag=1 ;;
                            esac
                        fi
                        if [ "$infer2g_flag" -eq 1 ]; then
                            wifi_width="20"
                            wifi_width_source="inferred"
                            wifi_width_confidence="low"
                        fi
                    fi
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
                    wifi_cycle_trace "before tests_network target=${NET_PROBE_TARGET:-8.8.8.8}"
                    if tests_network; then
                        wifi_cycle_trace "after tests_network rc=0 rtt=${NET_LAST_RTT_MS:-} jitter=${NET_LAST_JITTER_MS:-} loss=${NET_LAST_LOSS_PCT:-}"
                        wifi_probe_ok=1
                        wifi_probe_fail_streak=0
                        if [ -n "${NET_LAST_RTT_MS:-}" ] && echo "$NET_LAST_RTT_MS" | grep -Eq '^[0-9]+$'; then
                            wifi_latency_ms="$NET_LAST_RTT_MS"
                            wifi_latency_score="$(score_wifi_latency "$wifi_latency_ms")"
                            network__wifi__latency_window_update "$wifi_latency_ms"
                            if [ -n "$wifi_latency_ms" ]; then
                                wifi_latency_ema_ms="$(composite_ema "$wifi_latency_ms" "$MODDIR/cache/wifi.rtt.ema")"
                            fi
                        fi
                        if [ -n "${NET_LAST_JITTER_MS:-}" ] && echo "$NET_LAST_JITTER_MS" | grep -Eq '^[0-9]+$'; then
                            wifi_jitter_ms="$NET_LAST_JITTER_MS"
                            wifi_jitter_score="$(score_wifi_jitter "$wifi_jitter_ms")"
                            network__wifi__jitter_window_update "$wifi_jitter_ms"
                        fi
                        if [ -n "${NET_LAST_LOSS_PCT:-}" ] && echo "$NET_LAST_LOSS_PCT" | grep -Eq '^[0-9]+$'; then
                            wifi_loss_pct="$NET_LAST_LOSS_PCT"
                            wifi_loss_score="$(score_wifi_loss "$wifi_loss_pct")"
                            network__wifi__loss_trend_update "$wifi_loss_pct"
                        fi
                    else
                        wifi_cycle_trace "after tests_network rc=1"
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
    if [ -n "$wifi_jitter_score" ] && echo "$wifi_jitter_score" | grep -Eq '^[0-9]+$'; then
        wifi_score=$(awk -v b="$wifi_score" -v j="$wifi_jitter_score" 'BEGIN{v=(b*90 + j*10)/100; if(v<0) v=0; if(v>100) v=100; printf "%d", v}')
    fi
    if [ -n "$wifi_loss_score" ] && echo "$wifi_loss_score" | grep -Eq '^[0-9]+$'; then
        wifi_score=$(awk -v b="$wifi_score" -v l="$wifi_loss_score" 'BEGIN{v=(b*85 + l*15)/100; if(v<0) v=0; if(v>100) v=100; printf "%d", v}')
    fi

    wifi_quality_reason="$(get_reason_from_score "$wifi_score")"
    wifi_details="link=$wifi_link ip=$wifi_ip egress=$wifi_egress reason=$wifi_path_reason quality=$wifi_quality_reason rssi=${wifi_rssi_dbm:--} latency_ms=${wifi_latency_ms:--} latency_ema_ms=${wifi_latency_ema_ms:--} latency_p95_ms=${wifi_latency_p95_ms:--} latency_p99_ms=${wifi_latency_p99_ms:--} latency_score=${wifi_latency_score:--} jitter_ms=${wifi_jitter_ms:--} jitter_p95_ms=${wifi_jitter_p95_ms:--} jitter_p99_ms=${wifi_jitter_p99_ms:--} jitter_score=${wifi_jitter_score:--} loss_pct=${wifi_loss_pct:--} loss_trend_pct=${wifi_loss_trend_pct:--} loss_score=${wifi_loss_score:--} probe=$wifi_probe_ok bssid=${wifi_bssid:-} band=${wifi_band:-} chan=${wifi_chan:-} freq=${wifi_freq:-} width=${wifi_width:-} width_source=${wifi_width_source:-} width_confidence=${wifi_width_confidence:-} caps=${wifi_caps:-}"
}

network__wifi__transport_cycle() {
    if [ "$transport" = "wifi" ]; then
        wifi_composite="$wifi_score"
        wifi_composite_ema_val=$(composite_ema "$wifi_composite" "$MODDIR/cache/composite.wifi.ema")

        WIFI_SELECTOR_STATE_FILE="$MODDIR/cache/wifi.selector.state"

        WIFI_SPEED_UP_THRESHOLD=${WIFI_SPEED_UP_THRESHOLD:-${WIFI_SPEED_THRESHOLD:-75}}
        case "$WIFI_SPEED_UP_THRESHOLD" in ''|*[!0-9]* ) WIFI_SPEED_UP_THRESHOLD=75;; esac

        WIFI_SPEED_DOWN_THRESHOLD=${WIFI_SPEED_DOWN_THRESHOLD:-$((WIFI_SPEED_UP_THRESHOLD - 8))}
        case "$WIFI_SPEED_DOWN_THRESHOLD" in ''|*[!0-9]* ) WIFI_SPEED_DOWN_THRESHOLD=$((WIFI_SPEED_UP_THRESHOLD - 8));; esac
        if [ "$WIFI_SPEED_DOWN_THRESHOLD" -gt "$WIFI_SPEED_UP_THRESHOLD" ]; then
            WIFI_SPEED_DOWN_THRESHOLD="$WIFI_SPEED_UP_THRESHOLD"
        fi
        [ "$WIFI_SPEED_DOWN_THRESHOLD" -lt 1 ] && WIFI_SPEED_DOWN_THRESHOLD=1

        WIFI_SWITCH_MIN_HOLD_SEC=${WIFI_SWITCH_MIN_HOLD_SEC:-45}
        case "$WIFI_SWITCH_MIN_HOLD_SEC" in ''|*[!0-9]* ) WIFI_SWITCH_MIN_HOLD_SEC=45;; esac

        WIFI_SWITCH_STREAK_REQUIRED=${WIFI_SWITCH_STREAK_REQUIRED:-2}
        case "$WIFI_SWITCH_STREAK_REQUIRED" in ''|*[!0-9]* ) WIFI_SWITCH_STREAK_REQUIRED=2;; esac
        [ "$WIFI_SWITCH_STREAK_REQUIRED" -lt 1 ] && WIFI_SWITCH_STREAK_REQUIRED=1

        # Save baseline so band adjustment doesn't compound across daemon cycles
        _wifi_up_base="$WIFI_SPEED_UP_THRESHOLD"
        _wifi_down_base="$WIFI_SPEED_DOWN_THRESHOLD"
        _wifi_streak_base="$WIFI_SWITCH_STREAK_REQUIRED"

        # L2.5: band-aware hysteresis — on 2.4GHz raise score thresholds and streak
        # requirement to reduce flip-flop in congested environments.
        # Tuneable via WIFI_BAND_2G_UP_ADJ (default 7) and WIFI_BAND_2G_STREAK_ADJ (default 1).
        case "${wifi_band:-}" in
            2g)
                _band_up_adj="${WIFI_BAND_2G_UP_ADJ:-7}"
                case "$_band_up_adj" in ''|*[!0-9]* ) _band_up_adj=7 ;; esac
                _band_streak_adj="${WIFI_BAND_2G_STREAK_ADJ:-1}"
                case "$_band_streak_adj" in ''|*[!0-9]* ) _band_streak_adj=1 ;; esac
                WIFI_SPEED_UP_THRESHOLD=$((WIFI_SPEED_UP_THRESHOLD + _band_up_adj))
                WIFI_SPEED_DOWN_THRESHOLD=$((WIFI_SPEED_DOWN_THRESHOLD + _band_up_adj))
                [ "$WIFI_SPEED_DOWN_THRESHOLD" -gt "$WIFI_SPEED_UP_THRESHOLD" ] && WIFI_SPEED_DOWN_THRESHOLD="$WIFI_SPEED_UP_THRESHOLD"
                [ "$WIFI_SPEED_DOWN_THRESHOLD" -lt 1 ] && WIFI_SPEED_DOWN_THRESHOLD=1
                WIFI_SWITCH_STREAK_REQUIRED=$((WIFI_SWITCH_STREAK_REQUIRED + _band_streak_adj))
                ;;
        esac

        POLICY_REQUEST_FILE="$MODDIR/cache/policy.request"
        POLICY_CURRENT_FILE="$MODDIR/cache/policy.current"
        prev_profile=""
        [ -f "$POLICY_REQUEST_FILE" ] && prev_profile=$(cat "$POLICY_REQUEST_FILE" 2>/dev/null || echo "")
        [ -z "$prev_profile" ] && [ -f "$POLICY_CURRENT_FILE" ] && prev_profile=$(cat "$POLICY_CURRENT_FILE" 2>/dev/null || echo "")
        [ -z "$prev_profile" ] && prev_profile="stable"

        # App-override guard: when an app override is active the gaming/benchmark profile
        # was written to policy.request by the app, not by the wifi selector. Treat it as
        # "stable" so (a) policy.auto_request reflects real wifi quality and (b) the hold
        # timer resets — enabling a fast restore once the override is released.
        if [ -f "$MODDIR/cache/target.override.active" ]; then
            case "$prev_profile" in
                gaming|benchmark|benchmark_gaming|benchmark_speed)
                    prev_profile="stable"
                    selector_last_switch_ts=0
                    ;;
            esac
        fi

        network__wifi__read_selector_state "$WIFI_SELECTOR_STATE_FILE"
        [ -z "$selector_last_profile" ] && selector_last_profile="$prev_profile"

        # L2.5: boot profile hold guard — treat the boot profile write timestamp as a
        # recent switch so the dynamic cycle respects WIFI_SWITCH_MIN_HOLD_SEC after boot.
        _boot_ts_file="$MODDIR/cache/policy.boot.ts"
        if [ -f "$_boot_ts_file" ]; then
            _boot_ts="$(cat "$_boot_ts_file" 2>/dev/null || echo 0)"
            case "$_boot_ts" in ''|*[!0-9]* ) _boot_ts=0 ;; esac
            [ "$_boot_ts" -gt "${selector_last_switch_ts:-0}" ] && selector_last_switch_ts="$_boot_ts"
        fi

        profile="$prev_profile"
        selector_preferred_profile="$prev_profile"
        if [ "$wifi_score" -ge "$WIFI_SPEED_UP_THRESHOLD" ]; then
            selector_preferred_profile="speed"
        elif [ "$wifi_score" -lt "$WIFI_SPEED_DOWN_THRESHOLD" ]; then
            selector_preferred_profile="stable"
        fi

        # L2.5: probe_ok guard — do not promote to speed if last network probe failed.
        if [ "$selector_preferred_profile" = "speed" ] && [ "${wifi_probe_ok:-1}" -eq 0 ]; then
            selector_preferred_profile="${prev_profile:-stable}"
        fi

        selector_now_ts="$(now_epoch)"
        case "$selector_now_ts" in ''|*[!0-9]* ) selector_now_ts=0 ;; esac
        selector_elapsed_since_switch=$((selector_now_ts - selector_last_switch_ts))
        [ "$selector_elapsed_since_switch" -lt 0 ] && selector_elapsed_since_switch=0

        if [ "$selector_preferred_profile" != "$prev_profile" ]; then
            if [ "$selector_candidate_profile" = "$selector_preferred_profile" ]; then
                selector_candidate_streak=$((selector_candidate_streak + 1))
            else
                selector_candidate_profile="$selector_preferred_profile"
                selector_candidate_streak=1
            fi

            if [ "$selector_candidate_streak" -ge "$WIFI_SWITCH_STREAK_REQUIRED" ] && [ "$selector_elapsed_since_switch" -ge "$WIFI_SWITCH_MIN_HOLD_SEC" ]; then
                profile="$selector_preferred_profile"
                selector_last_switch_ts="$selector_now_ts"
                selector_candidate_profile=""
                selector_candidate_streak=0
            fi
        else
            selector_candidate_profile=""
            selector_candidate_streak=0
        fi

        selector_last_profile="$profile"
        selector_last_bssid="${wifi_bssid:-}"
        network__wifi__write_selector_state "$WIFI_SELECTOR_STATE_FILE"

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
            WIFI_SPEED_UP_THRESHOLD="$_wifi_up_base"
            WIFI_SPEED_DOWN_THRESHOLD="$_wifi_down_base"
            WIFI_SWITCH_STREAK_REQUIRED="$_wifi_streak_base"
            return 0
        fi

        prev_profile=""
        [ -f "$POLICY_REQUEST_FILE" ] && prev_profile=$(cat "$POLICY_REQUEST_FILE" 2>/dev/null || echo "")
        if [ "$profile" != "$prev_profile" ]; then
            printf '%s' "$profile" > "$POLICY_REQUEST_FILE" 2>/dev/null || true
            emit_event "PROFILE_CHANGED" "from=$prev_profile to=$profile transport=wifi wifi_score=$wifi_score wifi_quality=$wifi_quality_reason band=${wifi_band:--} probe_ok=${wifi_probe_ok:-1} rssi_dbm=${wifi_rssi_dbm:--} latency_ms=${wifi_latency_ms:--} latency_p95_ms=${wifi_latency_p95_ms:--} latency_p99_ms=${wifi_latency_p99_ms:--} jitter_ms=${wifi_jitter_ms:--} jitter_p95_ms=${wifi_jitter_p95_ms:--} jitter_p99_ms=${wifi_jitter_p99_ms:--} loss_pct=${wifi_loss_pct:--} loss_trend_pct=${wifi_loss_trend_pct:--} ema=$wifi_composite_ema_val up=$WIFI_SPEED_UP_THRESHOLD down=$WIFI_SPEED_DOWN_THRESHOLD hold_s=$WIFI_SWITCH_MIN_HOLD_SEC streak_req=$WIFI_SWITCH_STREAK_REQUIRED"
        fi

        WIFI_SPEED_UP_THRESHOLD="$_wifi_up_base"
        WIFI_SPEED_DOWN_THRESHOLD="$_wifi_down_base"
        WIFI_SWITCH_STREAK_REQUIRED="$_wifi_streak_base"
        composite="$wifi_composite"
        composite_ema_val="$wifi_composite_ema_val"
        rsrp=""; rsrp_score=0
        sinr=""; sinr_score=0
        
        # Auto-trigger channel scan if quality is sustained low
        if command -v network__wifi__channel_scan_trigger >/dev/null 2>&1; then
            network__wifi__channel_scan_trigger "$wifi_score" "$wifi_band"
        fi
        
        # M4: Check if notification should be sent for better channel availability
        if command -v network__wifi__channel_notification_check >/dev/null 2>&1; then
            case "$wifi_chan" in ''|*[!0-9]*|0) ;; *)
                network__wifi__channel_notification_check "$wifi_chan" >/dev/null 2>&1 || true
            ;; esac
        fi
    fi
}

network_wifi_cycle() {
    network__wifi__cycle "$@"
}

network_wifi_transport_cycle() {
    network__wifi__transport_cycle "$@"
}
