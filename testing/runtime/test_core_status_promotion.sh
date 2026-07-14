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
PROMOTION_MARKER="$TMP_DIR/promoted"

getprop() { :; }
log_info() { :; }
get_current_iface() { printf '%s' wlan0; }
daemon_run_app_event_cycle() { :; }
daemon_run_pairing_sync_cycle() { :; }
daemon_run_wifi_cycle() { :; }
daemon_run_mobile_cycle() { :; }
daemon_run_wifi_transport_cycle() { :; }
daemon_run_mobile_transport_cycle() { :; }
daemon_run_target_profile_cycle() { :; }
daemon_run_router_status_push_cycle() { :; }
daemon_run_transition_cycle() { :; }
daemon_run_tick_cycle() { :; }
daemon_write_state_file() { :; }
daemon_promote_startup_status_if_healthy() { : > "$PROMOTION_MARKER"; }

# shellcheck disable=SC1090
. "$REPO_DIR/core/runtime.sh"

core_daemon_iteration
assert_file_exists "$PROMOTION_MARKER" "core daemon iteration promotes healthy startup status"

finish