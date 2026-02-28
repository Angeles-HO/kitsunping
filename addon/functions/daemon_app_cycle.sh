daemon_run_app_event_cycle() {
    app_event="$(getprop "$APP_EVENT_PROP" 2>/dev/null | tr -d '\r\n')"
    app_event_data="$(getprop "$APP_EVENT_DATA_PROP" 2>/dev/null | tr -d '\r\n')"
    if [ -n "$app_event" ]; then
        case "$app_event" in
            "$EV_USER_REQUESTED_START")
                log_info "app_event=$app_event"
                emit_event "$EV_USER_REQUESTED_START" "source=app_intermediary"
                ;;
            "$EV_USER_REQUESTED_CALIBRATE")
                log_info "app_event=$app_event"
                emit_event "$EV_USER_REQUESTED_CALIBRATE" "source=app_intermediary"
                ;;
            "$EV_USER_REQUESTED_RESTART")
                log_info "app_event=$app_event"
                emit_event "$EV_USER_REQUESTED_RESTART" "source=app_intermediary"
                ;;
            "$EV_REQUEST_PROFILE")
                profile_target="$app_event_data"
                case "$profile_target" in
                    stable|speed|gaming)
                        POLICY_REQUEST_FILE="$MODDIR/cache/policy.request"
                        prev_profile=""
                        [ -f "$POLICY_REQUEST_FILE" ] && prev_profile=$(cat "$POLICY_REQUEST_FILE" 2>/dev/null || echo "")
                        printf '%s' "$profile_target" > "$POLICY_REQUEST_FILE" 2>/dev/null || true
                        log_info "app_event=$app_event target=$profile_target"
                        emit_event "$EV_REQUEST_PROFILE" "source=app_intermediary to=$profile_target from=${prev_profile:-unknown}"
                        ;;
                    *)
                        log_warning "Invalid profile target in $APP_EVENT_DATA_PROP: ${profile_target:-empty}"
                        ;;
                esac
                ;;
            *)
                log_warning "Unknown app event in $APP_EVENT_PROP: $app_event"
                ;;
        esac

        if command_exists resetprop; then
            resetprop "$APP_EVENT_PROP" "" >/dev/null 2>&1 || true
            resetprop "$APP_EVENT_DATA_PROP" "" >/dev/null 2>&1 || true
        else
            setprop "$APP_EVENT_PROP" "" >/dev/null 2>&1 || true
            setprop "$APP_EVENT_DATA_PROP" "" >/dev/null 2>&1 || true
        fi
    fi
}

normalize_target_token() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

target_prop_lookup_profile() {
    local pkg_raw="$1" target_file line key val profile priority token map
    local old_ifs

    pkg_raw="$(normalize_target_token "$pkg_raw")"
    [ -n "$pkg_raw" ] || return 1

    target_file="$MODDIR/target.prop"
    [ -f "$target_file" ] || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        line="$(printf '%s' "$line" | sed 's/[[:space:]]*#.*$//')"
        line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -z "$line" ] && continue

        case "$line" in
            *=*) ;;
            *) continue ;;
        esac

        key="${line%%=*}"
        val="${line#*=}"
        key="$(normalize_target_token "$key")"
        val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

        [ "$key" = "$pkg_raw" ] || continue

        profile=""
        priority=""
        old_ifs="$IFS"
        IFS=','
        set -- $val
        IFS="$old_ifs"

        for token in "$@"; do
            map="$(normalize_target_token "$token")"
            case "$map" in
                gaming|speed|stable)
                    [ -z "$profile" ] && profile="$map"
                    ;;
                high|medium|low)
                    [ -z "$priority" ] && priority="$map"
                    ;;
            esac
        done

        [ -n "$profile" ] || return 1
        [ -n "$priority" ] || priority="medium"
        printf '%s,%s' "$profile" "$priority"
        return 0
    done < "$target_file"

    return 1
}

daemon_detect_foreground_package() {
    local out pkg

    out="$(dumpsys window windows 2>/dev/null | grep -m 1 -E 'mCurrentFocus|mFocusedApp')"
    pkg="$(printf '%s\n' "$out" | sed -n 's/.* u[0-9][0-9]* \([^ /}][^ /}]*\)\/.*/\1/p' | head -n 1)"

    if [ -z "$pkg" ]; then
        out="$(dumpsys activity activities 2>/dev/null | grep -m 1 -E 'mResumedActivity|topResumedActivity|ResumedActivity')"
        pkg="$(printf '%s\n' "$out" | sed -n 's/.* \([[:alnum:]_.][[:alnum:]_.]*\)\/.*/\1/p' | head -n 1)"
    fi

    pkg="$(printf '%s' "$pkg" | tr -d '\r\n')"
    printf '%s' "$pkg"
}

target_request_emit_allowed() {
    local emit_sig="$1" now_ts cooldown_raw cooldown_sec
    local ts_file sig_file last_ts last_sig elapsed

    ts_file="$MODDIR/cache/target.request.last.ts"
    sig_file="$MODDIR/cache/target.request.last.sig"

    cooldown_raw="$(getprop persist.kitsunping.target_request_cooldown_sec 2>/dev/null | tr -d '\r\n')"
    case "$cooldown_raw" in
        ''|*[!0-9]*) cooldown_sec=8 ;;
        *) cooldown_sec="$cooldown_raw" ;;
    esac

    now_ts="$(date +%s 2>/dev/null || echo 0)"
    case "$now_ts" in
        ''|*[!0-9]*) now_ts=0 ;;
    esac

    last_ts=0
    [ -f "$ts_file" ] && last_ts="$(cat "$ts_file" 2>/dev/null || echo 0)"
    case "$last_ts" in
        ''|*[!0-9]*) last_ts=0 ;;
    esac

    last_sig=""
    [ -f "$sig_file" ] && last_sig="$(cat "$sig_file" 2>/dev/null || echo "")"

    if [ "$emit_sig" = "$last_sig" ] && [ "$cooldown_sec" -gt 0 ] && [ "$now_ts" -gt 0 ] && [ "$last_ts" -gt 0 ]; then
        elapsed=$((now_ts - last_ts))
        [ "$elapsed" -lt 0 ] && elapsed=0
        if [ "$elapsed" -lt "$cooldown_sec" ]; then
            return 1
        fi
    fi

    printf '%s' "$now_ts" > "$ts_file" 2>/dev/null || true
    printf '%s' "$emit_sig" > "$sig_file" 2>/dev/null || true
    return 0
}

daemon_run_target_profile_cycle() {
    local enabled_raw enabled pkg mapping profile priority policy_request_file prev_profile
    local last_app_file last_profile_file auto_profile_file override_file auto_profile
    local override_state current_profile

    enabled_raw="$(getprop persist.kitsunping.target_prop_enable 2>/dev/null | tr -d '\r\n')"
    case "$enabled_raw" in
        0|false|FALSE|no|NO|off|OFF) enabled=0 ;;
        *) enabled=1 ;;
    esac
    [ "$enabled" -eq 1 ] || return 0

    policy_request_file="$MODDIR/cache/policy.request"
    auto_profile_file="$MODDIR/cache/policy.auto_request"
    override_file="$MODDIR/cache/target.override.active"
    last_app_file="$MODDIR/cache/target.last_app"
    last_profile_file="$MODDIR/cache/target.last_profile"

    pkg="$(daemon_detect_foreground_package)"
    if [ -z "$pkg" ]; then
        if [ -f "$override_file" ]; then
            auto_profile=""
            [ -f "$auto_profile_file" ] && auto_profile="$(cat "$auto_profile_file" 2>/dev/null || echo "")"
            case "$auto_profile" in
                stable|speed|gaming)
                    prev_profile=""
                    [ -f "$policy_request_file" ] && prev_profile="$(cat "$policy_request_file" 2>/dev/null || echo "")"
                    if [ "$auto_profile" != "$prev_profile" ]; then
                        printf '%s' "$auto_profile" > "$policy_request_file" 2>/dev/null || true
                        if target_request_emit_allowed "release:none:$auto_profile"; then
                            emit_event "$EV_REQUEST_PROFILE" "source=target.prop_release package=none to=$auto_profile from=${prev_profile:-unknown}"
                        else
                            log_debug "target.prop release emit suppressed by cooldown (package=none to=$auto_profile)"
                        fi
                    fi
                    ;;
            esac
            rm -f "$override_file" "$last_app_file" "$last_profile_file" 2>/dev/null || true
            log_info "target.prop release: no foreground app, fallback to auto profile=${auto_profile:-unknown}"
        fi
        return 0
    fi

    mapping="$(target_prop_lookup_profile "$pkg")"
    if [ -z "$mapping" ]; then
        if [ -f "$override_file" ]; then
            auto_profile=""
            [ -f "$auto_profile_file" ] && auto_profile="$(cat "$auto_profile_file" 2>/dev/null || echo "")"
            case "$auto_profile" in
                stable|speed|gaming)
                    prev_profile=""
                    [ -f "$policy_request_file" ] && prev_profile="$(cat "$policy_request_file" 2>/dev/null || echo "")"
                    if [ "$auto_profile" != "$prev_profile" ]; then
                        printf '%s' "$auto_profile" > "$policy_request_file" 2>/dev/null || true
                        if target_request_emit_allowed "release:$pkg:$auto_profile"; then
                            emit_event "$EV_REQUEST_PROFILE" "source=target.prop_release package=$pkg to=$auto_profile from=${prev_profile:-unknown}"
                        else
                            log_debug "target.prop release emit suppressed by cooldown (package=$pkg to=$auto_profile)"
                        fi
                    fi
                    ;;
            esac
            rm -f "$override_file" "$last_app_file" "$last_profile_file" 2>/dev/null || true
            log_info "target.prop release: package=$pkg not mapped, fallback to auto profile=${auto_profile:-unknown}"
        fi
        return 0
    fi

    profile="${mapping%%,*}"
    priority="${mapping#*,}"
    case "$profile" in
        stable|speed|gaming) ;;
        *) return 0 ;;
    esac

    prev_profile=""
    [ -f "$policy_request_file" ] && prev_profile="$(cat "$policy_request_file" 2>/dev/null || echo "")"
    current_profile=""
    [ -f "$MODDIR/cache/policy.current" ] && current_profile="$(cat "$MODDIR/cache/policy.current" 2>/dev/null || echo "")"

    if [ ! -f "$last_app_file" ] || [ "$(cat "$last_app_file" 2>/dev/null)" != "$pkg" ]; then
        printf '%s' "$pkg" > "$last_app_file" 2>/dev/null || true
        log_info "target.prop app=$pkg profile=$profile priority=$priority"
    fi

    if [ "$profile" != "$prev_profile" ] || [ "$profile" != "$current_profile" ]; then
        printf '%s' "$profile" > "$policy_request_file" 2>/dev/null || true
        printf '%s' "$profile" > "$last_profile_file" 2>/dev/null || true
        if target_request_emit_allowed "target:$pkg:$profile"; then
            emit_event "$EV_REQUEST_PROFILE" "source=target.prop package=$pkg priority=$priority to=$profile from=${prev_profile:-unknown} current=${current_profile:-unknown}"
        else
            log_debug "target.prop emit suppressed by cooldown (package=$pkg to=$profile)"
        fi
    fi

    override_state="$pkg,$profile"
    if [ ! -f "$override_file" ] || [ "$(cat "$override_file" 2>/dev/null)" != "$override_state" ]; then
        printf '%s' "$override_state" > "$override_file" 2>/dev/null || true
    fi
}

daemon_run_pairing_sync_cycle() {
    if [ "${KITSUNROUTER_ENABLE:-0}" -eq 1 ]; then
        router_paired_now="$(get_router_paired_flag)"
        if [ "$router_paired_now" != "$last_router_paired" ]; then
            if [ "$router_paired_now" = "1" ]; then
                emit_event "$EV_ROUTER_PAIRED" "source=app_intermediary paired=1"
            else
                emit_event "$EV_ROUTER_UNPAIRED" "source=app_intermediary paired=0"
            fi
            last_router_paired="$router_paired_now"
        fi
    fi
}

read_pairing_json_field() {
    local key="$1" file="$2"
    local value_raw
    [ -f "$file" ] || { printf ''; return 0; }

    if command -v jq >/dev/null 2>&1; then
        jq -r ".${key} // empty" "$file" 2>/dev/null || true
        return 0
    fi

    value_raw="$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" 2>/dev/null | head -n1)"
    if [ -n "$value_raw" ]; then
        printf '%s' "$value_raw"
        return 0
    fi

    value_raw="$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p" "$file" 2>/dev/null | head -n1 | tr -d '\"[:space:]')"
    case "$value_raw" in
        true|false|null|[0-9]*)
            printf '%s' "$value_raw"
            ;;
    esac
}

daemon_get_wifi_client_mac() {
    local iface mac
    iface="${WIFI_IFACE:-wlan0}"
    case "$iface" in
        ''|none) iface="wlan0" ;;
    esac

    if [ -r "/sys/class/net/$iface/address" ]; then
        mac="$(cat "/sys/class/net/$iface/address" 2>/dev/null | tr 'A-Z' 'a-z' | tr -d '\r\n')"
        case "$mac" in
            [0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f])
                printf '%s' "$mac"
                return 0
                ;;
        esac
    fi

    printf ''
}

router_send_module_status() {
    local payload="$1" router_ip="$2" token="$3"

    if command -v curl >/dev/null 2>&1; then
        curl -fsS --connect-timeout 2 --max-time 5 \
            -H "Content-Type: application/json" \
            -H "X-Auth-Token: $token" \
            -X POST \
            -d "$payload" \
            "http://$router_ip/cgi-bin/router-event" >/dev/null 2>&1
        return $?
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -q -O /dev/null \
            --timeout=5 \
            --header="Content-Type: application/json" \
            --header="X-Auth-Token: $token" \
            --post-data="$payload" \
            "http://$router_ip/cgi-bin/router-event" >/dev/null 2>&1
        return $?
    fi

    return 127
}

daemon_run_router_status_push_cycle() {
    local paired_flag cache_file router_ip token router_id cache_paired now_ts min_interval
    local last_push_file last_push_ts elapsed payload bssid ssid band width profile_current profile_target transport client_mac

    [ "${KITSUNROUTER_ENABLE:-0}" -eq 1 ] || return 0

    paired_flag="$(get_router_paired_flag)"
    [ "$paired_flag" = "1" ] || return 0

    cache_file="$ROUTER_PAIRING_CACHE_FILE"
    [ -f "$cache_file" ] || return 0

    router_ip="$(read_pairing_json_field "router_ip" "$cache_file")"
    token="$(read_pairing_json_field "token" "$cache_file")"
    router_id="$(read_pairing_json_field "router_id" "$cache_file")"
    cache_paired="$(read_pairing_json_field "paired" "$cache_file")"

    case "${cache_paired:-}" in
        true|1|"1"|"true"|TRUE|yes|YES|on|ON) ;;
        *) return 0 ;;
    esac

    [ -n "$router_ip" ] || return 0
    [ -n "$token" ] || return 0

    now_ts="$(date +%s 2>/dev/null || echo 0)"
    min_interval="${ROUTER_STATUS_PUSH_INTERVAL_SEC:-15}"
    case "$min_interval" in ''|*[!0-9]* ) min_interval=15 ;; esac
    [ "$min_interval" -le 0 ] && min_interval=15

    last_push_file="$MODDIR/cache/router.status.last_push.ts"
    last_push_ts=0
    if [ -f "$last_push_file" ]; then
        last_push_ts="$(cat "$last_push_file" 2>/dev/null || echo 0)"
    fi
    case "$last_push_ts" in ''|*[!0-9]* ) last_push_ts=0 ;; esac

    elapsed=$((now_ts - last_push_ts))
    [ "$elapsed" -lt 0 ] && elapsed=0
    [ "$elapsed" -lt "$min_interval" ] && return 0

    bssid="${wifi_bssid:-}"
    ssid="${wifi_ssid:-}"
    band="${wifi_band:-}"
    width="${wifi_width:-}"
    profile_current="$(cat "$MODDIR/cache/policy.current" 2>/dev/null || echo "")"
    profile_target="$(cat "$MODDIR/cache/policy.target" 2>/dev/null || echo "")"
    transport="${transport:-unknown}"
    client_mac="$(daemon_get_wifi_client_mac)"

    payload=$(cat <<EOF
{"event":"MODULE_STATUS","ts":$now_ts,"paired":true,"router_id":"${router_id:-router}","client_mac":"${client_mac:-}","bssid":"$bssid","ssid":"$ssid","band":"$band","width":"$width","profile_current":"$profile_current","profile_target":"$profile_target","transport":"$transport","wifi_state":"${wifi_state:-unknown}","wifi_score":"${wifi_score:-0}","last_event":"${last_event:-}"}
EOF
)

    if router_send_module_status "$payload" "$router_ip" "$token"; then
        printf '%s\n' "$now_ts" | atomic_write "$last_push_file"
        log_debug "router_status_push ok ip=$router_ip transport=$transport"
    else
        log_warning "router_status_push failed ip=$router_ip (module cannot confirm pair-status)"
    fi
}
