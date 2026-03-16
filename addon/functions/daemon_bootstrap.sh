#!/system/bin/sh

daemon_ensure_singleton() {
    log_info "ensuring singleton daemon instance"

    if [ ! -d "${PID_FILE%/*}" ]; then
        mkdir -p "${PID_FILE%/*}" 2>/dev/null || log_warning "could not create pidfile dir"
    fi

    if [ -f "$PID_FILE" ]; then
        local old_pid old_cmd

        old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$old_pid" ] && [ "$old_pid" = "$$" ]; then
            log_debug "pidfile already set to our PID ($old_pid); continuing"
        else
            if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
                old_cmd="$(tr '\0' ' ' < "/proc/$old_pid/cmdline" 2>/dev/null)"
                if printf '%s' "$old_cmd" | grep -Fq "${MODDIR}/addon/daemon/daemon.sh"; then
                    log_warning "daemon already running with PID $old_pid; exiting for no kill/duplicate main process"
                    exit 0
                fi
                log_warning "stale pidfile detected (pid=$old_pid cmd=${old_cmd:-unknown}); replacing"
            fi
        fi
        rm -f "$PID_FILE" 2>/dev/null
    fi

    echo "$$" > "$PID_FILE" 2>/dev/null || log_warning "could not write pidfile"
}

daemon_check_and_detect_commands() {
    check_core_commands awk || { log_error "Missing core commands"; exit 1; }
    detect_ip_binary || { log_error "ip binary not found"; exit 1; }
    detect_ping_binary "$MODDIR/addon/ping" || log_warning "ping binary not found; skipping ping-based checks"

    if command_exists resetprop; then
        RESET_PROP_BIN=$(command -v resetprop 2>/dev/null)
    else
        log_warning "resetprop not found; executor may not apply props"
    fi

    detect_jq_binary
    detect_bc_binary
}

daemon_preflight_check_caps() {
    local caps_file cmd_wifi_low_latency=0 cmd_wifi_hi_perf=0

    caps_file="$MODDIR/cache/preflight.state"
    mkdir -p "$MODDIR/cache" 2>/dev/null || true

    if command -v cmd >/dev/null 2>&1; then
        _caps_out="$(cmd wifi 2>&1)"
        printf '%s' "$_caps_out" | grep -q 'force-low-latency-mode' && cmd_wifi_low_latency=1
        printf '%s' "$_caps_out" | grep -q 'force-hi-perf-mode' && cmd_wifi_hi_perf=1
    fi

    printf 'cmd_wifi_low_latency=%s\ncmd_wifi_hi_perf=%s\n' \
        "$cmd_wifi_low_latency" "$cmd_wifi_hi_perf" > "$caps_file" 2>/dev/null || true
    log_info "preflight: cmd_wifi_low_latency=$cmd_wifi_low_latency cmd_wifi_hi_perf=$cmd_wifi_hi_perf"
}

daemon_apply_boot_custom_profile_once() {
    local boot_profile_raw boot_profile policy_request_file policy_request_priority_file

    boot_profile_raw="$(getprop persist.kitsunping.boot_profile | tr -d '\r\n')"
    boot_profile="$(printf '%s' "$boot_profile_raw" | tr '[:upper:]' '[:lower:]')"

    case "$boot_profile" in
        stable|speed|gaming|benchmark_gaming|benchmark_speed) ;;
        benchmark|benchmarks) boot_profile="benchmark_gaming" ;;
        none|"") return 0 ;;
        *)
            log_warning "boot profile inválido: ${boot_profile_raw:-empty}"
            return 0
            ;;
    esac

    policy_request_file="$MODDIR/cache/policy.request"
    policy_request_priority_file="$MODDIR/cache/policy.request.priority"

    printf '%s' "$boot_profile" > "$policy_request_file" 2>/dev/null || true
    printf '%s' "high" > "$policy_request_priority_file" 2>/dev/null || true

    _boot_ts_file="$MODDIR/cache/policy.boot.ts"
    printf '%s' "$(date +%s 2>/dev/null || echo 0)" > "$_boot_ts_file" 2>/dev/null || true

    if command -v emit_event >/dev/null 2>&1; then
        emit_event "$EV_REQUEST_PROFILE" "source=boot_custom_profile to=$boot_profile from=boot"
    fi
    log_info "boot custom profile aplicado: $boot_profile"
}

daemon_run_bootstrap_init() {
    sleep 5
    daemon_check_and_detect_commands
    daemon_preflight_check_caps
    daemon_ensure_singleton
    daemon_apply_boot_custom_profile_once
}