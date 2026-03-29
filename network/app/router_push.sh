#!/system/bin/sh
# router_push.sh — HTTP status push to the paired router with exponential backoff.
# Completely decoupled from local profile decisions.
# Responsibility: push MODULE_STATUS payload to router_ip; manage push timing/backoff.
# Sourced by cycle.sh. MODDIR must be set. Depends on: state_io.sh, pairing_gate.sh.
# License boundary: this file implements only the Kitsunping-side protocol client.
# No KitsunpingRouter router-side scripts are included here; compatible router agents are
# separate distributions that may use different licenses and change independently.

# -----------------------------------------------------------------------
# WiFi client MAC address
# -----------------------------------------------------------------------

network__app__get_wifi_client_mac() {
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

# -----------------------------------------------------------------------
# Low-level HTTP send (curl → wget → fail)
# -----------------------------------------------------------------------

network__app__router_send_module_status() {
    local payload="$1" router_ip="$2" token="$3" url rc
    local timeout_sec ts nonce body_hash canonical sig

    timeout_sec="${ROUTER_PUSH_TIMEOUT_SEC:-12}"
    case "$timeout_sec" in ''|*[!0-9]*) timeout_sec=12 ;; esac
    [ "$timeout_sec" -lt 5 ]  && timeout_sec=5
    [ "$timeout_sec" -gt 30 ] && timeout_sec=30

    ROUTER_PUSH_LAST_TOOL=""
    ROUTER_PUSH_LAST_URL=""
    ROUTER_PUSH_LAST_RC=""

    # Build HMAC anti-replay headers.
    # X-KP-Signature = HMAC_SHA256(token, "POST|/cgi-bin/router-event|ts|nonce|body_sha256")
    ts=$(date +%s 2>/dev/null || echo 0)
    nonce=$(head -c 6 /dev/urandom 2>/dev/null | sha256sum 2>/dev/null | cut -c1-12 || echo "000000000000")
    body_hash=$(printf '%s' "$payload" | sha256sum 2>/dev/null | awk '{print $1}' || echo "0")
    canonical="POST|/cgi-bin/router-event|${ts}|${nonce}|${body_hash}"
    sig=""
    if command -v kitsunping_hmac_sha256_hex >/dev/null 2>&1; then
        sig=$(kitsunping_hmac_sha256_hex "$token" "$canonical" 2>/dev/null || echo "")
    fi

    if command -v curl >/dev/null 2>&1; then
        ROUTER_PUSH_LAST_TOOL="curl"
        url="http://$router_ip/cgi-bin/router-event"
        curl -fsS --connect-timeout 3 --max-time "$timeout_sec" \
            -H "Content-Type: application/json" \
            -H "X-Auth-Token: $token" \
            -H "X-KP-KeyId: ${KITSUNPING_MODULE_ID:-kitsunping}" \
            -H "X-KP-Ts: $ts" \
            -H "X-KP-Nonce: $nonce" \
            -H "X-KP-Signature: $sig" \
            -X POST \
            -d "$payload" \
            "$url" >/dev/null 2>&1
        rc=$?
        ROUTER_PUSH_LAST_URL="$url"
        ROUTER_PUSH_LAST_RC="$rc"
        return "$rc"
    fi

        # Prefer BusyBox wget over Android's toybox/system wget. The latter does not
        # reliably support repeated --header/--post-data options and breaks router auth.
        if command -v busybox >/dev/null 2>&1; then
            ROUTER_PUSH_LAST_TOOL="busybox-wget"
            url="http://$router_ip/cgi-bin/router-event"
            busybox wget -q -O /dev/null \
                -T "$timeout_sec" \
                --header="Content-Type: application/json" \
                --header="X-Auth-Token: $token" \
                --header="X-KP-KeyId: ${KITSUNPING_MODULE_ID:-kitsunping}" \
                --header="X-KP-Ts: $ts" \
                --header="X-KP-Nonce: $nonce" \
                --header="X-KP-Signature: $sig" \
                --post-data="$payload" \
                "$url" >/dev/null 2>&1
            rc=$?
            ROUTER_PUSH_LAST_URL="$url"
            ROUTER_PUSH_LAST_RC="$rc"
            return "$rc"
        fi

    if command -v wget >/dev/null 2>&1; then
        ROUTER_PUSH_LAST_TOOL="wget"
        url="http://$router_ip/cgi-bin/router-event"
        wget -q -O /dev/null \
            -T "$timeout_sec" \
            --header="Content-Type: application/json" \
            --header="X-Auth-Token: $token" \
            --header="X-KP-KeyId: ${KITSUNPING_MODULE_ID:-kitsunping}" \
            --header="X-KP-Ts: $ts" \
            --header="X-KP-Nonce: $nonce" \
            --header="X-KP-Signature: $sig" \
            --post-data="$payload" \
            "$url" >/dev/null 2>&1
        rc=$?
        ROUTER_PUSH_LAST_URL="$url"
        ROUTER_PUSH_LAST_RC="$rc"
        return "$rc"
    fi

    ROUTER_PUSH_LAST_TOOL="none"
    ROUTER_PUSH_LAST_URL=""
    ROUTER_PUSH_LAST_RC=127
    return 127
}

# -----------------------------------------------------------------------
# Push cycle — rate-limited, exponential backoff on failure.
# Exits early (return 0) if router not enabled/not paired → no side-effects.
# NEVER modifies policy.request or any local profile cache.
# -----------------------------------------------------------------------

network__app__router_status_push_cycle() {
    local paired_flag cache_file router_ip token router_id cache_paired now_ts min_interval
    local last_push_file last_push_ts last_attempt_file last_attempt_ts elapsed payload
    local bssid ssid band width profile_current profile_target transport client_mac
    local target_state target_state_reason
    local priority_target priority_weight priority_min_mbit policy_version status_seq module_boot_id
    local effective_interval backoff_cap backoff_interval backoff_fails
    local policy_hb_ttl max_safe_interval
    local warn_ts_file warn_debounce_sec last_warn_ts warn_elapsed
    local fail_count_file fail_count

    [ "${KITSUNROUTER_ENABLE:-0}" -eq 1 ] || return 0

    paired_flag="$(get_router_paired_flag)"
    [ "$paired_flag" = "1" ] || return 0

    cache_file="$ROUTER_PAIRING_CACHE_FILE"
    [ -f "$cache_file" ] || return 0

    router_ip="$(network__app__read_pairing_json_field "router_ip" "$cache_file")"
    token="$(network__app__read_pairing_json_field "token" "$cache_file")"
    router_id="$(network__app__read_pairing_json_field "router_id" "$cache_file")"
    cache_paired="$(network__app__read_pairing_json_field "paired" "$cache_file")"

    case "${cache_paired:-}" in
        true|1|"1"|"true"|TRUE|yes|YES|on|ON) ;;
        *) return 0 ;;
    esac

    [ -n "$router_ip" ] || return 0
    [ -n "$token" ]     || return 0

    now_ts="$(date +%s 2>/dev/null || echo 0)"
    min_interval="${ROUTER_STATUS_PUSH_INTERVAL_SEC:-15}"
    case "$min_interval" in ''|*[!0-9]*) min_interval=15 ;; esac
    [ "$min_interval" -le 0 ] && min_interval=15

    # ---- exponential backoff on consecutive failures ----
    fail_count_file="$MODDIR/cache/router.push.fail.count"
    fail_count=0
    [ -f "$fail_count_file" ] && fail_count="$(cat "$fail_count_file" 2>/dev/null || echo 0)"
    case "$fail_count" in ''|*[!0-9]*) fail_count=0 ;; esac

    effective_interval="$min_interval"
    if [ "$fail_count" -gt 0 ]; then
        backoff_cap="${ROUTER_STATUS_PUSH_BACKOFF_MAX_SEC:-120}"
        case "$backoff_cap" in ''|*[!0-9]*) backoff_cap=120 ;; esac
        [ "$backoff_cap" -lt "$min_interval" ] && backoff_cap="$min_interval"

        policy_hb_ttl="${ROUTER_POLICY_HEARTBEAT_TTL_SEC:-90}"
        case "$policy_hb_ttl" in ''|*[!0-9]*) policy_hb_ttl=90 ;; esac
        [ "$policy_hb_ttl" -lt 30 ] && policy_hb_ttl=30

        max_safe_interval=$((policy_hb_ttl - 15))
        [ "$max_safe_interval" -lt "$min_interval" ] && max_safe_interval="$min_interval"
        [ "$backoff_cap" -gt "$max_safe_interval" ] && backoff_cap="$max_safe_interval"

        backoff_interval="$min_interval"
        backoff_fails="$fail_count"
        [ "$backoff_fails" -gt 10 ] && backoff_fails=10
        while [ "$backoff_fails" -gt 0 ] && [ "$backoff_interval" -lt "$backoff_cap" ]; do
            backoff_interval=$((backoff_interval * 2))
            [ "$backoff_interval" -gt "$backoff_cap" ] && backoff_interval="$backoff_cap"
            backoff_fails=$((backoff_fails - 1))
        done
        effective_interval="$backoff_interval"
    fi

    # ---- rate-limit check ----
    last_push_file="$MODDIR/cache/router.status.last_push.ts"
    last_attempt_file="$MODDIR/cache/router.status.last_attempt.ts"
    last_push_ts=0
    [ -f "$last_push_file" ] && last_push_ts="$(cat "$last_push_file" 2>/dev/null || echo 0)"
    case "$last_push_ts" in ''|*[!0-9]*) last_push_ts=0 ;; esac

    last_attempt_ts=0
    if [ -f "$last_attempt_file" ]; then
        last_attempt_ts="$(cat "$last_attempt_file" 2>/dev/null || echo 0)"
    elif [ "$last_push_ts" -gt 0 ]; then
        last_attempt_ts="$last_push_ts"
    fi
    case "$last_attempt_ts" in ''|*[!0-9]*) last_attempt_ts=0 ;; esac

    elapsed=$((now_ts - last_attempt_ts))
    [ "$elapsed" -lt 0 ] && elapsed=0
    [ "$elapsed" -lt "$effective_interval" ] && return 0

    # ---- build payload ----
    bssid="${wifi_bssid:-}"
    ssid="${wifi_ssid:-}"
    band="${wifi_band:-}"
    width="${wifi_width:-}"
    profile_current="$(cat "$MODDIR/cache/policy.current"          2>/dev/null || echo "")"
    profile_target="$(cat "$MODDIR/cache/policy.target"            2>/dev/null || echo "")"
    # Derive priority_target from explicit policy cache first.
    priority_target="$(cat "$MODDIR/cache/policy.priority" 2>/dev/null || echo "")"
    case "$priority_target" in high|medium|low) ;; *) priority_target="" ;; esac

    # Fallback: parse active target_state reason (e.g. "... priority=high").
    target_state_reason="$(cat "$MODDIR/cache/target.state.reason" 2>/dev/null || echo "")"
    if [ -z "$priority_target" ] && [ -n "$target_state_reason" ]; then
        case "$target_state_reason" in
            *"priority=high"*) priority_target="high" ;;
            *"priority=medium"*) priority_target="medium" ;;
            *"priority=low"*) priority_target="low" ;;
        esac
    fi

    # Final fallback by coarse profile class only when no explicit priority was found.
    if [ -z "$priority_target" ]; then
        case "${profile_current:-}" in
            gaming|benchmark|benchmark_gaming) priority_target="high" ;;
            speed|benchmark_speed)             priority_target="medium" ;;
            *)                                 priority_target="medium" ;;
        esac
    fi
    priority_weight="$(cat "$MODDIR/cache/policy.priority.weight"  2>/dev/null || echo "50")"
    priority_min_mbit="$(cat "$MODDIR/cache/policy.priority.min_mbit" 2>/dev/null || echo "20")"
    policy_version="$(network__app__policy_version_get)"
    status_seq="$(network__app__router_status_next_seq)"
    module_boot_id="$(network__app__module_boot_id_get)"
    target_state="$(network__app__target_state_get)"
    transport="${transport:-unknown}"
    client_mac="$(network__app__get_wifi_client_mac)"
    # ---- telemetry counters ----
    local tel_changes_hour tel_tweak_restores tel_op_errors _kpi_file _kpi_ch
    tel_tweak_restores="$(network__app__telemetry_counter_read "tweak_restores")"
    tel_op_errors="$(network__app__telemetry_counter_read "op_errors")"
    _kpi_file="$MODDIR/cache/executor.kpi.hourly"
    _kpi_ch=0
    [ -f "$_kpi_file" ] && _kpi_ch="$(awk -F= '$1=="kpi.changes_hour"{print $2+0}' "$_kpi_file" 2>/dev/null || echo 0)"
    case "$_kpi_ch" in ''|*[!0-9]*) _kpi_ch=0 ;; esac
    tel_changes_hour="$_kpi_ch"

    payload=$(printf '%s' "{\"event\":\"MODULE_STATUS\",\"ts\":$now_ts,\"paired\":true,\"router_id\":\"${router_id:-router}\",\"version\":$policy_version,\"seq\":$status_seq,\"module_boot_id\":\"${module_boot_id:-unknown}\",\"client_mac\":\"${client_mac:-}\",\"bssid\":\"$bssid\",\"ssid\":\"$ssid\",\"band\":\"$band\",\"width\":\"$width\",\"profile_current\":\"$profile_current\",\"profile_target\":\"$profile_target\",\"priority_target\":\"$priority_target\",\"priority_weight\":\"$priority_weight\",\"priority_min_mbit\":\"$priority_min_mbit\",\"base_rate_mbit\":\"0\",\"target_state\":\"$target_state\",\"target_state_reason\":\"$target_state_reason\",\"transport\":\"$transport\",\"wifi_state\":\"${wifi_state:-unknown}\",\"wifi_score\":\"${wifi_score:-0}\",\"last_event\":\"${last_event:-}\",\"telemetry\":{\"changes_hour\":$tel_changes_hour,\"tweak_restores\":$tel_tweak_restores,\"op_errors\":$tel_op_errors}}")

    # ---- warn debounce ----
    warn_debounce_sec="${ROUTER_PUSH_WARN_DEBOUNCE_SEC:-90}"
    case "$warn_debounce_sec" in ''|*[!0-9]*) warn_debounce_sec=90 ;; esac
    [ "$warn_debounce_sec" -lt 10 ] && warn_debounce_sec=10

    warn_ts_file="$MODDIR/cache/router.push.warn.ts"
    last_warn_ts=0
    [ -f "$warn_ts_file" ] && last_warn_ts="$(cat "$warn_ts_file" 2>/dev/null || echo 0)"
    case "$last_warn_ts" in ''|*[!0-9]*) last_warn_ts=0 ;; esac

    # ---- send ----
    if network__app__router_send_module_status "$payload" "$router_ip" "$token"; then
        printf '%s\n' "$now_ts" | atomic_write "$last_attempt_file"
        printf '%s\n' "$now_ts" | atomic_write "$last_push_file"
        printf '0\n'            | atomic_write "$fail_count_file"
        log_debug "router_status_push ok ip=$router_ip transport=$transport"
    else
        printf '%s\n' "$now_ts"    | atomic_write "$last_attempt_file"
        fail_count=$((fail_count + 1))
        printf '%s\n' "$fail_count" | atomic_write "$fail_count_file"
        warn_elapsed=$((now_ts - last_warn_ts))
        [ "$warn_elapsed" -lt 0 ] && warn_elapsed=0
        if [ "$fail_count" -ge 3 ] && [ "$warn_elapsed" -ge "$warn_debounce_sec" ]; then
            printf '%s\n' "$now_ts" | atomic_write "$warn_ts_file"
            log_warning "router_status_push failed ip=$router_ip tool=${ROUTER_PUSH_LAST_TOOL:-unknown} url=${ROUTER_PUSH_LAST_URL:-unknown} rc=${ROUTER_PUSH_LAST_RC:-1} fails=$fail_count backoff_wait=${effective_interval}s timeout=${ROUTER_PUSH_TIMEOUT_SEC:-12}s (module cannot confirm pair-status)"
        fi
    fi
}
