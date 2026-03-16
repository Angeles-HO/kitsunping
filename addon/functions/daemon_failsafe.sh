#!/system/bin/sh
# Daemon Failsafe System: State corruption recovery and manual rescue trigger
# ============================================================================
# Detects and recovers from state file corruption, enables safe_mode for graceful degradation
# and provides manual rescue trigger for user-initiated recovery without reinstalling module.

# ============== State Validation ==============
# Validate that all critical state files are readable and have valid format
daemon_validate_state_files() {
    local valid=0

    # Check daemon.state: absent = fresh start (ok); exists = must have dotted key=value format
    if [ -f "$STATE_FILE" ]; then
        if grep -q '^[a-z_]*\.[a-z_]*=' "$STATE_FILE" 2>/dev/null; then
            valid=$((valid + 1))
        else
            printf '[FAILSAFE] STATE_FILE format invalid: %s\n' "$STATE_FILE" >> "$LOG_FILE" 2>/dev/null || true
        fi
    else
        valid=$((valid + 1))  # absent = clean start, not corruption
    fi

    # Check link_context.state: absent = fresh start (ok); exists = must have key=value format
    if [ -f "$LINK_CONTEXT_FILE" ]; then
        if grep -qE '^[a-z_]+=' "$LINK_CONTEXT_FILE" 2>/dev/null; then
            valid=$((valid + 1))
        else
            printf '[FAILSAFE] LINK_CONTEXT_FILE format invalid: %s\n' "$LINK_CONTEXT_FILE" >> "$LOG_FILE" 2>/dev/null || true
        fi
    else
        valid=$((valid + 1))  # absent = clean start, not corruption
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

daemon_get_validation_failure_count() {
    local guard_file="$MODDIR/cache/daemon.validation_fail_count"
    if [ ! -f "$guard_file" ]; then
        printf '0'
        return 0
    fi
    local raw
    raw="$(cat "$guard_file" 2>/dev/null | tr -d '\r\n')"
    case "$raw" in
        ''|*[!0-9]*) printf '0' ;;
        *) printf '%s' "$raw" ;;
    esac
    return 0
}

daemon_set_validation_failure_count() {
    local value="$1"
    local guard_file="$MODDIR/cache/daemon.validation_fail_count"
    printf '%s\n' "$value" > "$guard_file" 2>/dev/null || true
    chmod 0644 "$guard_file" 2>/dev/null || true
}

daemon_reset_validation_failure_count() {
    rm -f "$MODDIR/cache/daemon.validation_fail_count" 2>/dev/null || true
}

daemon_attempt_state_self_heal() {
    local ts repaired=0
    ts="$(date +%s 2>/dev/null || printf '0')"

    if [ -f "$STATE_FILE" ] && ! grep -q '^[a-z_]*\.[a-z_]*=' "$STATE_FILE" 2>/dev/null; then
        cp "$STATE_FILE" "$MODDIR/cache/daemon.state.corrupt.$ts" 2>/dev/null || true
        cat > "$STATE_FILE" << 'EOF'
daemon.version=7.0-beta
daemon.cycle_count=0
daemon.uptime_sec=0
daemon.self_healed=1
net.interface=
net.is_connected=0
net.type=unknown
link.vendor_oui=00:00:00
link.route_changes=0
link.roaming_count=0
link.flap_count=0
EOF
        chmod 0644 "$STATE_FILE" 2>/dev/null || true
        printf '[FAILSAFE][AUTOHEAL] Rebuilt daemon.state from minimal template (backup: daemon.state.corrupt.%s)\n' "$ts" >> "$LOG_FILE" 2>/dev/null || true
        repaired=1
    fi

    if [ -f "$LINK_CONTEXT_FILE" ] && ! grep -qE '^[a-z_]+=' "$LINK_CONTEXT_FILE" 2>/dev/null; then
        cp "$LINK_CONTEXT_FILE" "$MODDIR/cache/link_context.state.corrupt.$ts" 2>/dev/null || true
        cat > "$LINK_CONTEXT_FILE" << 'EOF'
vendor_oui=00:00:00
route_changes=0
roaming_count=0
flap_count=0
last_bssid=
last_wifi_state=unknown
EOF
        chmod 0644 "$LINK_CONTEXT_FILE" 2>/dev/null || true
        printf '[FAILSAFE][AUTOHEAL] Rebuilt link_context.state from minimal template (backup: link_context.state.corrupt.%s)\n' "$ts" >> "$LOG_FILE" 2>/dev/null || true
        repaired=1
    fi

    [ "$repaired" -eq 1 ]
    return $?
}

# ============== Safe Mode Management ==============
# Initialize safe_mode: flag that triggers graceful degradation
daemon_init_safe_mode() {
    local safety_checks_failed=0 failure_count=0
    
    # Run all validation checks
    daemon_validate_state_files || safety_checks_failed=1
    
    if [ "$safety_checks_failed" -eq 1 ]; then
        failure_count="$(daemon_get_validation_failure_count)"
        failure_count=$((failure_count + 1))
        daemon_set_validation_failure_count "$failure_count"

        if [ "$failure_count" -lt 2 ]; then
            printf '[FAILSAFE][WARN] Validation failed (%s/2). Delaying SAFE_MODE to avoid false positives and attempting auto-heal.\n' "$failure_count" >> "$LOG_FILE" 2>/dev/null || true
            daemon_attempt_state_self_heal || true
            rm -f "$MODDIR/cache/daemon.safe_mode" 2>/dev/null || true
            # Update description even on delayed safe-mode so module.prop is never stale.
            if command -v daemon_set_module_status >/dev/null 2>&1; then
                daemon_set_module_status "startup"
            fi
            return 1
        fi

        printf '[FAILSAFE] State corruption detected, entering SAFE_MODE\n' >> "$LOG_FILE" 2>/dev/null || true
        touch "$MODDIR/cache/daemon.safe_mode" 2>/dev/null || true
        
        # Update module status to reflect safe_mode
        if command -v daemon_set_module_status >/dev/null 2>&1; then
            daemon_set_module_status "safe_mode"
        fi
        
        return 0  # Safe mode enabled
    fi

    daemon_reset_validation_failure_count

    # No issues detected: always refresh visible status to OK.
    # daemon_update_module_description() handles one-time backup creation safely.
    if command -v daemon_set_module_status >/dev/null 2>&1; then
        daemon_set_module_status "ok"
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
    
    # Update module status to "recovering"
    if command -v daemon_set_module_status >/dev/null 2>&1; then
        daemon_set_module_status "recovering"
    fi
    
    # Backup current state before reset (in case user needs diagnostics)
    mkdir -p "$rescue_dir" 2>/dev/null || true
    [ -f "$STATE_FILE" ] && cp "$STATE_FILE" "$rescue_dir/daemon.state.backup" 2>/dev/null || true
    [ -f "$LINK_CONTEXT_FILE" ] && cp "$LINK_CONTEXT_FILE" "$rescue_dir/link_context.state.backup" 2>/dev/null || true
    [ -f "$LAST_EVENT_FILE" ] && cp "$LAST_EVENT_FILE" "$rescue_dir/daemon.last.backup" 2>/dev/null || true
    
    # Reset link_context to minimal state (keys must match daemon_link_context_load parser)
    cat > "$LINK_CONTEXT_FILE" << 'EOF'
vendor_oui=00:00:00
route_changes=0
roaming_count=0
flap_count=0
last_bssid=
last_wifi_state=unknown
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
    
    # Update module status to "recovery_complete"
    if command -v daemon_set_module_status >/dev/null 2>&1; then
        daemon_set_module_status "recovery_complete"
    fi
    
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
        printf '[DAEMON][SAFE_MODE] Module status visible in: Magisk Manager → Kitsunping\n' >> "$LOG_FILE" 2>/dev/null || true
        printf '[DAEMON][SAFE_MODE] To trigger manual rescue, create: touch %s/cache/daemon.rescue_requested\n' "$MODDIR" >> "$LOG_FILE" 2>/dev/null || true
        printf '[DAEMON][SAFE_MODE] Then restart daemon: kill -TERM $(cat %s/cache/daemon.pid 2>/dev/null)\n' "$MODDIR" >> "$LOG_FILE" 2>/dev/null || true
        return 0
    fi
    printf '[DAEMON] Normal operation - all systems OK\n' >> "$LOG_FILE" 2>/dev/null || true
    return 1
}

# ============== Module Status Management ==============
# HYBRID Status Definitions:
# 1) Try cache/module_status.json (if present)
# 2) Fallback to embedded defaults (startup-safe if JSON is missing)

daemon_status_json_get() {
    local status_type="$1"
    local field="$2"
    local json_file="$MODDIR/cache/module_status.json"
    local result

    [ -f "$json_file" ] || return 1

    result="$(awk -v st="\"$status_type\"" -v fd="\"$field\"" '
        BEGIN { in_statuses=0; in_target=0 }
        /"statuses"[[:space:]]*:[[:space:]]*\{/ { in_statuses=1; next }
        in_statuses && $0 ~ st"[[:space:]]*:[[:space:]]*\\{" { in_target=1; next }
        in_target && /^[[:space:]]*\}[[:space:]]*,?[[:space:]]*$/ { in_target=0 }
        in_target && $0 ~ fd"[[:space:]]*:[[:space:]]*" {
            line=$0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line ~ /^\"/) {
                sub(/^\"/, "", line)
                sub(/\",?[[:space:]]*$/, "", line)
            } else {
                sub(/,?[[:space:]]*$/, "", line)
            }
            print line
            exit
        }
    ' "$json_file" 2>/dev/null)"

    [ -n "$result" ] || return 1
    printf '%s' "$result"
    return 0
}

daemon_status_json_top_get() {
    local field="$1"
    local json_file="$MODDIR/cache/module_status.json"
    local result

    [ -f "$json_file" ] || return 1

    result="$(awk -v fd="\"$field\"" '
        $0 ~ "^[[:space:]]*"fd"[[:space:]]*:[[:space:]]*" {
            line=$0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line ~ /^\"/) {
                sub(/^\"/, "", line)
                sub(/\",?[[:space:]]*$/, "", line)
            } else {
                sub(/,?[[:space:]]*$/, "", line)
            }
            print line
            exit
        }
    ' "$json_file" 2>/dev/null)"

    [ -n "$result" ] || return 1
    printf '%s' "$result"
    return 0
}

daemon_get_status_base() {
    local mid ver

    mid="$(daemon_status_json_top_get "module_id" 2>/dev/null || true)"
    ver="$(daemon_status_json_top_get "version" 2>/dev/null || true)"

    if [ -n "$mid" ] && [ -n "$ver" ]; then
        printf '%s v%s' "$mid" "$ver"
        return 0
    fi

    # Embedded fallback
    printf '%s' "Kitsunping v7.0-beta"
    return 0
}

daemon_get_status_suffix() {
    local status_type="$1"
    local from_json

    from_json="$(daemon_status_json_get "$status_type" "description_suffix" 2>/dev/null || true)"
    if [ -n "$from_json" ]; then
        printf '%s' "$from_json"
        return 0
    fi

    case "$status_type" in
        ok)
            printf '%s' "Network improvements and stability enhancements TCP, PPC, wifi/Mobile"
            ;;
        safe_mode)
            printf '%s' "[SAFE MODE]"
            ;;
        broken_environment)
            printf '%s' "[BROKEN ENV]"
            ;;
        conflict_detected)
            printf '%s' "[CONFLICT]"
            ;;
        recovering)
            printf '%s' "[RECOVERING]"
            ;;
        recovery_complete)
            printf '%s' "[RECOVERED]"
            ;;
        startup)
            printf '%s' "[STARTING]"
            ;;
        *)
            printf '%s' "[UNKNOWN]"
            return 1
            ;;
    esac
    return 0
}

daemon_get_status_description() {
    local status_type="$1"  # 'ok', 'safe_mode', 'broken_environment', etc.
    local base suffix

    base="$(daemon_get_status_base)"
    suffix="$(daemon_get_status_suffix "$status_type")"

    [ -n "$base" ] || base="Kitsunping v7.0-beta"
    [ -n "$suffix" ] || suffix="[UNKNOWN]"

    case "$suffix" in
        \[*\]) printf '%s %s' "$base" "$suffix" ;;
        *) printf '%s - %s' "$base" "$suffix" ;;
    esac
    return 0
}

# Extract status details (help text)
daemon_get_status_details() {
    local status_type="$1"
    local from_json

    from_json="$(daemon_status_json_get "$status_type" "details" 2>/dev/null || true)"
    if [ -n "$from_json" ]; then
        printf '%s' "$from_json"
        return 0
    fi
    
    case "$status_type" in
        ok)
            printf '%s' "WiFi 2.4G/5G + TCP + LTE/LTE-A + PPC"
            ;;
        safe_mode)
            printf '%s' "Safe Mode - State corruption detected, degraded operation"
            ;;
        broken_environment)
            printf '%s' "Critical error - module disabled for safety"
            ;;
        conflict_detected)
            printf '%s' "Conflict - Other modules interfering with network paths"
            ;;
        recovering)
            printf '%s' "Recovering - Rescue in progress, please wait..."
            ;;
        recovery_complete)
            printf '%s' "Recovery Complete - State reset, daemon restarting"
            ;;
        startup)
            printf '%s' "Starting - Initializing daemon..."
            ;;
        *)
            printf '%s' "Unknown status"
            return 1
            ;;
    esac
    return 0
}

# Check if status should have disable flag
daemon_should_disable_module() {
    local status_type="$1"
    local disable_value
    local disable_norm

    disable_value="$(daemon_status_json_get "$status_type" "disable" 2>/dev/null || true)"
    disable_norm="$(printf '%s' "$disable_value" | tr 'A-Z' 'a-z')"
    case "$disable_norm" in
        true)
            return 0  # Should disable (true)
            ;;
        false)
            return 1  # Should not disable (false)
            ;;
    esac

    if [ -n "$disable_value" ]; then
        printf '[FAILSAFE][WARN] Invalid disable value in module_status.json: status=%s disable=%s\n' "$status_type" "$disable_value" >> "$LOG_FILE" 2>/dev/null || true
    fi
    
    # Embedded fallback: only broken_environment disables the module
    case "$status_type" in
        broken_environment)
            return 0  # Should disable (true)
            ;;
        *)
            return 1  # Should not disable (false)
            ;;
    esac
}

# Update module.prop with new description and details
daemon_module_prop_set_field() {
    local file_path="$1" key="$2" value="$3"
    local tmp_file

    [ -n "$file_path" ] || return 1
    [ -f "$file_path" ] || return 1
    [ -n "$key" ] || return 1

    tmp_file="${file_path}.tmp.$$"
    awk -v k="$key" -v v="$value" '
        BEGIN { updated=0 }
        $0 ~ "^" k "=" {
            print k "=" v
            updated=1
            next
        }
        { print }
        END {
            if (!updated) {
                print k "=" v
            }
        }
    ' "$file_path" > "$tmp_file" 2>/dev/null || {
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }

    mv "$tmp_file" "$file_path" 2>/dev/null || {
        # SELinux may block mv across contexts; fallback to in-place write.
        if cat "$tmp_file" > "$file_path" 2>/dev/null; then
            rm -f "$tmp_file" 2>/dev/null || true
            return 0
        fi
        rm -f "$tmp_file" 2>/dev/null || true
        return 1
    }
    return 0
}

daemon_update_module_description() {
    local status_type="$1"  # 'ok', 'safe_mode', 'broken_environment', etc.
    local module_prop="$MODDIR/module.prop"
    
    if [ ! -f "$module_prop" ]; then
        printf '[FAILSAFE] module.prop not found: %s\n' "$module_prop" >> "$LOG_FILE" 2>/dev/null || true
        return 1
    fi
    
    local desc details
    desc="$(daemon_get_status_description "$status_type")"
    details="$(daemon_get_status_details "$status_type")"
    
    if [ -z "$desc" ]; then
        printf '[FAILSAFE] Could not resolve status description for: %s\n' "$status_type" >> "$LOG_FILE" 2>/dev/null || true
        return 1
    fi
    
    # Backup original module.prop (once)
    if [ ! -f "$MODDIR/cache/module.prop.original" ]; then
        cp "$module_prop" "$MODDIR/cache/module.prop.original" 2>/dev/null || true
    fi
    
    # Keep module.prop single-line fields; strip CR/LF from dynamic payloads.
    # Magisk Manager only shows: name, version, author, description.
    # Merge details into description so everything is visible in one line.
    local full_desc
    if [ -n "$details" ] && [ "$status_type" != "ok" ]; then
        full_desc="$(printf '%s | %s' "$desc" "$details" | tr '\r\n' '  ')"
    else
        full_desc="$(printf '%s' "$desc" | tr '\r\n' '  ')"
    fi

    if ! daemon_module_prop_set_field "$module_prop" "description" "$full_desc"; then
        printf '[FAILSAFE][WARN] Could not update description in module.prop (check permissions): %s\n' "$module_prop" >> "$LOG_FILE" 2>/dev/null || true
    fi

    # Ensure module.prop keeps correct permissions and SELinux context after write.
    chmod 0644 "$module_prop" 2>/dev/null || true
    if command -v restorecon >/dev/null 2>&1; then
        restorecon "$module_prop" 2>/dev/null || true
    fi
    
    printf '[FAILSAFE] Updated module.prop status: %s\n' "$status_type" >> "$LOG_FILE" 2>/dev/null || true
    return 0
}

# Create or remove disable file (standard Magisk mechanism)
daemon_write_disable_file() {
    local disable_file="$MODDIR/disable"
    touch "$disable_file" 2>/dev/null || true
    printf '[FAILSAFE] Module disable flag set at: %s\n' "$disable_file" >> "$LOG_FILE" 2>/dev/null || true
}

daemon_remove_disable_file() {
    local disable_file="$MODDIR/disable"
    rm -f "$disable_file" 2>/dev/null || true
    printf '[FAILSAFE] Module disable flag removed\n' >> "$LOG_FILE" 2>/dev/null || true
}

# Unified status update: changes description + manages disable file
daemon_set_module_status() {
    local status_type="$1"  # 'ok', 'safe_mode', 'broken_environment', etc.
    
    printf '[FAILSAFE] Setting module status: %s\n' "$status_type" >> "$LOG_FILE" 2>/dev/null || true
    
    # Update module.prop description
    daemon_update_module_description "$status_type"
    
    # Manage disable file based on status
    if daemon_should_disable_module "$status_type"; then
        daemon_write_disable_file
    else
        daemon_remove_disable_file
    fi
}

# ============== Rescue Documentation ==============
# Write rescue instructions to log and cache
daemon_write_rescue_instructions() {
    cat > "$MODDIR/cache/.rescue_instructions.txt" << 'EOF'
=== DAEMON RESCUE INSTRUCTIONS ===

If daemon enters safe_mode (degraded operation):

1. Check Module Status (visible in Magisk Manager):
   Status is updated in real-time in module.prop description field
   - OK = Normal operation
   - SAFE MODE = State corruption, degraded operation
   - BROKEN ENV = Critical error, module may be disabled
   - RECOVERING = Rescue in progress
   - RECOVERED = Recovery complete, restarting

2. Check Disable Flag:
   adb shell [ -f /data/adb/modules/Kitsunping/disable ] && echo "Module disabled" || echo "Module enabled"
   
   If disabled, Magisk Manager won't load the module. Re-enable via:
   adb shell rm /data/adb/modules/Kitsunping/disable

3. Request Manual Rescue (from device or ADB):
   adb shell touch /data/adb/modules/Kitsunping/cache/daemon.rescue_requested

4. Restart Daemon:
   adb shell kill -TERM $(adb shell cat /data/adb/modules/Kitsunping/cache/daemon.pid 2>/dev/null)
   
   Or wait 60 seconds for daemon to auto-restart.
   Daemon will auto-recover state and restore module to OK status.

5. Check Logs:
   adb logcat | grep '\[FAILSAFE\]'
   adb shell tail -f /data/adb/modules/Kitsunping/logs/daemon.log

6. Inspect Backup:
   adb shell ls -la /data/adb/modules/Kitsunping/cache/rescue_backup_*/
   
   State files are backed up automatically during rescue for diagnostics.
   Compare against original:
   adb shell diff /data/adb/modules/Kitsunping/cache/rescue_backup_*/daemon.state.backup /data/adb/modules/Kitsunping/cache/daemon.state

7. Manual State Reset (if needed):
   adb shell rm -f /data/adb/modules/Kitsunping/cache/daemon.state
   adb shell rm -f /data/adb/modules/Kitsunping/cache/link_context.state
   
   Daemon will rebuild state on next cycle.

8. View Original Module Description:
   adb shell cat /data/adb/modules/Kitsunping/cache/module.prop.original

=== MODULE STATUS REFERENCE ===
- Status: OK (module enabled, normal operation)
- Status: Safe Mode (module enabled, degraded - detect & fix corruption)
- Status: Broken Environment (module disabled - critical error)
- Status: Conflict (other modules interfering)
- Status: Recovering (rescue in progress)
- Status: Recovered (recovery complete, restarting)

=== NO REINSTALL REQUIRED ===
Rescue is designed to recover without module reinstall.

EOF
    chmod 0644 "$MODDIR/cache/.rescue_instructions.txt" 2>/dev/null || true
}

