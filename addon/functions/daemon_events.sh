#!/system/bin/sh
# Event and router identity helpers for daemon.sh

get_router_paired_flag() {
    local raw
    raw="$(getprop persist.kitsunrouter.paired)"
    case "${raw:-}" in
        1|true|TRUE|yes|YES|on|ON) printf '1' ;;
        *) printf '0' ;;
    esac
}

## Write event to JSON file
## Usage: write_event_json $1 = "event_name" $2 = "timestamp" $3 = "details"
## e.g., write_event_json "WIFI_LEFT" 1620000000 "iface=wlan0 link=DOWN ip=0 egress=0 reason=link_down"
write_event_json() {
    local name="$1" ts="$2" details jsonfile="$LAST_EVENT_JSON"
    details="$(json_escape "$3")"

    cat <<EOF | atomic_write "$jsonfile"
{"event":"$name","ts":$ts,"details":"$details","iface":"$current_iface","wifi_state":"$wifi_state","wifi_score":$wifi_score}
EOF
}

## Determine if event should be emitted based on debounce time
## Usage: should_emit_event "event_name"
## Returns 0 (true) if event should be emitted, 1 (false) otherwise
should_emit_event() {
    local name="$1" now last_var last_ts diff

    # Global kill-switch for event emission
    [ "${EMIT_EVENTS:-1}" -eq 0 ] && return 1

    # Explicit user requests should always trigger immediately.
    [ "$name" = "$EV_USER_REQUESTED_START" ] && return 0
    [ "$name" = "$EV_USER_REQUESTED_RESTART" ] && return 0
    [ "$name" = "$EV_USER_REQUESTED_CALIBRATE" ] && return 0
    [ "$name" = "$EV_REQUEST_PROFILE" ] && return 0

    now=$(now_epoch)
    case "$now" in
        ''|*[!0-9]*) now=0 ;;
    esac

    # If debounce is unset/invalid, don't suppress events.
    case "${EVENT_DEBOUNCE_SEC:-}" in
        ''|*[!0-9]*) return 0 ;;
    esac

    last_var="LAST_TS_${name}"
    eval "last_ts=\${$last_var:-0}"
    case "$last_ts" in
        ''|*[!0-9]*) last_ts=0 ;;
    esac

    diff=$((now - last_ts))
    # If time went backwards or is equal, allow emission.
    [ "$diff" -lt 0 ] && diff="$EVENT_DEBOUNCE_SEC"

    if [ "$diff" -ge "$EVENT_DEBOUNCE_SEC" ]; then
        eval "$last_var=$now"
        return 0
    fi
    return 1
}

should_direct_broadcast() {
    # Purpose: allow daemon events to reach the APK immediately (without waiting for polling).
    # Priority: env DAEMON_DIRECT_BROADCAST > persist.kitsunping.direct_broadcast > default enabled.
    local raw
    raw="${DAEMON_DIRECT_BROADCAST:-}"
    if [ -z "$raw" ]; then
        raw="$(getprop persist.kitsunping.direct_broadcast 2>/dev/null | tr -d '\r\n')"
    fi
    [ -z "$raw" ] && raw=1

    case "$raw" in
        0|false|FALSE|no|NO|off|OFF) return 1 ;;
    esac
    return 0
}

broadcast_event_to_apk() {
    # Purpose: optional low-latency app update channel.
    # Sends the same event context already persisted in LAST_EVENT_JSON.
    local name="$1" ts="$2" details="$3" payload

    should_direct_broadcast || return 0
    command -v am >/dev/null 2>&1 || return 0

    payload=$(cat "$LAST_EVENT_JSON" 2>/dev/null | tr -d '\n')
    [ -n "$payload" ] || return 0

    am broadcast -a com.kitsunping.ACTION_UPDATE -p app.kitsunping \
        --es payload "$payload" \
        --es event "$name" \
        --es ts "$ts" \
        --es details "$details" \
        >/dev/null 2>&1
}

## Emit an event (debounced) and notify executor
## Usage: emit_event "EVENT_NAME" "details"
emit_event() {
    local name="$1" details="$2" now
    now=$(now_epoch)

    if should_emit_event "$name"; then
        EVENT_SEQ=$(( ${EVENT_SEQ:-0} + 1 ))
        log_info "EVENT #$EVENT_SEQ $name ts=$now $details"
        write_event_json "$name" "$now" "$details"

        if ! printf '%s %s %s\n' "$name" "$now" "$details" | atomic_write "$LAST_EVENT_FILE"; then
            log_error "Failed to write LAST_EVENT_FILE"
        fi

        if [ -x "$EXECUTOR_SH" ]; then
            EVENT_NAME="$name" \
            EVENT_TS="$now" \
            EVENT_DETAILS="$details" \
            LOG_DIR="$LOG_DIR" \
            POLICY_LOG="$POLICY_LOG" \
            "$EXECUTOR_SH" >> "$POLICY_LOG" 2>&1 &
        else
            log_error "EXECUTOR not executable: $EXECUTOR_SH"
        fi
        # DONE: Optional direct broadcast to APK (action com.kitsunping.ACTION_UPDATE with event/ts)
        broadcast_event_to_apk "$name" "$now" "$details"
    else
        log_debug "EVENT suppressed by debounce: $name"
    fi
}

handle_router_identity_change_unpair() {
    local old_sig="$1" new_sig="$2" bssid="$3"
    local paired_prop ts
    paired_prop="$(getprop persist.kitsunrouter.paired)"
    case "$paired_prop" in
        1|true|TRUE|yes|YES|on|ON) ;;
        *) return 0 ;;
    esac

    ts="$(now_epoch)"

    if [ -n "$RESET_PROP_BIN" ]; then
        "$RESET_PROP_BIN" persist.kitsunrouter.paired 0 >/dev/null 2>&1 || setprop persist.kitsunrouter.paired 0
    else
        setprop persist.kitsunrouter.paired 0
    fi

    cat <<EOF | atomic_write "$ROUTER_PAIRING_CACHE_FILE"
{"router_ip":"","token":"","router_id":"","paired":false,"updated_ts":${ts:-0},"reason":"router_identity_changed"}
EOF

    emit_event "$EV_ROUTER_UNPAIRED" "reason=router_changed bssid=$bssid from=${old_sig:-none} to=${new_sig:-none}"
    log_info "router pairing reset due identity change: from=${old_sig:-none} to=${new_sig:-none}"
}

# TODO: consider adding rate-limiting to this function to prevent rapid unpairing in edge cases (e.g., unstable Wi-Fi causing frequent DNI changes)
# TODO: detect group confidence level, add count when the device joined on same bssid, if joined_bssid > 10, agrupate as "high confidence it's the same router even if DNI changed due to e.g. channel width inference change", so can going forward, if DNI changes but bssid is the same and confidence is high, don't unpair, just update DNI and emit event with reason "DNI changed but high confidence same router"
verify_router_identity_on_wifi_join() {
    local bssid="$1" band="$2" chan="$3" freq="$4" width="$5" width_source="$6" width_confidence="$7" caps="$8"
    local wifi_vendor router_width_for_sig router_sig router_cache_cur emit_reason router_dni_prev_short router_dni_new_short

    [ "${ROUTER_EXPERIMENTAL:-0}" -eq 1 ] || return 0
    [ "${KITSUNROUTER_ENABLE:-0}" -eq 1 ] || return 0

    if [ -z "$bssid" ]; then
        router_debug_log "router_dni_skip_missing_data bssid=${bssid:-} caps=${caps:-}"
        return 0
    fi

    if [ -z "$caps" ] && [ "$band" = "2g" ]; then
        caps="legacy_2g"
    fi

    wifi_vendor="$(detect_router_vendor "$bssid")"
    router_width_for_sig="$width"
    if [ "${width_source:-}" = "inferred" ]; then
        router_width_for_sig=""
    fi

    router_sig="$(build_router_signature "$bssid" "$band" "$chan" "$freq" "$router_width_for_sig" "$caps")"
    if [ -f "$ROUTER_DNI_FILE" ]; then
        router_cache_cur=$(cat "$ROUTER_DNI_FILE" 2>/dev/null | tr -d '\r\n')
    else
        router_cache_cur=""
    fi

    if [ "$router_cache_cur" = "$router_sig" ]; then
        emit_reason="same_dni"
    else
        handle_router_identity_change_unpair "$router_cache_cur" "$router_sig" "$bssid"
        printf '%s\n' "$router_sig" | atomic_write "$ROUTER_DNI_FILE"
        printf '%s\n' "$router_sig" | atomic_write "$ROUTER_LAST_FILE"
        router_dni_prev_short="none"
        [ -n "$router_cache_cur" ] && router_dni_prev_short="$(router_dni_short "$router_cache_cur")"
        router_dni_new_short="$(router_dni_short "$router_sig")"
        emit_event "$EV_ROUTER_DNI_CHANGED" "vendor=$wifi_vendor bssid=$bssid from=${router_cache_cur:-none} to=$router_sig dni_prev=${router_dni_prev_short} dni_new=${router_dni_new_short} band=${band:-unknown} width=${width:-} width_source=${width_source:-unknown} width_confidence=${width_confidence:-unknown}"
        if [ "${ROUTER_OPENWRT_MODE:-0}" -eq 1 ] && should_emit_router_caps "$wifi_vendor" "$caps"; then
            emit_reason="changed_emit"
            emit_event "$EV_ROUTER_CAPS_DETECTED" "vendor=$wifi_vendor bssid=$bssid caps=$caps dni=${router_dni_new_short} band=${band:-unknown} width=${width:-} width_source=${width_source:-unknown} width_confidence=${width_confidence:-unknown}"
        else
            emit_reason="changed_cached_only"
        fi
    fi

    router_debug_log "router_dni_check reason=$emit_reason vendor=$wifi_vendor sig=$router_sig cache=$router_cache_cur"
}
