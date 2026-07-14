#!/bin/sh

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) : ;;
    *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac

TEST_DIR=${SCRIPT_PATH%/*}
ROOT_DIR=${TEST_DIR%/*}
REPO_DIR=${ROOT_DIR%/*}

# shellcheck disable=SC1090
. "$ROOT_DIR/lib/test_helpers.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

mkdir -p "$TMP_DIR/cache" "$TMP_DIR/logs"
cp "$REPO_DIR/cache/module_status.json" "$TMP_DIR/cache/module_status.json"
cat > "$TMP_DIR/module.prop" <<'EOF'
id=Kitsunping
name=Kitsunping
version=6.30
versionCode=630
author=@Angeles_ho
description=Kitsunping v6.30 - WiFi 2.4G/5G + TCP + LTE/LTE-A + PPC
updateJson=https://example.invalid/update.json
EOF

MODDIR="$TMP_DIR"
LOG_FILE="$TMP_DIR/logs/daemon.log"
STATE_FILE="$TMP_DIR/cache/daemon.state"
LINK_CONTEXT_FILE="$TMP_DIR/cache/link_context.state"
LAST_EVENT_FILE="$TMP_DIR/cache/daemon.last"

# shellcheck disable=SC1090
. "$REPO_DIR/addon/functions/daemon_failsafe.sh"

# Ensure a clean starting point even if a previous run left the rescue flag.
rm -f "$TMP_DIR/cache/daemon.rescue_requested"

expected_ok_desc="$(daemon_get_status_description ok)"
assert_contains "Kitsunping v6.30" "$expected_ok_desc" "module status base uses installed module.prop version"

sed 's/^version=6\.30$/version=7.0-beta/' "$TMP_DIR/module.prop" > "$TMP_DIR/module.prop.next"
mv "$TMP_DIR/module.prop.next" "$TMP_DIR/module.prop"
assert_contains "Kitsunping v7.0-beta" "$(daemon_get_status_description startup)" "module status ignores stale JSON version"
sed 's/^version=7\.0-beta$/version=6.30/' "$TMP_DIR/module.prop" > "$TMP_DIR/module.prop.next"
mv "$TMP_DIR/module.prop.next" "$TMP_DIR/module.prop"

touch "$TMP_DIR/cache/daemon.rescue_requested"
daemon_check_rescue_request
assert_rc 0 "$?" "rescue request is true when flag exists"
rm -f "$TMP_DIR/cache/daemon.rescue_requested"

printf 'bad state\n' > "$STATE_FILE"
printf 'bad link\n' > "$LINK_CONTEXT_FILE"
daemon_init_safe_mode
assert_rc 1 "$?" "first corruption hit delays safe mode to allow self-heal"
assert_file_not_exists "$TMP_DIR/cache/daemon.safe_mode" "safe mode flag stays absent after first recoverable hit"
assert_file_contains "$TMP_DIR/module.prop" "[STARTING]" "startup status is written during delayed safe-mode path"
assert_file_contains "$STATE_FILE" "daemon.self_healed=1" "self-heal rewrites daemon.state template"
daemon_promote_startup_status_if_healthy
assert_rc 0 "$?" "healthy rebuilt state promotes startup module status"
assert_file_contains "$TMP_DIR/module.prop" "$expected_ok_desc" "healthy rebuilt state exposes stable module description"

printf 'bad state again\n' > "$STATE_FILE"
printf 'bad link again\n' > "$LINK_CONTEXT_FILE"
daemon_init_safe_mode
assert_rc 0 "$?" "second corruption hit enters safe mode"
assert_file_exists "$TMP_DIR/cache/daemon.safe_mode" "safe mode flag is created"
assert_file_contains "$TMP_DIR/module.prop" "[SAFE MODE]" "module.prop exposes safe mode"

daemon_set_module_status broken_environment
assert_file_exists "$TMP_DIR/disable" "broken_environment creates disable flag"
daemon_set_module_status ok
assert_file_not_exists "$TMP_DIR/disable" "ok status removes disable flag"
assert_file_contains "$TMP_DIR/module.prop" "$expected_ok_desc" "ok status restores stable description"

# Hardening: invalid JSON disable values must not break deterministic fallback.
cp "$TMP_DIR/cache/module_status.json" "$TMP_DIR/cache/module_status.json.bak"
awk '
    /"broken_environment"[[:space:]]*:[[:space:]]*\{/ { in_broken=1 }
    in_broken && /"disable"[[:space:]]*:[[:space:]]*true/ {
        sub(/true/, "\"maybe\"")
        in_broken=0
    }
    { print }
' "$TMP_DIR/cache/module_status.json.bak" > "$TMP_DIR/cache/module_status.json"

daemon_set_module_status broken_environment
assert_file_exists "$TMP_DIR/disable" "broken_environment fallback keeps disable flag when JSON disable is invalid"
assert_file_contains "$LOG_FILE" "Invalid disable value in module_status.json: status=broken_environment disable=maybe" "invalid disable value is logged for broken_environment"

awk '
    /"ok"[[:space:]]*:[[:space:]]*\{/ { in_ok=1 }
    in_ok && /"disable"[[:space:]]*:[[:space:]]*false/ {
        sub(/false/, "\"invalid\"")
        in_ok=0
    }
    { print }
' "$TMP_DIR/cache/module_status.json.bak" > "$TMP_DIR/cache/module_status.json"

daemon_set_module_status ok
assert_file_not_exists "$TMP_DIR/disable" "ok fallback keeps module enabled when JSON disable is invalid"
assert_file_contains "$LOG_FILE" "Invalid disable value in module_status.json: status=ok disable=invalid" "invalid disable value is logged for ok"

# Transition hardening: conflict status applies only when safe_mode is not active.
rm -f "$TMP_DIR/cache/daemon.safe_mode"
daemon_set_module_status ok
daemon_apply_conflict_risk_status high
assert_rc 0 "$?" "high conflict risk transitions to conflict_detected outside safe_mode"
assert_file_contains "$TMP_DIR/module.prop" "[CONFLICT]" "module.prop exposes conflict_detected status"
assert_file_not_exists "$TMP_DIR/disable" "conflict_detected does not disable module"

touch "$TMP_DIR/cache/daemon.safe_mode"
daemon_set_module_status safe_mode
daemon_apply_conflict_risk_status high
assert_rc 1 "$?" "high conflict risk is suppressed while safe_mode is active"
assert_file_contains "$TMP_DIR/module.prop" "[SAFE MODE]" "safe_mode status remains after conflict suppression"
assert_file_not_exists "$TMP_DIR/disable" "safe_mode remains enabled during conflict suppression"
assert_file_contains "$LOG_FILE" "conflict_detected suppressed because safe_mode is active" "suppressed transition is logged"

touch "$TMP_DIR/cache/daemon.rescue_requested"
touch "$TMP_DIR/cache/daemon.safe_mode"
printf 'old-event\n' > "$LAST_EVENT_FILE"
daemon_perform_rescue
assert_rc 0 "$?" "manual rescue completes successfully"
assert_file_not_exists "$TMP_DIR/cache/daemon.rescue_requested" "rescue clears rescue request flag"
assert_file_not_exists "$TMP_DIR/cache/daemon.safe_mode" "rescue clears safe mode flag"
assert_file_contains "$STATE_FILE" "daemon.safe_mode_recovery=1" "rescue writes recovery state template"
assert_file_contains "$TMP_DIR/module.prop" "[RECOVERED]" "module.prop exposes recovery_complete state"

daemon_consume_safe_mode_recovery_flag
assert_rc 0 "$?" "recovery marker is consumed after rescue"
assert_file_contains "$STATE_FILE" "daemon.safe_mode_recovery=0" "recovery marker resets to 0 after consume"

daemon_consume_safe_mode_recovery_flag
assert_rc 1 "$?" "second recovery-marker consume is a no-op"

finish