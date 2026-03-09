#!/system/bin/sh
# cycle.sh — thin orchestrator
# Phases in dependency order:
#   1. state_io.sh      — cache I/O helpers, priority utils, state machine
#   2. pairing_gate.sh  — router pairing gate (never blocks local profiles)
#   3. target_engine.sh — foreground app → target.prop → policy.request
#   4. router_push.sh   — HTTP push to router, fully decoupled from profile logic
#   5. router_channel.sh — WiFi channel recommendation from router (optional feature)
#
# Robustness rule: local profile switching (target_engine) works regardless
#                  of router or pairing state.

_CYCLE_APP_DIR="${MODDIR}/network/app"

# shellcheck source=state_io.sh
. "${_CYCLE_APP_DIR}/state_io.sh"
# shellcheck source=pairing_gate.sh
. "${_CYCLE_APP_DIR}/pairing_gate.sh"
# shellcheck source=target_engine.sh
. "${_CYCLE_APP_DIR}/target_engine.sh"
# shellcheck source=router_push.sh
. "${_CYCLE_APP_DIR}/router_push.sh"
# shellcheck source=router_channel.sh
. "${_CYCLE_APP_DIR}/router_channel.sh"

# -----------------------------------------------------------------------
# Backward-compatibility aliases (called by daemon.sh and external scripts)
# -----------------------------------------------------------------------

daemon_run_app_event_cycle()           { network__app__event_cycle "$@"; }
daemon_run_pairing_sync_cycle()        { network__app__pairing_sync_cycle "$@"; }
daemon_run_target_profile_cycle()      { network__app__target_profile_cycle "$@"; }
daemon_run_router_status_push_cycle()  { network__app__router_status_push_cycle "$@"; }
daemon_run_channel_recommend_request() { network__router__channel_recommend_request "$@"; }

normalize_target_token()               { network__app__normalize_target_token "$@"; }
target_prop_lookup_profile()           { network__app__target_prop_lookup_profile "$@"; }
daemon_detect_foreground_package()     { network__app__detect_foreground_package "$@"; }
target_request_emit_allowed()          { network__app__target_request_emit_allowed "$@"; }
read_pairing_json_field()              { network__app__read_pairing_json_field "$@"; }
daemon_get_wifi_client_mac()           { network__app__get_wifi_client_mac "$@"; }
router_send_module_status()            { network__app__router_send_module_status "$@"; }
router_channel_get_cached()            { network__router__channel_get_cached "$@"; }
router_channel_has_better_option()     { network__router__channel_has_better_option "$@"; }

network_app_event_cycle()              { network__app__event_cycle "$@"; }
network_app_pairing_sync_cycle()       { network__app__pairing_sync_cycle "$@"; }
network_app_target_profile_cycle()     { network__app__target_profile_cycle "$@"; }
network_app_router_status_push_cycle() { network__app__router_status_push_cycle "$@"; }

# -----------------------------------------------------------------------
# Smart channel recommendation trigger (M1-M2)
# Requests channel scan when wifi_score < threshold sustained for N+ consecutive iterations
# M2: Configurable via setprop kitsuneping.channel.*
# -----------------------------------------------------------------------

_CHANNEL_LOW_SCORE_ITERATIONS=0  # consecutive iterations with low wifi score

# Configuration (override via setprop)
CHANNEL_SCAN_THRESHOLD="${CHANNEL_SCAN_THRESHOLD:-65}"
CHANNEL_TRIGGER_MIN_ITERATIONS="${CHANNEL_TRIGGER_MIN_ITERATIONS:-3}"

# Load overrides from props
_trigger_threshold="$(getprop kitsuneping.channel.score_threshold 2>/dev/null | tr -d '\r\n')"
_trigger_iterations="$(getprop kitsuneping.channel.trigger_iterations 2>/dev/null | tr -d '\r\n')"
[ -n "$_trigger_threshold" ] && [ "$_trigger_threshold" -ge 10 ] && [ "$_trigger_threshold" -le 100 ] && \
    CHANNEL_SCAN_THRESHOLD="$_trigger_threshold"
[ -n "$_trigger_iterations" ] && [ "$_trigger_iterations" -ge 1 ] && [ "$_trigger_iterations" -le 10 ] && \
    CHANNEL_TRIGGER_MIN_ITERATIONS="$_trigger_iterations"

daemon_run_channel_smart_trigger() {
    # Only trigger on WiFi
    local current_iface
    current_iface="$(get_current_iface)"
    [ "$current_iface" != "wlan0" ] && {
        _CHANNEL_LOW_SCORE_ITERATIONS=0
        return 0
    }

    # Only trigger if paired
    local pairing_ok
    pairing_ok="$(network__app__read_state_field pairing_ok)"
    [ "$pairing_ok" != "1" ] && {
        _CHANNEL_LOW_SCORE_ITERATIONS=0
        return 0
    }

    # Read current wifi score
    local wifi_score
    wifi_score="$(network__app__read_state_field wifi_score)"
    [ -z "$wifi_score" ] && wifi_score=100

    # Check if score is below threshold
    if [ "$wifi_score" -lt "$CHANNEL_SCAN_THRESHOLD" ]; then
        _CHANNEL_LOW_SCORE_ITERATIONS=$((_CHANNEL_LOW_SCORE_ITERATIONS + 1))
        
        # Trigger request if sustained for minimum iterations
        if [ "$_CHANNEL_LOW_SCORE_ITERATIONS" -ge "$CHANNEL_TRIGGER_MIN_ITERATIONS" ]; then
            log_info "[channel_trigger] WiFi score $wifi_score sustained for ${_CHANNEL_LOW_SCORE_ITERATIONS} iterations (threshold=$CHANNEL_TRIGGER_MIN_ITERATIONS), requesting scan"
            
            # Detect band from interface properties (2.4GHz vs 5GHz)
            # For now, default to 2.4GHz as it's most common problem band
            # TODO: read actual band from daemon.state or link_context
            local band="2.4GHz"
            
            # Request with force=0 (respects internal rate-limit and guards)
            network__router__channel_recommend_request "$band" "0"
            local req_result=$?
            
            # Reset counter to avoid spamming (request function has its own rate-limit)
            _CHANNEL_LOW_SCORE_ITERATIONS=0
            
            # M2: Log result for observability
            case $req_result in
                0) log_info "[channel_trigger] auto-request completed successfully" ;;
                1) log_info "[channel_trigger] auto-request skipped: pairing inactive or feature disabled" ;;
                2) log_info "[channel_trigger] auto-request rate-limited" ;;
                3) log_info "[channel_trigger] auto-request skipped: score recovered" ;;
                *) log_warning "[channel_trigger] auto-request failed: code=$req_result" ;;
            esac
        else
            # M2: Log progress toward threshold
            [ "$((_CHANNEL_LOW_SCORE_ITERATIONS % 2))" -eq 0 ] && \
                log_info "[channel_trigger] low score ($wifi_score) iteration ${_CHANNEL_LOW_SCORE_ITERATIONS}/${CHANNEL_TRIGGER_MIN_ITERATIONS}"
        fi
    else
        # Score is good, reset counter
        [ "$_CHANNEL_LOW_SCORE_ITERATIONS" -gt 0 ] && \
            log_info "[channel_trigger] WiFi score recovered ($wifi_score), resetting counter (was ${_CHANNEL_LOW_SCORE_ITERATIONS})"
        _CHANNEL_LOW_SCORE_ITERATIONS=0
    fi
}

