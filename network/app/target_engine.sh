#!/system/bin/sh
# target_engine.sh — foreground app detection → target.prop lookup → policy.request write.
# This is the SOLE authority that writes policy.request (profile decisions).
# Robustness rule: local profile switching works regardless of router/pairing state.
# Sourced by cycle.sh. MODDIR must be set. Depends on: state_io.sh, pairing_gate.sh.

# -----------------------------------------------------------------------
# KPI session helpers
# -----------------------------------------------------------------------

network__app__kpi_session_marker_clear() {
    local marker_file
    marker_file="$MODDIR/cache/kpi.app_override.marker"
    rm -f "$marker_file" 2>/dev/null || true
}

network__app__kpi_reset_for_app_session() {
    local pkg="$1" profile="$2"
    local marker_file marker current_marker

    case "$profile" in
        gaming|benchmark|benchmark_gaming|benchmark_speed) ;;
        *) return 0 ;;
    esac

    marker_file="$MODDIR/cache/kpi.app_override.marker"
    marker="${pkg},${profile}"
    current_marker=""
    [ -f "$marker_file" ] && current_marker="$(cat "$marker_file" 2>/dev/null || echo '')"
    [ "$current_marker" = "$marker" ] && return 0

    rm -f \
        "$MODDIR/cache/wifi.latency.samples" \
        "$MODDIR/cache/wifi.jitter.samples"  \
        "$MODDIR/cache/wifi.loss.samples"    \
        2>/dev/null || true

    printf '%s' "$marker" > "$marker_file" 2>/dev/null || true
    log_info "kpi reset for app session package=$pkg profile=$profile"
}

# -----------------------------------------------------------------------
# target.prop cache: checksum → parse → fast lookup
# -----------------------------------------------------------------------

network__app__target_prop_checksum() {
    local target_file="$1"

    [ -f "$target_file" ] || { printf ''; return 1; }

    if command -v sha1sum >/dev/null 2>&1; then
        sha1sum "$target_file" 2>/dev/null | awk '{print $1}'
        return 0
    fi

    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$target_file" 2>/dev/null | awk '{print $1}'
        return 0
    fi

    cksum "$target_file" 2>/dev/null | awk '{print $1":"$2}'
    return 0
}

network__app__target_prop_refresh_cache() {
    local target_file cache_dir cache_file hash_file tmp_file
    local current_hash previous_hash line key val profile priority token map legacy_mode old_ifs

    target_file="$MODDIR/target.prop"
    cache_dir="$MODDIR/cache"
    cache_file="$cache_dir/target.prop.cache"
    hash_file="$cache_dir/target.prop.hash"
    tmp_file="$cache_dir/target.prop.cache.tmp"

    [ -f "$target_file" ] || {
        rm -f "$cache_file" "$hash_file" "$tmp_file" 2>/dev/null || true
        return 1
    }

    mkdir -p "$cache_dir" 2>/dev/null || true

    current_hash="$(network__app__target_prop_checksum "$target_file" 2>/dev/null || true)"
    [ -n "$current_hash" ] || return 1

    previous_hash=""
    [ -f "$hash_file" ] && previous_hash="$(cat "$hash_file" 2>/dev/null || echo '')"

    if [ "$current_hash" = "$previous_hash" ] && [ -f "$cache_file" ]; then
        return 0
    fi

    : > "$tmp_file" 2>/dev/null || return 1

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
        key="$(network__app__normalize_target_token "$key")"
        val="$(printf '%s' "$val" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"

        [ -n "$key" ] || continue

        profile=""
        priority=""
        legacy_mode=1
        old_ifs="$IFS"
        IFS=','
        set -- $val
        IFS="$old_ifs"

        for token in "$@"; do
            map="$(printf '%s' "$token" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/[[:space:]]*:[[:space:]]*/:/g')"
            case "$map" in
                profile:gaming|profile:speed|profile:stable|profile:benchmark|profile:benchmark_gaming|profile:benchmark_speed)
                    profile="${map#profile:}"
                    legacy_mode=0
                    ;;
                priority:high|priority:medium|priority:low)
                    priority="${map#priority:}"
                    legacy_mode=0
                    ;;
                gaming|speed|stable|benchmark|benchmark_gaming|benchmark_speed)
                    if [ "$legacy_mode" -eq 1 ] && [ -z "$profile" ]; then
                        profile="$map"
                    fi
                    ;;
                high|medium|low)
                    if [ "$legacy_mode" -eq 1 ] && [ -z "$priority" ]; then
                        priority="$map"
                    fi
                    ;;
            esac
        done

        [ -n "$profile" ] || continue
        [ "$profile" = "benchmark" ] && profile="benchmark_gaming"
        [ -n "$priority" ] || priority="medium"
        printf '%s=%s,%s\n' "$key" "$profile" "$priority" >> "$tmp_file"
    done < "$target_file"

    mv "$tmp_file" "$cache_file" 2>/dev/null || return 1
    printf '%s' "$current_hash" > "$hash_file" 2>/dev/null || true
    return 0
}

network__app__target_prop_lookup_profile() {
    local pkg_raw="$1" cache_file line key val

    pkg_raw="$(network__app__normalize_target_token "$pkg_raw")"
    [ -n "$pkg_raw" ] || return 1

    network__app__target_prop_refresh_cache || return 1

    cache_file="$MODDIR/cache/target.prop.cache"
    [ -f "$cache_file" ] || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in *=*) ;; *) continue ;; esac
        key="${line%%=*}"
        val="${line#*=}"
        key="$(network__app__normalize_target_token "$key")"
        [ "$key" = "$pkg_raw" ] || continue
        printf '%s' "$val"
        return 0
    done < "$cache_file"

    return 1
}

# -----------------------------------------------------------------------
# Foreground package detection
# -----------------------------------------------------------------------

network__app__detect_foreground_package() {
    local out pkg pkg_win pkg_act

    out="$(dumpsys window windows 2>/dev/null | grep -m 1 -E 'mCurrentFocus|mFocusedApp')"
    pkg_win="$(printf '%s\n' "$out" | sed -n 's/.* u[0-9][0-9]* \([^ /}][^ /}]*\)\/.*/\1/p' | head -n 1)"

    out="$(dumpsys activity activities 2>/dev/null | grep -m 1 -E 'mResumedActivity|topResumedActivity|ResumedActivity')"
    pkg_act="$(printf '%s\n' "$out" | sed -n 's/.* \([[:alnum:]_.][[:alnum:]_.]*\)\/.*/\1/p' | head -n 1)"

    pkg_win="$(printf '%s' "$pkg_win" | tr -d '\r\n')"
    pkg_act="$(printf '%s' "$pkg_act" | tr -d '\r\n')"

    case "$pkg_win" in
        ""|com.android.systemui|com.miui.home|com.android.launcher|com.android.launcher3|com.sec.android.app.launcher|com.google.android.apps.nexuslauncher)
            pkg="$pkg_act"
            ;;
        *)
            pkg="$pkg_win"
            ;;
    esac

    [ -z "$pkg" ] && pkg="$pkg_act"

    pkg="$(printf '%s' "$pkg" | tr -d '\r\n')"
    printf '%s' "$pkg"
}

# -----------------------------------------------------------------------
# Stability & cooldown guards
# -----------------------------------------------------------------------

network__app__target_app_is_stable() {
    local pkg_key="$1" now_ts="$2" stable_sec="$3"
    local candidate_pkg_file candidate_ts_file candidate_pkg candidate_ts elapsed

    [ "$stable_sec" -le 0 ] && return 0

    candidate_pkg_file="$MODDIR/cache/target.fg.candidate.pkg"
    candidate_ts_file="$MODDIR/cache/target.fg.candidate.ts"

    candidate_pkg=""
    [ -f "$candidate_pkg_file" ] && candidate_pkg="$(cat "$candidate_pkg_file" 2>/dev/null || echo '')"

    if [ "$candidate_pkg" != "$pkg_key" ]; then
        printf '%s' "$pkg_key" > "$candidate_pkg_file" 2>/dev/null || true
        printf '%s' "$now_ts"  > "$candidate_ts_file"  2>/dev/null || true
        return 1
    fi

    candidate_ts=0
    [ -f "$candidate_ts_file" ] && candidate_ts="$(cat "$candidate_ts_file" 2>/dev/null || echo 0)"
    case "$candidate_ts" in ''|*[!0-9]*) candidate_ts=0 ;; esac
    case "$now_ts"       in ''|*[!0-9]*) now_ts=0       ;; esac
    [ "$now_ts" -gt 0 ]        || return 1
    [ "$candidate_ts" -gt 0 ]  || return 1

    elapsed=$((now_ts - candidate_ts))
    [ "$elapsed" -lt 0 ] && elapsed=0
    [ "$elapsed" -ge "$stable_sec" ]
}

network__app__target_change_cooldown_ok() {
    local now_ts="$1" cooldown_sec="$2"
    local last_change_file last_change_ts elapsed

    [ "$cooldown_sec" -le 0 ] && return 0

    last_change_file="$MODDIR/cache/target.profile_change.last.ts"
    last_change_ts=0
    [ -f "$last_change_file" ] && last_change_ts="$(cat "$last_change_file" 2>/dev/null || echo 0)"
    case "$last_change_ts" in ''|*[!0-9]*) last_change_ts=0 ;; esac
    case "$now_ts"          in ''|*[!0-9]*) now_ts=0        ;; esac
    [ "$now_ts" -gt 0 ]           || return 0
    [ "$last_change_ts" -gt 0 ]   || return 0

    elapsed=$((now_ts - last_change_ts))
    [ "$elapsed" -lt 0 ] && elapsed=0
    [ "$elapsed" -ge "$cooldown_sec" ]
}

# -----------------------------------------------------------------------
# App-event cycle — bridge between the companion app and policy.request.
# Handles: profile request, calibrate/restart/start user events.
# -----------------------------------------------------------------------

network__app__event_cycle() {
    local app_event app_event_data profile_target prev_profile

    app_event="$(getprop "$APP_EVENT_PROP"      2>/dev/null | tr -d '\r\n')"
    app_event_data="$(getprop "$APP_EVENT_DATA_PROP" 2>/dev/null | tr -d '\r\n')"

    # Backward compatibility: consume legacy typoed props if primary props are empty.
    if [ -z "$app_event" ] && [ -n "${APP_EVENT_PROP_LEGACY:-}" ]; then
        app_event="$(getprop "$APP_EVENT_PROP_LEGACY" 2>/dev/null | tr -d '\r\n')"
    fi
    if [ -z "$app_event_data" ] && [ -n "${APP_EVENT_DATA_PROP_LEGACY:-}" ]; then
        app_event_data="$(getprop "$APP_EVENT_DATA_PROP_LEGACY" 2>/dev/null | tr -d '\r\n')"
    fi

    [ -n "$app_event" ] && log_info "event_cycle read app_event=$app_event data=${app_event_data:-empty}"

    [ -n "$app_event" ] || return 0

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
            [ "$profile_target" = "benchmark" ] && profile_target="benchmark_gaming"
            case "$profile_target" in
                stable|speed|gaming|benchmark_gaming|benchmark_speed)
                    prev_profile=""
                    [ -f "$MODDIR/cache/policy.request" ] && \
                        prev_profile=$(cat "$MODDIR/cache/policy.request" 2>/dev/null || echo "")
                    printf '%s' "$profile_target" > "$MODDIR/cache/policy.request" 2>/dev/null || true
                    network__app__policy_version_touch "$profile_target" "medium"
                    log_info "app_event=$app_event target=$profile_target"
                    emit_event "$EV_REQUEST_PROFILE" "source=app_intermediary to=$profile_target from=${prev_profile:-unknown}"
                    ;;
                *)
                    log_warning "Invalid profile target in $APP_EVENT_DATA_PROP: ${profile_target:-empty}"
                    ;;
            esac
            ;;
        "$EV_REQUEST_CHANNEL_SCAN")
            local band="$app_event_data"
            # Default to 2.4GHz if not specified or invalid
            case "$band" in
                2.4GHz|5GHz) ;;
                *) band="2.4GHz" ;;
            esac
            log_info "app_event=$app_event band=$band (force=1)"
            
            # Call channel request with force=1 (bypasses rate-limit and score threshold)
            if command -v network__router__channel_recommend_request >/dev/null 2>&1; then
                network__router__channel_recommend_request "$band" "1"
                emit_event "$EV_REQUEST_CHANNEL_SCAN" "source=app_intermediary band=$band"
            else
                log_warning "Channel recommendation not available (module not loaded)"
            fi
            ;;
        "$EV_REQUEST_CHANNEL_CHANGE")
            # Parse channel:band from app_event_data (e.g., "11:2g" or "36:5g")
            local channel_info="$app_event_data"
            local channel band
            
            channel="${channel_info%%:*}"
            band="${channel_info##*:}"
            
            # Validate channel is numeric
            case "$channel" in
                ''|*[!0-9]*)
                    log_warning "Invalid channel in channel_change_request: $channel"
                    ;;
                *)
                    # Validate band
                    case "$band" in
                        2g|5g) ;;
                        *)
                            log_warning "Invalid band in channel_change_request: $band"
                            band="2g" # fallback
                            ;;
                    esac
                    
                    log_info "app_event=$app_event channel=$channel band=$band"
                    
                    # Call channel apply function (P4)
                    if command -v network__router__channel_apply_request >/dev/null 2>&1; then
                        network__router__channel_apply_request "$band" "$channel"
                        emit_event "$EV_REQUEST_CHANNEL_CHANGE" "source=app_intermediary channel=$channel band=$band"
                    else
                        log_warning "Channel apply not available (module not loaded)"
                    fi
                    ;;
            esac
            ;;
        *)
            log_warning "Unknown app event in $APP_EVENT_PROP: $app_event"
            ;;
    esac

    if command_exists resetprop; then
        resetprop "$APP_EVENT_PROP"      "" >/dev/null 2>&1 || true
        resetprop "$APP_EVENT_DATA_PROP" "" >/dev/null 2>&1 || true
        [ -n "${APP_EVENT_PROP_LEGACY:-}" ] && resetprop "$APP_EVENT_PROP_LEGACY" "" >/dev/null 2>&1 || true
        [ -n "${APP_EVENT_DATA_PROP_LEGACY:-}" ] && resetprop "$APP_EVENT_DATA_PROP_LEGACY" "" >/dev/null 2>&1 || true
    else
        setprop "$APP_EVENT_PROP"      "" >/dev/null 2>&1 || true
        setprop "$APP_EVENT_DATA_PROP" "" >/dev/null 2>&1 || true
        [ -n "${APP_EVENT_PROP_LEGACY:-}" ] && setprop "$APP_EVENT_PROP_LEGACY" "" >/dev/null 2>&1 || true
        [ -n "${APP_EVENT_DATA_PROP_LEGACY:-}" ] && setprop "$APP_EVENT_DATA_PROP_LEGACY" "" >/dev/null 2>&1 || true
    fi
}

# -----------------------------------------------------------------------
# _release_override — internal helper called when override ends.
# Restores the auto profile and cleans override tracking files.
# -----------------------------------------------------------------------

_target_engine__release_override() {
    local pkg="$1" reason_tag="$2"
    local auto_profile_file override_file last_app_file last_profile_file
    local auto_profile prev_profile pkg_key now_ts stable_sec cooldown_sec
    local stable_raw cooldown_raw policy_request_file policy_request_priority_file

    auto_profile_file="$MODDIR/cache/policy.auto_request"
    override_file="$MODDIR/cache/target.override.active"
    last_app_file="$MODDIR/cache/target.last_app"
    last_profile_file="$MODDIR/cache/target.last_profile"
    policy_request_file="$MODDIR/cache/policy.request"
    policy_request_priority_file="$MODDIR/cache/policy.request.priority"

    now_ts="$(date +%s 2>/dev/null || echo 0)"
    case "$now_ts" in ''|*[!0-9]*) now_ts=0 ;; esac

    stable_raw="$(getprop persist.kitsunping.target_foreground_stable_sec 2>/dev/null | tr -d '\r\n')"
    case "$stable_raw" in ''|*[!0-9]*) stable_sec=3 ;; *) stable_sec="$stable_raw" ;; esac

    cooldown_raw="$(getprop persist.kitsunping.target_profile_change_cooldown_sec 2>/dev/null | tr -d '\r\n')"
    case "$cooldown_raw" in ''|*[!0-9]*) cooldown_sec=5 ;; *) cooldown_sec="$cooldown_raw" ;; esac

    auto_profile=""
    [ -f "$auto_profile_file" ] && auto_profile="$(cat "$auto_profile_file" 2>/dev/null || echo "")"
    # Normalize: manual benchmark/gaming overrides captured during override, or empty → stable
    case "$auto_profile" in
        gaming|benchmark|benchmark_gaming|benchmark_speed|'') auto_profile="stable" ;;
    esac

    case "$auto_profile" in
        stable|speed|gaming|benchmark_gaming|benchmark_speed)
            network__app__target_state_transition "NETWORK_DECISION" "${reason_tag}:auto=$auto_profile"
            prev_profile=""
            [ -f "$policy_request_file" ] && prev_profile="$(cat "$policy_request_file" 2>/dev/null || echo "")"
            if [ "$auto_profile" != "$prev_profile" ]; then
                pkg_key="${pkg:-none}"
                if ! network__app__target_app_is_stable "$pkg_key" "$now_ts" "$stable_sec"; then
                    log_debug "target.prop release skipped: foreground not stable pkg=$pkg_key stable_sec=$stable_sec"
                    return 0
                fi
                if ! network__app__target_change_cooldown_ok "$now_ts" "$cooldown_sec"; then
                    log_debug "target.prop release skipped: profile cooldown active cooldown_sec=$cooldown_sec"
                    return 0
                fi
                printf '%s' "$auto_profile" > "$policy_request_file"         2>/dev/null || true
                network__app__priority_apply_context "$auto_profile" "medium"
                printf '%s' "medium"        > "$policy_request_priority_file" 2>/dev/null || true
                network__app__policy_version_touch "$auto_profile" "medium"
                network__app__target_mark_profile_change "$now_ts"
                network__app__target_state_transition "POLICY_APPLIED" "${reason_tag}:profile=$auto_profile"
                emit_event "$EV_REQUEST_PROFILE" "source=target.prop_release package=${pkg:-none} to=$auto_profile from=${prev_profile:-unknown}"
            fi
            ;;
    esac

    rm -f "$override_file" "$last_app_file" "$last_profile_file" 2>/dev/null || true
    log_info "target.prop release: ${reason_tag} fallback to auto profile=${auto_profile:-unknown}"
}

# -----------------------------------------------------------------------
# Main profile decision engine — called every daemon tick.
# SINGLE writer of policy.request. Trace origin in every emit_event call.
# -----------------------------------------------------------------------

network__app__target_profile_cycle() {
    local enabled_raw enabled pkg mapping profile priority
    local policy_request_file policy_request_priority_file auto_profile_file override_file
    local last_app_file last_profile_file
    local request_profile current_profile prev_profile
    local now_ts stable_raw stable_sec cooldown_raw cooldown_sec pkg_key
    local override_state

    # ---- feature gate ----
    enabled_raw="$(getprop persist.kitsunping.target_prop_enable 2>/dev/null | tr -d '\r\n')"
    case "$enabled_raw" in
        0|false|FALSE|no|NO|off|OFF) enabled=0 ;;
        *) enabled=1 ;;
    esac
    if [ "$enabled" -ne 1 ]; then
        network__app__target_state_transition "IDLE" "target_prop_disabled"
        return 0
    fi

    # Pairing is enforced only for router-side actions (push/apply/scan).
    # target.prop keeps controlling local profile selection even when unpaired.

    # ---- timing config ----
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    case "$now_ts" in ''|*[!0-9]*) now_ts=0 ;; esac

    stable_raw="$(getprop persist.kitsunping.target_foreground_stable_sec 2>/dev/null | tr -d '\r\n')"
    case "$stable_raw" in ''|*[!0-9]*) stable_sec=3 ;; *) stable_sec="$stable_raw" ;; esac

    cooldown_raw="$(getprop persist.kitsunping.target_profile_change_cooldown_sec 2>/dev/null | tr -d '\r\n')"
    case "$cooldown_raw" in ''|*[!0-9]*) cooldown_sec=5 ;; *) cooldown_sec="$cooldown_raw" ;; esac

    policy_request_file="$MODDIR/cache/policy.request"
    policy_request_priority_file="$MODDIR/cache/policy.request.priority"
    auto_profile_file="$MODDIR/cache/policy.auto_request"
    override_file="$MODDIR/cache/target.override.active"
    last_app_file="$MODDIR/cache/target.last_app"
    last_profile_file="$MODDIR/cache/target.last_profile"

    # ---- reconcile: ensure policy.request matches policy.current ----
    request_profile=""
    current_profile=""
    [ -f "$policy_request_file" ] && \
        request_profile="$(cat "$policy_request_file" 2>/dev/null || echo "")"
    [ -f "$MODDIR/cache/policy.current" ] && \
        current_profile="$(cat "$MODDIR/cache/policy.current" 2>/dev/null || echo "")"
    [ "$request_profile" = "benchmark" ] && request_profile="benchmark_gaming"
    case "$request_profile" in
        stable|speed|gaming|benchmark_gaming|benchmark_speed)
            if [ -n "$current_profile" ] && [ "$request_profile" != "$current_profile" ]; then
                if network__app__target_request_emit_allowed "reconcile:$request_profile:$current_profile"; then
                    emit_event "$EV_REQUEST_PROFILE" "source=target.prop_reconcile to=$request_profile from=${current_profile:-unknown}"
                fi
            fi
            ;;
    esac

    # ---- foreground detection ----
    pkg="$(network__app__detect_foreground_package)"

    if [ -z "$pkg" ]; then
        network__app__kpi_session_marker_clear
        [ -f "$override_file" ] && \
            _target_engine__release_override "" "release_no_foreground"
        network__app__target_state_transition "IDLE" "no_foreground"
        return 0
    fi

    # ---- target.prop lookup ----
    mapping="$(network__app__target_prop_lookup_profile "$pkg")"
    if [ -z "$mapping" ]; then
        network__app__kpi_session_marker_clear
        [ -f "$override_file" ] && \
            _target_engine__release_override "$pkg" "release_unmapped:pkg=$pkg"
        network__app__target_state_transition "IDLE" "unmapped_package:$pkg"
        return 0
    fi

    profile="${mapping%%,*}"
    priority="${mapping#*,}"
    [ "$profile" = "benchmark" ] && profile="benchmark_gaming"
    case "$profile" in
        stable|speed|gaming|benchmark_gaming|benchmark_speed) ;;
        *)
            network__app__kpi_session_marker_clear
            network__app__target_state_transition "IDLE" "invalid_profile:$pkg"
            return 0
            ;;
    esac

    network__app__kpi_reset_for_app_session "$pkg" "$profile"
    network__app__target_state_transition "APP_OVERRIDE" "mapped:$pkg profile=$profile priority=$priority"

    prev_profile=""
    [ -f "$policy_request_file" ] && \
        prev_profile="$(cat "$policy_request_file" 2>/dev/null || echo "")"
    current_profile=""
    [ -f "$MODDIR/cache/policy.current" ] && \
        current_profile="$(cat "$MODDIR/cache/policy.current" 2>/dev/null || echo "")"

    # ---- log new app only once ----
    if [ ! -f "$last_app_file" ] || [ "$(cat "$last_app_file" 2>/dev/null)" != "$pkg" ]; then
        printf '%s' "$pkg" > "$last_app_file" 2>/dev/null || true
        log_info "target.prop app=$pkg profile=$profile priority=$priority"
    fi

    # ---- apply if needed ----
    if [ "$profile" != "$prev_profile" ] || [ "$profile" != "$current_profile" ]; then
        pkg_key="$pkg"
        if ! network__app__target_app_is_stable "$pkg_key" "$now_ts" "$stable_sec"; then
            log_debug "target.prop skipped: foreground not stable pkg=$pkg_key stable_sec=$stable_sec"
            return 0
        fi
        if ! network__app__target_change_cooldown_ok "$now_ts" "$cooldown_sec"; then
            log_debug "target.prop skipped: profile cooldown active pkg=$pkg_key cooldown_sec=$cooldown_sec"
            return 0
        fi
        network__app__target_state_transition "NETWORK_DECISION" "apply_candidate:$pkg to=$profile"
        if ! printf '%s' "$profile" > "$policy_request_file" 2>/dev/null; then
            network__app__telemetry_counter_inc "op_errors"
            log_warning "target_engine: policy.request write failed pkg=$pkg profile=$profile"
        fi
        network__app__priority_apply_context "$profile" "$priority"
        printf '%s' "$priority"  > "$policy_request_priority_file" 2>/dev/null || true
        network__app__policy_version_touch "$profile" "$priority"
        printf '%s' "$profile"   > "$last_profile_file"            2>/dev/null || true
        network__app__target_mark_profile_change "$now_ts"
        network__app__target_state_transition "POLICY_APPLIED" "request_written:$pkg profile=$profile priority=$priority"
        emit_event "$EV_REQUEST_PROFILE" "source=target.prop package=$pkg priority=$priority to=$profile from=${prev_profile:-unknown} current=${current_profile:-unknown}"
    else
        network__app__target_state_transition "POLICY_APPLIED" "already_applied:$pkg profile=$profile priority=$priority"
    fi

    # ---- maintain override tracking file ----
    override_state="$pkg,$profile"
    if [ ! -f "$override_file" ] || [ "$(cat "$override_file" 2>/dev/null)" != "$override_state" ]; then
        printf '%s' "$override_state" > "$override_file" 2>/dev/null || true
    fi
}
