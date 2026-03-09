#!/system/bin/sh
# router_channel.sh — WiFi channel recommendation from paired router.
# Responsibility: request channel scan/recommendation from router; cache results with TTL.
# Sourced by cycle.sh or triggered manually. MODDIR must be set.
# Depends on: state_io.sh, pairing_gate.sh.
# License boundary: this file contains only the Kitsunping-side HTTP/JSON exchange.
# Router-side implementations such as KitsunpingRouter are separate distributions,
# can carry different licenses, and may vary internally while honoring the protocol.

# -----------------------------------------------------------------------
# Configuration (M2: configurable via setprop)
# -----------------------------------------------------------------------

# Minimum wifi_score to trigger automatic channel scan (default: 65)
CHANNEL_SCAN_THRESHOLD="${KITSUNPING_CHANNEL_SCAN_THRESHOLD:-65}"
_prop_threshold="$(getprop kitsuneping.channel.score_threshold 2>/dev/null | tr -d '\r\n')"
[ -n "$_prop_threshold" ] && [ "$_prop_threshold" -ge 10 ] && [ "$_prop_threshold" -le 100 ] && \
    CHANNEL_SCAN_THRESHOLD="$_prop_threshold"

# Cache TTL in seconds (default: 15 minutes = 900s)
CHANNEL_CACHE_TTL_SEC="${KITSUNEPING_CHANNEL_CACHE_TTL:-900}"
_prop_ttl="$(getprop kitsuneping.channel.cache_ttl_sec 2>/dev/null | tr -d '\r\n')"
[ -n "$_prop_ttl" ] && [ "$_prop_ttl" -ge 60 ] && [ "$_prop_ttl" -le 7200 ] && \
    CHANNEL_CACHE_TTL_SEC="$_prop_ttl"

# Rate-limit: minimum seconds between requests (default: 5 min = 300s)
CHANNEL_REQUEST_INTERVAL_SEC="${KITSUNPING_CHANNEL_REQUEST_INTERVAL:-300}"
_prop_interval="$(getprop kitsuneping.channel.request_interval_sec 2>/dev/null | tr -d '\r\n')"
[ -n "$_prop_interval" ] && [ "$_prop_interval" -ge 60 ] && [ "$_prop_interval" -le 3600 ] && \
    CHANNEL_REQUEST_INTERVAL_SEC="$_prop_interval"

# HTTP timeout (default: 5s)
CHANNEL_HTTP_TIMEOUT_SEC="${KITSUNPING_CHANNEL_HTTP_TIMEOUT:-5}"

# Retry count (default: 1)
CHANNEL_HTTP_RETRY="${KITSUNPING_CHANNEL_HTTP_RETRY:-1}"

# Telemetry file (M2)
# Note: Use /sdcard which is always writable
CHANNEL_CACHE_DIR="/sdcard/kitsunping_cache"
mkdir -p "$CHANNEL_CACHE_DIR" 2>/dev/null || true
CHANNEL_TELEMETRY_FILE="$CHANNEL_CACHE_DIR/telemetry.channel_requests"

# M4: Notification threshold (minimum score_gap to notify user)
CHANNEL_NOTIFICATION_GAP="${KITSUNEPING_CHANNEL_NOTIFICATION_GAP:-15}"
_prop_notif_gap="$(getprop kitsuneping.channel.notification_gap 2>/dev/null | tr -d '\r\n')"
[ -n "$_prop_notif_gap" ] && [ "$_prop_notif_gap" -ge 5 ] && [ "$_prop_notif_gap" -le 50 ] && \
    CHANNEL_NOTIFICATION_GAP="$_prop_notif_gap"

# M4: Notification rate-limit (minimum seconds between notifications, default: 1 hour)
CHANNEL_NOTIFICATION_INTERVAL_SEC="${KITSUNEPING_CHANNEL_NOTIFICATION_INTERVAL:-3600}"
_prop_notif_interval="$(getprop kitsuneping.channel.notification_interval_sec 2>/dev/null | tr -d '\r\n')"
[ -n "$_prop_notif_interval" ] && [ "$_prop_notif_interval" -ge 300 ] && [ "$_prop_notif_interval" -le 86400 ] && \
    CHANNEL_NOTIFICATION_INTERVAL_SEC="$_prop_notif_interval"

# M4: Notification state file
CHANNEL_NOTIFICATION_STATE="$CHANNEL_CACHE_DIR/channel_notification.state"

# -----------------------------------------------------------------------
# Logging compatibility
# -----------------------------------------------------------------------

if ! command -v kitsunping_log >/dev/null 2>&1; then
    kitsunping_log() {
        local level="$1"
        shift
        case "$level" in
            info)  log_info "[router_channel] $*" ;;
            warn)  log_warning "[router_channel] $*" ;;
            error) log_error "[router_channel] $*" ;;
            *)     log_debug "[router_channel] $*" ;;
        esac
    }
fi

if ! command -v kitsuneping_log >/dev/null 2>&1; then
    kitsuneping_log() {
        kitsunping_log "$@"
    }
fi

# -----------------------------------------------------------------------
# Telemetry helpers (M2)
# -----------------------------------------------------------------------

# Increment telemetry counter atomically
# Usage: _channel__telemetry_inc <counter_name>
#   counter_name: auto|manual|errors
_channel__telemetry_inc() {
    local counter_name="$1"
    local telem_file="$CHANNEL_TELEMETRY_FILE"
    local tmp_file="${telem_file}.tmp.$$"
    local current_count=0
    
    # Read current count
    if [ -f "$telem_file" ]; then
        current_count="$(grep "^${counter_name}=" "$telem_file" 2>/dev/null | cut -d'=' -f2 | tr -d '\r\n')"
        case "$current_count" in ''|*[!0-9]*) current_count=0 ;; esac
    fi
    
    # Increment
    current_count=$((current_count + 1))
    
    # Write atomically (preserve other counters)
    {
        if [ -f "$telem_file" ]; then
            grep -v "^${counter_name}=" "$telem_file" 2>/dev/null || true
        fi
        printf '%s=%d\n' "$counter_name" "$current_count"
    } > "$tmp_file" 2>/dev/null
    
    mv "$tmp_file" "$telem_file" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null
}

# Read telemetry counter
# Usage: _channel__telemetry_read <counter_name>
_channel__telemetry_read() {
    local counter_name="$1"
    local telem_file="$CHANNEL_TELEMETRY_FILE"
    local count
    
    [ -f "$telem_file" ] || { printf '0'; return 0; }
    
    count="$(grep "^${counter_name}=" "$telem_file" 2>/dev/null | cut -d'=' -f2 | tr -d '\r\n')"
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    printf '%d' "$count"
}

# Persist latest channel-apply result for app UI refresh.
# Usage: _channel__write_apply_status <file> <status> <reason> <detail> <band> <channel>
_channel__write_apply_status() {
    local file="$1" status="$2" reason="$3" detail="$4" band="$5" channel="$6"
    local ts tmp
    ts="$(date +%s 2>/dev/null || echo 0)"
    tmp="${file}.tmp.$$"

    reason="$(printf '%s' "$reason" | tr -d '\r\n\"')"
    detail="$(printf '%s' "$detail" | tr -d '\r\n\"')"
    band="$(printf '%s' "$band" | tr -d '\r\n\"')"

    {
        printf '{"status":"%s","reason":"%s","detail":"%s","band":"%s","channel":%s,"ts":%s}' \
            "$status" "$reason" "$detail" "$band" "${channel:-0}" "$ts"
    } > "$tmp" 2>/dev/null

    mv "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------

# Read single field from JSON cache (simple key match)
_channel__read_cache_field() {
    local key="$1" file="$2" value
    [ -f "$file" ] || return 1
    value="$(grep -m1 "\"$key\"" "$file" 2>/dev/null | sed 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"[,}].*$//; s/[,}].*$//')"
    [ -n "$value" ] && printf '%s' "$value"
}

# Write atomic JSON cache with timestamp
_channel__write_cache() {
    local cache_file="$1" payload="$2" tmp_file ts json_content
    ts="$(date +%s 2>/dev/null || echo 0)"
    tmp_file="${cache_file}.tmp.$$"
    
    # Build JSON content (cache_file already points to /data/local/tmp)
    json_content="{\"cached_at\":$ts,\"ttl_sec\":$CHANNEL_CACHE_TTL_SEC,\"data\":$payload}"
    
    # Write directly (no need for su -mm since using /data/local/tmp)
    printf '%s' "$json_content" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$cache_file" 2>/dev/null
}

# Check if cache is valid (exists and not expired)
_channel__cache_valid() {
    local cache_file="$1" cached_at now_ts age
    [ -f "$cache_file" ] || return 1
    
    cached_at="$(_channel__read_cache_field "cached_at" "$cache_file")"
    case "$cached_at" in ''|*[!0-9]*) return 1 ;; esac
    
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    age=$(( now_ts - cached_at ))
    
    [ "$age" -ge 0 ] && [ "$age" -le "$CHANNEL_CACHE_TTL_SEC" ]
}

# -----------------------------------------------------------------------
# HTTP GET to router endpoint (simplified for channel recommendation)
# -----------------------------------------------------------------------

_channel__http_get() {
    local url="$1" token="$2" timeout="$3" output_file="$4" rc
    
    # Note: router-channel-recommend CGI doesn't require authentication headers
    # It's a read-only endpoint, so we skip HMAC signatures
    
    # Temporarily disable SELinux to allow file writes from daemon context
    local selinux_original=$(getenforce 2>/dev/null)
    [ "$selinux_original" = "Enforcing" ] && setenforce 0 2>/dev/null
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --connect-timeout 3 --max-time "$timeout" \
            -o "$output_file" \
            "$url" 2>/dev/null
        rc=$?
    elif command -v busybox >/dev/null 2>&1; then
        busybox wget -q -O "$output_file" \
            -T "$timeout" \
            "$url" 2>/dev/null
        rc=$?
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$output_file" \
            -T "$timeout" \
            "$url" 2>/dev/null
        rc=$?
    else
        rc=127
    fi
    
    # Restore SELinux mode (optional - Permissive is usually safe on rooted devices)
    # [ "$selinux_original" = "Enforcing" ] && setenforce 1 2>/dev/null
    
    return "$rc"
}

# -----------------------------------------------------------------------
# Main function: Request channel recommendation
# -----------------------------------------------------------------------
# Usage: network__router__channel_recommend_request [band] [force]
#   band:  2g|5g (default: auto-detect from current connection)
#   force: 1 to bypass score/rate-limit guards (manual trigger)
# Returns: 0 if successful (cache updated), non-zero otherwise
# -----------------------------------------------------------------------

network__router__channel_recommend_request() {
    local band="${1:-auto}" force="${2:-0}"
    local paired_flag cache_file router_ip token wifi_score now_ts
    local last_request_file last_request_ts elapsed
    local url iface response_file tmp_response status rc retries
    local recommendation_cache request_type
    
    # M2: Determine request type for telemetry
    request_type="auto"
    [ "$force" -eq 1 ] && request_type="manual"
    
    # ---- Guard: router feature enabled ----
    [ "${KITSUNROUTER_ENABLE:-0}" -eq 1 ] || {
        kitsunping_log "warn" "router_channel: router feature disabled"
        return 1
    }
    
    # ---- Guard: pairing active ----
    paired_flag="$(get_router_paired_flag)"
    [ "$paired_flag" = "1" ] || {
        kitsunping_log "warn" "router_channel: not paired"
        return 1
    }
    
    cache_file="$ROUTER_PAIRING_CACHE_FILE"
    [ -f "$cache_file" ] || {
        kitsunping_log "warn" "router_channel: pairing cache missing"
        return 1
    }
    
    router_ip="$(network__app__read_pairing_json_field "router_ip" "$cache_file")"
    token="$(network__app__read_pairing_json_field "token" "$cache_file")"
    
    [ -n "$router_ip" ] && [ -n "$token" ] || {
        kitsunping_log "warn" "router_channel: missing router_ip or token"
        return 1
    }
    
    # ---- Guard: rate-limiting (unless force=1) ----
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    last_request_file="$CHANNEL_CACHE_DIR/router_channel_last_request.ts"
    
    if [ "$force" -ne 1 ]; then
        if [ -f "$last_request_file" ]; then
            last_request_ts="$(cat "$last_request_file" 2>/dev/null || echo 0)"
            case "$last_request_ts" in ''|*[!0-9]*) last_request_ts=0 ;; esac
            elapsed=$(( now_ts - last_request_ts ))
            
            if [ "$elapsed" -lt "$CHANNEL_REQUEST_INTERVAL_SEC" ]; then
                kitsunping_log "debug" "router_channel: rate-limited (${elapsed}s < ${CHANNEL_REQUEST_INTERVAL_SEC}s, type=$request_type)"
                return 1
            fi
        fi
        
        # ---- Guard: wifi_score threshold ----
        wifi_score="${WIFI_SCORE:-100}"
        case "$wifi_score" in ''|*[!0-9]*) wifi_score=100 ;; esac
        
        if [ "$wifi_score" -ge "$CHANNEL_SCAN_THRESHOLD" ]; then
            kitsuneping_log "debug" "router_channel: score too high ($wifi_score >= $CHANNEL_SCAN_THRESHOLD, type=$request_type)"
            return 1
        fi
        
        kitsunping_log "info" "router_channel: score threshold met ($wifi_score < $CHANNEL_SCAN_THRESHOLD, type=$request_type)"
    else
        kitsunping_log "info" "router_channel: force=1, bypassing guards (type=$request_type)"
    fi
    
    # ---- Auto-detect band if needed ----
    if [ "$band" = "auto" ]; then
        band="${WIFI_BAND:-2g}"
        case "$band" in
            2.4*|2g*) band="2g" ;;
            5*|5g*)   band="5g" ;;
            *)        band="2g" ;;
        esac
    fi
    
    case "$band" in
        2g|5g) ;;
        *)
            kitsunping_log "warn" "router_channel: invalid band '$band', using 2g"
            band="2g"
            ;;
    esac
    
    # ---- Detect interface ----
    iface="${WIFI_IFACE:-wlan0}"
    case "$iface" in
        ''|none) iface="wlan0" ;;
    esac
    
    # ---- Build request URL ----
    # Note: Don't send client's iface (wlan0) to router - let router detect its own AP interface (ra0)
    # Sending wlan0 causes scan_method=none and degraded_mode=1
    url="http://${router_ip}/cgi-bin/router-channel-recommend?${band}&--channel-mode=full-1-13&debug=rf"
    
    kitsuneping_log "info" "router_channel: requesting recommendation band=$band type=$request_type"
    
    # ---- Execute HTTP GET with retry ----
    tmp_response="$CHANNEL_CACHE_DIR/router_channel_response.tmp.$$"
    response_file="$CHANNEL_CACHE_DIR/router_channel_response.json"
    recommendation_cache="$CHANNEL_CACHE_DIR/router_channel_recommendation.json"
    rc=1
    retries=0
    
    while [ "$retries" -le "$CHANNEL_HTTP_RETRY" ]; do
        if _channel__http_get "$url" "$token" "$CHANNEL_HTTP_TIMEOUT_SEC" "$tmp_response"; then
            rc=0
            break
        fi
        retries=$(( retries + 1 ))
        [ "$retries" -le "$CHANNEL_HTTP_RETRY" ] && sleep 1
    done
    
    if [ "$rc" -ne 0 ]; then
        rm -f "$tmp_response" 2>/dev/null
        kitsunping_log "warn" "router_channel: HTTP request failed after $((retries)) attempts (type=$request_type)"
        _channel__telemetry_inc "errors"  # M2: track errors
        return 1
    fi
    
    # ---- Validate response ----
    if [ ! -s "$tmp_response" ]; then
        rm -f "$tmp_response" 2>/dev/null
        kitsunping_log "warn" "router_channel: empty response (type=$request_type)"
        _channel__telemetry_inc "errors"  # M2: track errors
        return 1
    fi
    
    status="$(_channel__read_cache_field "status" "$tmp_response")"
    if [ "$status" != "ok" ]; then
        kitsunping_log "warn" "router_channel: response status=$status (type=$request_type)"
        rm -f "$tmp_response" 2>/dev/null
        _channel__telemetry_inc "errors"  # M2: track errors
        return 1
    fi
    
    # ---- Success: move to final location ----
    mv "$tmp_response" "$response_file" 2>/dev/null
    chmod 600 "$response_file" 2>/dev/null
    
    # Write to cache (note: recommendation_cache defined above points to read-only MODDIR/cache)
    # The app reads from /data/local/tmp/router_channel_response.json via symlink or direct read
    _channel__write_cache "$recommendation_cache" "$(cat "$response_file")"
    
    # Update last request timestamp
    printf '%s' "$now_ts" > "$last_request_file" 2>/dev/null
    
    # M2: Increment telemetry counter (auto or manual)
    _channel__telemetry_inc "$request_type"
    
    kitsunping_log "info" "router_channel: recommendation cached successfully (type=$request_type)"
    
    return 0
}
# -----------------------------------------------------------------------
# M4: Check if notification should be triggered
# -----------------------------------------------------------------------
# Usage: network__wifi__channel_notification_check [current_channel]
#   current_channel: Current WiFi channel number (from wifi_chan variable)
# Purpose: Compare cached recommendation with current state, notify if improvement >= threshold
# Returns: 0 if notification sent, 1 if skipped (no improvement/rate-limited)
# -----------------------------------------------------------------------

network__wifi__channel_notification_check() {
    local current_channel="${1:-0}" recommendation_cache response_file
    local recommended_channel current_channel_from_cache score_gap band status
    local last_notif_ts last_notif_channel now_ts elapsed_sec
    
    recommendation_cache="$CHANNEL_CACHE_DIR/router_channel_recommendation.json"
    response_file="$CHANNEL_CACHE_DIR/router_channel_response.json"
    
    # Validate current channel input
    case "$current_channel" in ''|*[!0-9]*|0) 
        kitsuneping_log "debug" "router_channel: notification check skipped - invalid current channel ($current_channel)"
        return 1 
    ;; esac
    
    # Check if recommendation cache exists
    if [ ! -f "$response_file" ]; then
        kitsuneping_log "debug" "router_channel: notification check skipped - no cached recommendation"
        return 1
    fi
    
    # Validate cache status
    status="$(_channel__read_cache_field "status" "$response_file")"
    if [ "$status" != "ok" ]; then
        kitsuneping_log "debug" "router_channel: notification check skipped - invalid cache status ($status)"
        return 1
    fi
    
    # Extract recommendation fields
    recommended_channel="$(_channel__read_cache_field "recommended_channel" "$response_file")"
    current_channel_from_cache="$(_channel__read_cache_field "current_channel" "$response_file")"
    score_gap_raw="$(_channel__read_cache_field "score_gap" "$response_file")"
    band="$(_channel__read_cache_field "band" "$response_file")"
    
    # Validate extracted fields
    case "$recommended_channel" in ''|*[!0-9]*) 
        kitsuneping_log "debug" "router_channel: notification check skipped - invalid recommended_channel ($recommended_channel)"
        return 1 
    ;; esac
    
    case "$score_gap_raw" in ''|*[!0-9.-]*) score_gap=0 ;; *) score_gap="${score_gap_raw%.*}" ;; esac
    
    [ -z "$band" ] && band="unknown"
    
    # ---- Guard 1: Same channel (no improvement available) ----
    if [ "$recommended_channel" -eq "$current_channel" ]; then
        kitsuneping_log "debug" "router_channel: notification skipped - already on optimal channel ($current_channel)"
        return 1
    fi
    
    # ---- Guard 2: Score gap below threshold ----
    if [ "$score_gap" -lt "$CHANNEL_NOTIFICATION_GAP" ]; then
        kitsuneping_log "debug" "router_channel: notification skipped - score_gap=$score_gap < threshold=$CHANNEL_NOTIFICATION_GAP"
        return 1
    fi
    
    # ---- Guard 3: Rate-limit check ----
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    
    if [ -f "$CHANNEL_NOTIFICATION_STATE" ]; then
        last_notif_ts="$(grep "^last_notification_ts=" "$CHANNEL_NOTIFICATION_STATE" 2>/dev/null | cut -d'=' -f2 | tr -d '\r\n')"
        last_notif_channel="$(grep "^last_notified_channel=" "$CHANNEL_NOTIFICATION_STATE" 2>/dev/null | cut -d'=' -f2 | tr -d '\r\n')"
        
        case "$last_notif_ts" in ''|*[!0-9]*) last_notif_ts=0 ;; esac
        case "$last_notif_channel" in ''|*[!0-9]*) last_notif_channel=0 ;; esac
        
        elapsed_sec=$(( now_ts - last_notif_ts ))
        
        # Skip if same channel notified recently
        if [ "$last_notif_channel" -eq "$recommended_channel" ] && [ "$elapsed_sec" -lt "$CHANNEL_NOTIFICATION_INTERVAL_SEC" ]; then
            kitsuneping_log "debug" "router_channel: notification rate-limited - channel $recommended_channel notified ${elapsed_sec}s ago (min: ${CHANNEL_NOTIFICATION_INTERVAL_SEC}s)"
            return 1
        fi
    fi
    
    # ---- Send notification via broadcast ----
    kitsuneping_log "info" "router_channel: sending notification - channel $recommended_channel (+${score_gap} improvement, band=$band)"
    
    am broadcast \
        -a com.kitsunping.ACTION_CHANNEL_AVAILABLE \
        -p app.kitsunping \
        --es recommended_channel "$recommended_channel" \
        --es current_channel "$current_channel" \
        --ei score_gap "$score_gap" \
        --es band "$band" \
        >/dev/null 2>&1
    
    # Update notification state
    {
        printf 'last_notification_ts=%d\n' "$now_ts"
        printf 'last_notified_channel=%d\n' "$recommended_channel"
        printf 'last_score_gap=%d\n' "$score_gap"
        printf 'last_band=%s\n' "$band"
    } > "$CHANNEL_NOTIFICATION_STATE" 2>/dev/null
    
    return 0
}
# -----------------------------------------------------------------------
# Read cached recommendation
# -----------------------------------------------------------------------
# Usage: network__router__channel_get_cached [field]
#   field: recommended_channel|score_gap|current_channel|confidence|...
# Returns: field value if cache valid, empty otherwise
# -----------------------------------------------------------------------

network__router__channel_get_cached() {
    local field="$1" cache_file value
    
    cache_file="$CHANNEL_CACHE_DIR/router_channel_recommendation.json"
    
    if ! _channel__cache_valid "$cache_file"; then
        kitsunping_log "debug" "router_channel: cache expired or missing"
        return 1
    fi
    
    # Read from nested data.field
    value="$(grep -m1 "\"$field\"" "$cache_file" 2>/dev/null | sed 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*//; s/[",].*//; s/[[:space:]]*$//')"
    
    [ -n "$value" ] && printf '%s' "$value"
}

# -----------------------------------------------------------------------
# Check if better channel is available
# -----------------------------------------------------------------------
# Returns: 0 if recommended_channel != current_channel AND score_gap >= threshold
# -----------------------------------------------------------------------

network__router__channel_has_better_option() {
    local recommended current score_gap threshold
    
    threshold="${1:-15}"
    case "$threshold" in ''|*[!0-9]*) threshold=15 ;; esac
    
    recommended="$(network__router__channel_get_cached "recommended_channel")"
    current="$(network__router__channel_get_cached "current_channel")"
    score_gap="$(network__router__channel_get_cached "score_gap")"
    
    [ -n "$recommended" ] && [ -n "$current" ] && [ -n "$score_gap" ] || return 1
    
    case "$recommended" in ''|*[!0-9]*) return 1 ;; esac
    case "$current" in ''|*[!0-9]*) return 1 ;; esac
    case "$score_gap" in ''|*[!0-9]*) return 1 ;; esac
    
    [ "$recommended" -ne "$current" ] && [ "$score_gap" -ge "$threshold" ]
}

# -----------------------------------------------------------------------
# P4: Apply channel change on router
# -----------------------------------------------------------------------
# Usage: network__router__channel_apply_request <band> <channel>
#   band: 2g|5g (required)
#   channel: integer channel number (required)
# Returns: 0 if successful, non-zero otherwise
# Telemetry: increments telemetry.channel_applies (success) or telemetry.channel_apply_errors (failure)
# -----------------------------------------------------------------------

network__router__channel_apply_request() {
    local band="$1" channel="$2"
    local paired_flag cache_file router_ip token
    local url json_body response_file tmp_response status rc
    local timeout selinux_original
    local telemetry_file="$CHANNEL_CACHE_DIR/telemetry.channel_applies"

    response_file="$CHANNEL_CACHE_DIR/router_channel_apply_response.json"
    
    # ---- Validate arguments ----
    if [ -z "$band" ] || [ -z "$channel" ]; then
        kitsunping_log "error" "channel_apply: missing band or channel (band=$band, channel=$channel)"
        _channel__write_apply_status "$response_file" "error" "missing_args" "band_or_channel_empty" "$band" "$channel"
        _channel__telemetry_inc "apply_errors"
        return 1
    fi
    
    # Validate band
    case "$band" in
        2g|2.4g|2.4ghz) band="2g" ;;
        5g|5ghz) band="5g" ;;
        *)
            kitsunping_log "error" "channel_apply: invalid band '$band'"
            _channel__write_apply_status "$response_file" "error" "invalid_band" "$band" "$band" "$channel"
            _channel__telemetry_inc "apply_errors"
            return 1
            ;;
    esac
    
    # Validate channel is numeric
    case "$channel" in
        ''|*[!0-9]*)
            kitsunping_log "error" "channel_apply: invalid channel '$channel' (expected integer)"
            _channel__write_apply_status "$response_file" "error" "invalid_channel" "$channel" "$band" "$channel"
            _channel__telemetry_inc "apply_errors"
            return 1
            ;;
    esac
    
    # Validate channel range per band
    if [ "$band" = "2g" ]; then
        if [ "$channel" -lt 1 ] || [ "$channel" -gt 14 ]; then
            kitsunping_log "error" "channel_apply: 2.4GHz channel out of range (1-14): $channel"
            _channel__write_apply_status "$response_file" "error" "channel_out_of_range" "2g_1_14" "$band" "$channel"
            _channel__telemetry_inc "apply_errors"
            return 1
        fi
    elif [ "$band" = "5g" ]; then
        if [ "$channel" -lt 36 ] || [ "$channel" -gt 165 ]; then
            kitsunping_log "error" "channel_apply: 5GHz channel out of range (36-165): $channel"
            _channel__write_apply_status "$response_file" "error" "channel_out_of_range" "5g_36_165" "$band" "$channel"
            _channel__telemetry_inc "apply_errors"
            return 1
        fi
    fi
    
    # ---- Guard: router feature enabled ----
    [ "${KITSUNROUTER_ENABLE:-0}" -eq 1 ] || {
        kitsunping_log "warn" "channel_apply: router feature disabled"
        _channel__write_apply_status "$response_file" "error" "router_feature_disabled" "KITSUNROUTER_ENABLE=0" "$band" "$channel"
        _channel__telemetry_inc "apply_errors"
        return 1
    }
    
    # ---- Guard: pairing active ----
    paired_flag="$(get_router_paired_flag)"
    [ "$paired_flag" = "1" ] || {
        kitsunping_log "warn" "channel_apply: not paired"
        _channel__write_apply_status "$response_file" "error" "not_paired" "pairing_required" "$band" "$channel"
        _channel__telemetry_inc "apply_errors"
        return 1
    }
    
    cache_file="$ROUTER_PAIRING_CACHE_FILE"
    [ -f "$cache_file" ] || {
        kitsunping_log "warn" "channel_apply: pairing cache missing"
        _channel__write_apply_status "$response_file" "error" "pairing_cache_missing" "$cache_file" "$band" "$channel"
        _channel__telemetry_inc "apply_errors"
        return 1
    }
    
    router_ip="$(network__app__read_pairing_json_field "router_ip" "$cache_file")"
    token="$(network__app__read_pairing_json_field "token" "$cache_file")"
    
    [ -n "$router_ip" ] && [ -n "$token" ] || {
        kitsunping_log "warn" "channel_apply: missing router_ip or token"
        _channel__write_apply_status "$response_file" "error" "router_ip_or_token_missing" "invalid_pairing_cache" "$band" "$channel"
        _channel__telemetry_inc "apply_errors"
        return 1
    }
    
    # ---- Build request ----
    url="http://${router_ip}/cgi-bin/router-channel-apply"
    json_body="{\"band\":\"${band}\",\"channel\":${channel}}"
    tmp_response="${response_file}.tmp.$$"
    timeout="${CHANNEL_HTTP_TIMEOUT_SEC:-5}"
    
    kitsunping_log "info" "channel_apply: requesting channel change (band=$band, channel=$channel, router=$router_ip)"
    
    # ---- Execute POST request ----
    # Note: SELinux workaround
    selinux_original=$(getenforce 2>/dev/null)
    [ "$selinux_original" = "Enforcing" ] && setenforce 0 2>/dev/null
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsS --connect-timeout 3 --max-time "$timeout" \
            -X POST \
            -H "Content-Type: application/json" \
            -H "X-Auth-Token: $token" \
            -d "$json_body" \
            -o "$tmp_response" \
            "$url" 2>/dev/null
        rc=$?
    elif command -v busybox >/dev/null 2>&1; then
        busybox wget -q -O "$tmp_response" \
            -T "$timeout" \
            --header="Content-Type: application/json" \
            --header="X-Auth-Token: $token" \
            --post-data="$json_body" \
            "$url" 2>/dev/null
        rc=$?
    elif command -v wget >/dev/null 2>&1; then
        # wget doesn't support POST with body easily, need temp file
        local body_file="${tmp_response}.body"
        printf '%s' "$json_body" > "$body_file"
        wget -q -O "$tmp_response" \
            -T "$timeout" \
            --header="Content-Type: application/json" \
            --header="X-Auth-Token: $token" \
            --post-file="$body_file" \
            "$url" 2>/dev/null
        rc=$?
        rm -f "$body_file" 2>/dev/null
    else
        kitsunping_log "error" "channel_apply: no HTTP client available (curl/wget)"
        _channel__write_apply_status "$response_file" "error" "no_http_client" "curl_or_wget_missing" "$band" "$channel"
        _channel__telemetry_inc "apply_errors"
        return 1
    fi
    
    # Restore SELinux (optional)
    # [ "$selinux_original" = "Enforcing" ] && setenforce 1 2>/dev/null
    
    # ---- Check response ----
    if [ $rc -ne 0 ]; then
        kitsunping_log "error" "channel_apply: HTTP POST failed (rc=$rc, url=$url)"
        _channel__write_apply_status "$response_file" "error" "http_post_failed" "rc=$rc" "$band" "$channel"
        _channel__telemetry_inc "apply_errors"
        rm -f "$tmp_response" 2>/dev/null
        return 1
    fi
    
    if [ ! -s "$tmp_response" ]; then
        kitsunping_log "error" "channel_apply: empty response from router"
        _channel__write_apply_status "$response_file" "error" "empty_response" "router_no_body" "$band" "$channel"
        _channel__telemetry_inc "apply_errors"
        rm -f "$tmp_response" 2>/dev/null
        return 1
    fi
    
    # Move to final location
    mv "$tmp_response" "$response_file" 2>/dev/null
    
    # Parse status
    status="$(_channel__read_cache_field "status" "$response_file")"
    
    if [ "$status" != "ok" ]; then
        local reason="$(_channel__read_cache_field "reason" "$response_file")"
        kitsunping_log "error" "channel_apply: router returned error (status=$status, reason=$reason)"
        _channel__write_apply_status "$response_file" "error" "router_error" "$reason" "$band" "$channel"
        _channel__telemetry_inc "apply_errors"
        return 1
    fi
    
    # ---- Success ----
    kitsunping_log "info" "channel_apply: SUCCESS - channel changed to $channel on band $band"
    _channel__write_apply_status "$response_file" "ok" "applied" "router_confirmed" "$band" "$channel"
    _channel__telemetry_inc "applies"
    
    # Invalidate recommendation cache (channel changed, old recommendation is stale)
    local recommendation_cache="$CHANNEL_CACHE_DIR/router_channel_recommendation.json"
    rm -f "$recommendation_cache" 2>/dev/null
    
    return 0
}
