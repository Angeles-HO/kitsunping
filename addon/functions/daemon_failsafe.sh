#!/system/bin/sh
# Daemon Failsafe System: State corruption recovery and manual rescue trigger
# ============================================================================
# Detects and recovers from state file corruption, enables safe_mode for graceful degradation
# and provides manual rescue trigger for user-initiated recovery without reinstalling module.

# ============== State Validation ==============
# Validate that all critical state files are readable and have valid format
daemon_validate_state_files() {
    local valid=0
    
    # Check daemon.state: must be key=value format, non-empty
    if [ -f "$STATE_FILE" ]; then
        if grep -q '^[a-z_]*\.[a-z_]*=' "$STATE_FILE" 2>/dev/null; then
            valid=$((valid + 1))
        else
            printf '[FAILSAFE] STATE_FILE format invalid: %s\n' "$STATE_FILE" >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi
    
    # Check link_context.state: must have key=value format
    if [ -f "$LINK_CONTEXT_FILE" ]; then
        if grep -q '^link\.' "$LINK_CONTEXT_FILE" 2>/dev/null; then
            valid=$((valid + 1))
        else
            printf '[FAILSAFE] LINK_CONTEXT_FILE format invalid: %s\n' "$LINK_CONTEXT_FILE" >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi
    
    # Check that we can write to cache directory
    if touch "$MODDIR/cache/.write_test" 2>/dev/null; then
        rm -f "$MODDIR/cache/.write_test" 2>/dev/null || true
        valid=$((valid + 1))
    else
        printf '[FAILSAFE] Cannot write to cache directory: %s\n' "$MODDIR/cache" >> "$LOG_FILE" 2>/dev/null || true
    fi
    
    # Return: 3 = all valid, <3 = at least one issue detected
    return $((3 - valid))
}

# ============== Safe Mode Management ==============
# Initialize safe_mode: flag that triggers graceful degradation
daemon_init_safe_mode() {
    local safety_checks_failed=0
    
    # Run all validation checks
    daemon_validate_state_files || safety_checks_failed=1
    
    if [ "$safety_checks_failed" -eq 1 ]; then
        printf '[FAILSAFE] State corruption detected, entering SAFE_MODE\n' >> "$LOG_FILE" 2>/dev/null || true
        touch "$MODDIR/cache/daemon.safe_mode" 2>/dev/null || true
        return 0  # Safe mode enabled
    fi
    
    # Clean up safe_mode flag if no issues detected
    rm -f "$MODDIR/cache/daemon.safe_mode" 2>/dev/null || true
    return 1  # Safe mode not needed
}

# Check if daemon is running in safe_mode
daemon_is_safe_mode() {
    [ -f "$MODDIR/cache/daemon.safe_mode" ]
    return $?
}

# ============== Rescue Trigger ==============
# Check if user requested manual rescue (user can create this file to trigger recovery)
daemon_check_rescue_request() {
    return $([ -f "$MODDIR/cache/daemon.rescue_requested" ])
}

# ============== State Reset & Recovery ==============
# Perform safe rescue: reset state files to known-good defaults without losing connectivity
daemon_perform_rescue() {
    local rescue_dir="$MODDIR/cache/rescue_backup_$(date +%s)"
    
    printf '[FAILSAFE] RESCUE TRIGGERED: backing up current state and initializing recovery\n' >> "$LOG_FILE" 2>/dev/null || true
    
    # Backup current state before reset (in case user needs diagnostics)
    mkdir -p "$rescue_dir" 2>/dev/null || true
    [ -f "$STATE_FILE" ] && cp "$STATE_FILE" "$rescue_dir/daemon.state.backup" 2>/dev/null || true
    [ -f "$LINK_CONTEXT_FILE" ] && cp "$LINK_CONTEXT_FILE" "$rescue_dir/link_context.state.backup" 2>/dev/null || true
    [ -f "$LAST_EVENT_FILE" ] && cp "$LAST_EVENT_FILE" "$rescue_dir/daemon.last.backup" 2>/dev/null || true
    
    # Reset link_context to minimal state (preserve only last_wifi_state to avoid flapping)
    cat > "$LINK_CONTEXT_FILE" << 'EOF'
link.vendor_oui=00:00:00
link.route_changes=0
link.roaming_count=0
link.flap_count=0
link.last_bssid=
link.last_wifi_state=0
EOF
    chmod 0644 "$LINK_CONTEXT_FILE" 2>/dev/null || true
    
    # Reset daemon.state to minimal state (preserve only essential connectivity info)
    cat > "$STATE_FILE" << 'EOF'
daemon.version=7.0-beta
daemon.cycle_count=0
daemon.uptime_sec=0
daemon.safe_mode_recovery=1
net.interface=
net.is_connected=0
net.type=unknown
link.vendor_oui=00:00:00
link.route_changes=0
link.roaming_count=0
link.flap_count=0
EOF
    chmod 0644 "$STATE_FILE" 2>/dev/null || true
    
    # Reset last event (forces fresh event detection on next cycle)
    > "$LAST_EVENT_FILE" 2>/dev/null || true
    
    # Mark rescue completed and disable safe_mode
    rm -f "$MODDIR/cache/daemon.rescue_requested" 2>/dev/null || true
    rm -f "$MODDIR/cache/daemon.safe_mode" 2>/dev/null || true
    
    printf '[FAILSAFE] RESCUE COMPLETE: state files reset, backup at %s\n' "$rescue_dir" >> "$LOG_FILE" 2>/dev/null || true
    printf '[FAILSAFE] User can inspect: %s\n' "$rescue_dir" >> "$LOG_FILE" 2>/dev/null || true
    
    return 0
}

# ============== Safe Mode Degradation ==============
# Reduce cycle frequency and disable expensive operations when in safe_mode
daemon_safe_mode_adjust_sleep() {
    local base_sleep="$1"
    
    # In safe_mode, increase sleep duration by 50% and cap at 30 seconds
    # This reduces CPU load and allows filesystem to stabilize
    if daemon_is_safe_mode; then
        local degraded=$((base_sleep + base_sleep / 2))
        [ "$degraded" -gt 30 ] && degraded=30
        printf '%d' "$degraded"
        return 0
    fi
    
    printf '%d' "$base_sleep"
    return 0
}

# Check if we should skip expensive cycles in safe_mode
daemon_safe_mode_skip_cycle() {
    local cycle_type="$1"  # 'wifi', 'mobile', 'app', 'policy_check'
    
    # In safe_mode, skip non-critical cycles to reduce load
    if daemon_is_safe_mode; then
        case "$cycle_type" in
            app|policy_check)
                # Always skip app and policy triggers in safe_mode
                return 0  # Skip (true)
                ;;
            wifi|mobile)
                # Keep connectivity monitoring even in safe_mode
                return 1  # Don't skip (false)
                ;;
            *)
                return 1
                ;;
        esac
    fi
    
    return 1  # Don't skip in normal mode
}

# Log safe_mode status to user feedback
daemon_safe_mode_log_status() {
    if daemon_is_safe_mode; then
        printf '[DAEMON][SAFE_MODE] Running in degraded mode - state corruption detected\n' >> "$LOG_FILE" 2>/dev/null || true
        printf '[DAEMON][SAFE_MODE] To trigger manual rescue, create: touch %s/cache/daemon.rescue_requested\n' "$MODDIR" >> "$LOG_FILE" 2>/dev/null || true
        printf '[DAEMON][SAFE_MODE] Then restart daemon: kill -TERM $(cat %s/cache/daemon.pid 2>/dev/null)\n' "$MODDIR" >> "$LOG_FILE" 2>/dev/null || true
        return 0
    fi
    return 1
}

# ============== Rescue Documentation ==============
# Write rescue instructions to log and cache
daemon_write_rescue_instructions() {
    cat > "$MODDIR/cache/.rescue_instructions.txt" << 'EOF'
=== DAEMON RESCUE INSTRUCTIONS ===

If daemon enters safe_mode (degraded operation):

1. Request Manual Rescue (from device or ADB):
   adb shell touch /data/adb/modules/Kitsunping/cache/daemon.rescue_requested

2. Restart Daemon:
   adb shell kill -TERM $(adb shell cat /data/adb/modules/Kitsunping/cache/daemon.pid 2>/dev/null)
   
   Or wait 60 seconds for daemon to auto-restart.

3. Check Status:
   adb logcat | grep '\[FAILSAFE\]'
   adb shell tail -f /data/adb/modules/Kitsunping/logs/daemon.log

4. Inspect Backup:
   adb shell ls -la /data/adb/modules/Kitsunping/cache/rescue_backup_*/
   
   State files are backed up automatically during rescue for diagnostics.

5. Manual State Reset (if needed):
   adb shell rm -f /data/adb/modules/Kitsunping/cache/daemon.state
   adb shell rm -f /data/adb/modules/Kitsunping/cache/link_context.state
   
   Daemon will rebuild state on next cycle.

=== NO REINSTALL REQUIRED ===
Rescue is designed to recover without module reinstall.

EOF
    chmod 0644 "$MODDIR/cache/.rescue_instructions.txt" 2>/dev/null || true
}

