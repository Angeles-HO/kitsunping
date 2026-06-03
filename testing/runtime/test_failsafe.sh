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

touch "$TMP_DIR/cache/daemon.rescue_requested"
touch "$TMP_DIR/cache/daemon.safe_mode"
printf 'old-event\n' > "$LAST_EVENT_FILE"
daemon_perform_rescue
assert_rc 0 "$?" "manual rescue completes successfully"
assert_file_not_exists "$TMP_DIR/cache/daemon.rescue_requested" "rescue clears rescue request flag"
assert_file_not_exists "$TMP_DIR/cache/daemon.safe_mode" "rescue clears safe mode flag"
assert_file_contains "$STATE_FILE" "daemon.safe_mode_recovery=1" "rescue writes recovery state template"
assert_file_contains "$TMP_DIR/module.prop" "[RECOVERED]" "module.prop exposes recovery_complete state"

finish