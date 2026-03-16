#!/system/bin/sh
# state_io.sh — shared cache I/O helpers, state machine, priority utils, policy version
# Sourced by cycle.sh. MODDIR must be set before sourcing.
# Idempotent: safe to source multiple times.
# No side-effects at source time.

# -----------------------------------------------------------------------
# String / token normalization
# -----------------------------------------------------------------------

network__app__normalize_target_token() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

network__app__priority_normalize() {
    case "$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" in
        low|medium|high) printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' ;;
        *) printf '%s' "medium" ;;
    esac
}

# -----------------------------------------------------------------------
# Priority context (QoS weights per profile+priority)
# -----------------------------------------------------------------------

network__app__priority_profile_defaults() {
    local profile="$1" priority="$2"
    case "$profile:$priority" in
        gaming:low)       printf '%s,%s' "22" "10" ;;
        gaming:medium)    printf '%s,%s' "45" "18" ;;
        gaming:high)      printf '%s,%s' "80" "32" ;;
        benchmark:low|benchmark_gaming:low)       printf '%s,%s' "34" "14" ;;
        benchmark:medium|benchmark_gaming:medium) printf '%s,%s' "70" "28" ;;
        benchmark:high|benchmark_gaming:high)     printf '%s,%s' "100" "56" ;;
        benchmark_speed:low)     printf '%s,%s' "50" "80" ;;
        benchmark_speed:medium)  printf '%s,%s' "82" "180" ;;
        benchmark_speed:high)    printf '%s,%s' "100" "320" ;;
        speed:low)        printf '%s,%s' "35" "40" ;;
        speed:medium)     printf '%s,%s' "65" "90" ;;
        speed:high)       printf '%s,%s' "95" "160" ;;
        stable:low)       printf '%s,%s' "15" "8"  ;;
        stable:medium)    printf '%s,%s' "30" "20" ;;
        stable:high)      printf '%s,%s' "50" "35" ;;
        *)                printf '%s,%s' "50" "20" ;;
    esac
}

network__app__priority_apply_context() {
    local profile="$1" priority_raw="$2" priority norm_pair weight min_mbit
    local weight_prop min_mbit_prop

    priority="$(network__app__priority_normalize "$priority_raw")"
    norm_pair="$(network__app__priority_profile_defaults "$profile" "$priority")"
    weight="${norm_pair%%,*}"
    min_mbit="${norm_pair#*,}"

    weight_prop="$(getprop "persist.kitsunping.qos.${profile}.${priority}.weight" 2>/dev/null | tr -d '\r\n')"
    case "$weight_prop" in ''|*[!0-9]*) ;; *) weight="$weight_prop" ;; esac

    min_mbit_prop="$(getprop "persist.kitsunping.qos.${profile}.${priority}.min_mbit" 2>/dev/null | tr -d '\r\n')"
    case "$min_mbit_prop" in ''|*[!0-9]*) ;; *) min_mbit="$min_mbit_prop" ;; esac

    printf '%s' "$priority"   > "$MODDIR/cache/policy.priority"            2>/dev/null || true
    printf '%s' "$weight"     > "$MODDIR/cache/policy.priority.weight"     2>/dev/null || true
    printf '%s' "$min_mbit"   > "$MODDIR/cache/policy.priority.min_mbit"   2>/dev/null || true
}

# -----------------------------------------------------------------------
# Read field from daemon.state (key=value format)
# -----------------------------------------------------------------------

network__app__read_state_field() {
    local key="$1" state_file value
    state_file="$MODDIR/cache/daemon.state"

    [ -n "$key" ] || return 1
    [ -f "$state_file" ] || return 1

    value="$(awk -F'=' -v k="$key" '$1==k { sub(/^[^=]*=/, "", $0); print $0; found=1; exit } END { if (!found) exit 1 }' "$state_file" 2>/dev/null)"
    [ -n "$value" ] || return 1

    printf '%s' "$value"
    return 0
}

# -----------------------------------------------------------------------
# Policy version (bumps monotonically when profile+priority changes)
# -----------------------------------------------------------------------

network__app__policy_version_get() {
    local version_file version

    version_file="$MODDIR/cache/policy.version"
    version=1
    [ -f "$version_file" ] && version="$(cat "$version_file" 2>/dev/null || echo 1)"
    case "$version" in ''|*[!0-9]*) version=1 ;; esac
    [ "$version" -gt 0 ] || version=1
    printf '%s' "$version"
}

network__app__policy_version_touch() {
    local profile="$1" priority="$2"
    local version_file state_file prev_state next_state current_version next_version

    case "$profile" in
        stable|speed|gaming|benchmark|benchmark_gaming|benchmark_speed|normal) ;;
        *) return 0 ;;
    esac
    case "$priority" in
        high|medium|low) ;;
        *) priority="medium" ;;
    esac

    version_file="$MODDIR/cache/policy.version"
    state_file="$MODDIR/cache/policy.version.state"

    next_state="$profile,$priority"
    prev_state=""
    [ -f "$state_file" ] && prev_state="$(cat "$state_file" 2>/dev/null || echo '')"
    if [ "$next_state" = "$prev_state" ]; then
        return 0
    fi

    current_version="$(network__app__policy_version_get)"
    next_version=$((current_version + 1))
    [ "$next_version" -gt 0 ] || next_version=1

    printf '%s' "$next_version" > "$version_file" 2>/dev/null || true
    printf '%s' "$next_state"   > "$state_file"   2>/dev/null || true
    log_info "policy.version bump version=$next_version state=$next_state"
}

# -----------------------------------------------------------------------
# Router status sequence counter
# -----------------------------------------------------------------------

network__app__router_status_next_seq() {
    local seq_file seq

    seq_file="$MODDIR/cache/router.status.seq"
    seq=0
    [ -f "$seq_file" ] && seq="$(cat "$seq_file" 2>/dev/null || echo 0)"
    case "$seq" in ''|*[!0-9]*) seq=0 ;; esac
    seq=$((seq + 1))
    [ "$seq" -gt 0 ] || seq=1
    printf '%s' "$seq" > "$seq_file" 2>/dev/null || true
    printf '%s' "$seq"
}

# -----------------------------------------------------------------------
# Boot ID (stable per-boot identifier)
# -----------------------------------------------------------------------

network__app__module_boot_id_get() {
    local boot_id

    if [ -r /proc/sys/kernel/random/boot_id ]; then
        boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\r\n')"
        [ -n "$boot_id" ] && { printf '%s' "$boot_id"; return 0; }
    fi

    boot_id="$(getprop ro.boot.bootreason 2>/dev/null | tr -d '\r\n')"
    [ -n "$boot_id" ] && { printf '%s' "$boot_id"; return 0; }

    printf 'unknown'
}

# -----------------------------------------------------------------------
# Target state machine (IDLE / APP_OVERRIDE / NETWORK_DECISION / POLICY_APPLIED)
# -----------------------------------------------------------------------

network__app__target_state_get() {
    local state_file state

    state_file="$MODDIR/cache/target.state"
    state=""
    [ -f "$state_file" ] && state="$(cat "$state_file" 2>/dev/null || echo '')"

    case "$state" in
        IDLE|APP_OVERRIDE|NETWORK_DECISION|POLICY_APPLIED)
            printf '%s' "$state"
            ;;
        *)
            printf 'IDLE'
            ;;
    esac
}

network__app__target_state_transition() {
    local next_state="$1" reason="$2"
    local state_file reason_file ts_file history_file current_state current_reason now_ts transition_line

    case "$next_state" in
        IDLE|APP_OVERRIDE|NETWORK_DECISION|POLICY_APPLIED) ;;
        *) return 1 ;;
    esac

    state_file="$MODDIR/cache/target.state"
    reason_file="$MODDIR/cache/target.state.reason"
    ts_file="$MODDIR/cache/target.state.ts"
    history_file="$MODDIR/cache/target.state.history"

    current_state="$(network__app__target_state_get)"
    current_reason=""
    [ -f "$reason_file" ] && current_reason="$(cat "$reason_file" 2>/dev/null || echo '')"

    if [ "$current_state" = "$next_state" ] && [ "$current_reason" = "$reason" ]; then
        return 0
    fi

    now_ts="$(date +%s 2>/dev/null || echo 0)"
    case "$now_ts" in ''|*[!0-9]*) now_ts=0 ;; esac

    printf '%s' "$next_state" > "$state_file"  2>/dev/null || true
    printf '%s' "$reason"     > "$reason_file" 2>/dev/null || true
    printf '%s' "$now_ts"     > "$ts_file"     2>/dev/null || true

    transition_line="${now_ts:-0}|${current_state:-IDLE}|${next_state}|${reason:-none}"
    if [ -f "$history_file" ]; then
        {
            cat "$history_file" 2>/dev/null
            printf '%s\n' "$transition_line"
        } | awk 'NF{buf[NR]=$0} END{start=NR-19; if(start<1) start=1; for(i=start;i<=NR;i++) print buf[i]}' | atomic_write "$history_file"
    else
        printf '%s\n' "$transition_line" | atomic_write "$history_file"
    fi

    log_info "target.state transition from=${current_state:-IDLE} to=$next_state reason=${reason:-none}"
    return 0
}

# -----------------------------------------------------------------------
# Last profile-change timestamp (used by cooldown checks)
# -----------------------------------------------------------------------

network__app__target_mark_profile_change() {
    local now_ts="$1"
    local last_change_file

    case "$now_ts" in ''|*[!0-9]*) return 0 ;; esac
    [ "$now_ts" -gt 0 ] || return 0

    last_change_file="$MODDIR/cache/target.profile_change.last.ts"
    printf '%s' "$now_ts" > "$last_change_file" 2>/dev/null || true
}

# -----------------------------------------------------------------------
# Emit-cooldown gate for reconcile/profile-request events
# -----------------------------------------------------------------------

network__app__target_request_emit_allowed() {
    local emit_sig="$1" now_ts cooldown_raw cooldown_sec
    local ts_file sig_file last_ts last_sig elapsed

    ts_file="$MODDIR/cache/target.request.last.ts"
    sig_file="$MODDIR/cache/target.request.last.sig"

    cooldown_raw="$(getprop persist.kitsunping.target_request_cooldown_sec 2>/dev/null | tr -d '\r\n')"
    case "$cooldown_raw" in
        ''|*[!0-9]*) cooldown_sec=8 ;;
        *)           cooldown_sec="$cooldown_raw" ;;
    esac

    now_ts="$(date +%s 2>/dev/null || echo 0)"
    case "$now_ts" in ''|*[!0-9]*) now_ts=0 ;; esac

    last_ts=0
    [ -f "$ts_file" ] && last_ts="$(cat "$ts_file" 2>/dev/null || echo 0)"
    case "$last_ts" in ''|*[!0-9]*) last_ts=0 ;; esac

    last_sig=""
    [ -f "$sig_file" ] && last_sig="$(cat "$sig_file" 2>/dev/null || echo "")"

    if [ "$emit_sig" = "$last_sig" ] && [ "$cooldown_sec" -gt 0 ] && \
       [ "$now_ts" -gt 0 ] && [ "$last_ts" -gt 0 ]; then
        elapsed=$((now_ts - last_ts))
        [ "$elapsed" -lt 0 ] && elapsed=0
        if [ "$elapsed" -lt "$cooldown_sec" ]; then
            return 1
        fi
    fi

    printf '%s' "$now_ts"   > "$ts_file"  2>/dev/null || true
    printf '%s' "$emit_sig" > "$sig_file" 2>/dev/null || true
    return 0
}

# -----------------------------------------------------------------------
# Operational telemetry counters (cumulative integers in cache/telemetry.*)
# Usage: network__app__telemetry_counter_inc op_errors
#        network__app__telemetry_counter_inc tweak_restores
# -----------------------------------------------------------------------

network__app__telemetry_counter_inc() {
    local name="$1" counter_file val
    [ -n "$name" ] || return 0
    counter_file="$MODDIR/cache/telemetry.${name}"
    val=0
    [ -f "$counter_file" ] && val="$(cat "$counter_file" 2>/dev/null || echo 0)"
    case "$val" in ''|*[!0-9]*) val=0 ;; esac
    val=$((val + 1))
    printf '%s' "$val" > "$counter_file" 2>/dev/null || true
}

network__app__telemetry_counter_read() {
    local name="$1" counter_file val
    counter_file="$MODDIR/cache/telemetry.${name}"
    val=0
    [ -f "$counter_file" ] && val="$(cat "$counter_file" 2>/dev/null || echo 0)"
    case "$val" in ''|*[!0-9]*) val=0 ;; esac
    printf '%s' "$val"
}

# -----------------------------------------------------------------------
# Runtime JSON export — writes /tmp/kitsunping_runtime.json for diagnosis.
# Rate-limited: at most once every RUNTIME_EXPORT_INTERVAL_SEC (default 60).
# Safe to call every daemon tick; exits early if too soon.
# -----------------------------------------------------------------------

network__app__runtime_export() {
    local now_ts interval last_ts elapsed out_file tmp_file
    local paired_flag router_id router_ip
    local profile_current profile_target target_state target_state_reason
    local profile_selector profile_mismatch
    local tel_changes_hour tel_tweak_restores tel_op_errors
    local kpi_rollbacks_hour kpi_mean_apply_ms _kpi_file
    local wifi_score_v wifi_state_v transport_v profile_v
    local daemon_pid uptime_s boot_id
    local link_vendor_oui_v link_route_changes_v link_roaming_count_v link_flap_count_v

    # ---- rate-limit ----
    interval="${RUNTIME_EXPORT_INTERVAL_SEC:-60}"
    case "$interval" in ''|*[!0-9]*) interval=60 ;; esac
    [ "$interval" -lt 10 ] && interval=10

    now_ts="$(date +%s 2>/dev/null || echo 0)"
    case "$now_ts" in ''|*[!0-9]*) now_ts=0 ;; esac

    last_ts=0
    out_file="$MODDIR/cache/kitsunping_runtime.json"
    [ -f "${out_file}.ts" ] && last_ts="$(cat "${out_file}.ts" 2>/dev/null || echo 0)"
    case "$last_ts" in ''|*[!0-9]*) last_ts=0 ;; esac
    elapsed=$((now_ts - last_ts))
    [ "$elapsed" -lt 0 ] && elapsed=0
    [ "$elapsed" -lt "$interval" ] && return 0

    # ---- read state ----
    profile_current="$(cat "$MODDIR/cache/policy.current"     2>/dev/null || echo "")"
    profile_target="$(cat  "$MODDIR/cache/policy.target"      2>/dev/null || echo "")"
    target_state="$(network__app__target_state_get)"
    target_state_reason="$(cat "$MODDIR/cache/target.state.reason" 2>/dev/null || echo "")"

    # pairing
    paired_flag="0"
    router_id=""
    router_ip=""
    if command -v get_router_paired_flag >/dev/null 2>&1; then
        paired_flag="$(get_router_paired_flag 2>/dev/null || echo 0)"
    fi
    if [ -f "${ROUTER_PAIRING_CACHE_FILE:-}" ]; then
        router_id="$(network__app__read_pairing_json_field "router_id" "$ROUTER_PAIRING_CACHE_FILE" 2>/dev/null || echo "")"
        router_ip="$(network__app__read_pairing_json_field "router_ip" "$ROUTER_PAIRING_CACHE_FILE" 2>/dev/null || echo "")"
    fi

    # daemon state flat fields
    wifi_score_v="$(cat "$MODDIR/cache/daemon.state" 2>/dev/null | awk -F= '$1=="wifi.score"{print $2}' | tail -n1 || echo 0)"
    wifi_state_v="$(cat "$MODDIR/cache/daemon.state" 2>/dev/null | awk -F= '$1=="wifi.state"{print $2}' | tail -n1 || echo "")"
    transport_v="$(cat  "$MODDIR/cache/daemon.state" 2>/dev/null | awk -F= '$1=="transport"{print $2}'  | tail -n1 || echo "")"
    profile_v="$(cat    "$MODDIR/cache/daemon.state" 2>/dev/null | awk -F= '$1=="profile"{print $2}'    | tail -n1 || echo "")"
    link_vendor_oui_v="$(cat "$MODDIR/cache/daemon.state" 2>/dev/null | awk -F= '$1=="link.vendor_oui"{print $2}' | tail -n1 || echo "")"
    link_route_changes_v="$(cat "$MODDIR/cache/daemon.state" 2>/dev/null | awk -F= '$1=="link.route_changes"{print $2}' | tail -n1 || echo 0)"
    link_roaming_count_v="$(cat "$MODDIR/cache/daemon.state" 2>/dev/null | awk -F= '$1=="link.roaming_count"{print $2}' | tail -n1 || echo 0)"
    link_flap_count_v="$(cat "$MODDIR/cache/daemon.state" 2>/dev/null | awk -F= '$1=="link.flap_count"{print $2}' | tail -n1 || echo 0)"
    profile_selector="$profile_v"
    profile_mismatch=0
    if [ -n "$profile_selector" ] && [ -n "$profile_current" ] && [ "$profile_selector" != "$profile_current" ]; then
        profile_mismatch=1
    fi
    case "$wifi_score_v"  in ''|*[!0-9]*) wifi_score_v=0 ;; esac
    case "$link_route_changes_v" in ''|*[!0-9]*) link_route_changes_v=0 ;; esac
    case "$link_roaming_count_v" in ''|*[!0-9]*) link_roaming_count_v=0 ;; esac
    case "$link_flap_count_v" in ''|*[!0-9]*) link_flap_count_v=0 ;; esac

    # telemetry counters
    tel_tweak_restores="$(network__app__telemetry_counter_read "tweak_restores")"
    tel_op_errors="$(network__app__telemetry_counter_read "op_errors")"
    _kpi_file="$MODDIR/cache/executor.kpi.hourly"
    tel_changes_hour=0; kpi_rollbacks_hour=0; kpi_mean_apply_ms=0
    if [ -f "$_kpi_file" ]; then
        tel_changes_hour="$(awk -F= '$1=="kpi.changes_hour"  {print $2+0}' "$_kpi_file" 2>/dev/null || echo 0)"
        kpi_rollbacks_hour="$(awk -F= '$1=="kpi.rollbacks_hour" {print $2+0}' "$_kpi_file" 2>/dev/null || echo 0)"
        kpi_mean_apply_ms="$(awk -F= '$1=="kpi.apply_sum_ms"    {print $2+0}' "$_kpi_file" 2>/dev/null || echo 0)"
    fi
    case "$tel_changes_hour"  in ''|*[!0-9]*) tel_changes_hour=0  ;; esac
    case "$kpi_rollbacks_hour" in ''|*[!0-9]*) kpi_rollbacks_hour=0 ;; esac
    case "$kpi_mean_apply_ms"  in ''|*[!0-9]*) kpi_mean_apply_ms=0  ;; esac

    # process info
    daemon_pid="$(cat "$MODDIR/cache/daemon.pid" 2>/dev/null | tr -d '\r\n' || echo 0)"
    case "$daemon_pid" in ''|*[!0-9]*) daemon_pid=0 ;; esac
    boot_id="$(network__app__module_boot_id_get)"
    uptime_s=0
    [ -r /proc/uptime ] && uptime_s="$(awk '{printf "%.0f", $1}' /proc/uptime 2>/dev/null || echo 0)"

    # ---- write ----
    tmp_file="${out_file}.tmp.$$"
    printf '%s' "{\"ts\":$now_ts,\"uptime_s\":$uptime_s,\"boot_id\":\"${boot_id}\",\"daemon_pid\":$daemon_pid,\"transport\":\"${transport_v:-unknown}\",\"wifi\":{\"state\":\"${wifi_state_v:-unknown}\",\"score\":$wifi_score_v},\"profile\":{\"current\":\"${profile_current:-unknown}\",\"target\":\"${profile_target:-unknown}\",\"selector\":\"${profile_selector:-unknown}\",\"daemon\":\"${profile_v:-unknown}\",\"mismatch\":$profile_mismatch},\"target_state\":{\"state\":\"${target_state}\",\"reason\":\"${target_state_reason}\"},\"pairing\":{\"paired\":${paired_flag:-0},\"router_id\":\"${router_id:-}\",\"router_ip\":\"${router_ip:-}\"},\"link\":{\"vendor_oui\":\"${link_vendor_oui_v:-}\",\"route_changes\":$link_route_changes_v,\"roaming_count\":$link_roaming_count_v,\"flap_count\":$link_flap_count_v},\"telemetry\":{\"changes_hour\":$tel_changes_hour,\"rollbacks_hour\":$kpi_rollbacks_hour,\"mean_apply_ms\":$kpi_mean_apply_ms,\"tweak_restores\":$tel_tweak_restores,\"op_errors\":$tel_op_errors}}" > "$tmp_file" 2>/dev/null
    if [ -s "$tmp_file" ]; then
        mv "$tmp_file" "$out_file" 2>/dev/null || { rm -f "$tmp_file" 2>/dev/null; return 1; }
        printf '%s' "$now_ts" > "${out_file}.ts" 2>/dev/null || true
        log_debug "runtime_export ok ts=$now_ts path=$out_file"
    else
        rm -f "$tmp_file" 2>/dev/null || true
    fi
    return 0
}
