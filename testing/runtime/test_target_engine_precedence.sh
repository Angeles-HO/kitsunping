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

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

MODDIR="$TMP_ROOT/mod"
mkdir -p "$MODDIR/cache"

BOOT_PROFILE=''
TARGET_ENGINE_ENABLED='0'
FOREGROUND_PKG=''
getprop() {
    case "$1" in
        persist.kitsunping.target_prop_enable) printf '%s' "$TARGET_ENGINE_ENABLED" ;;
        persist.kitsunping.boot_profile) printf '%s' "$BOOT_PROFILE" ;;
        persist.kitsunping.target_foreground_stable_sec|persist.kitsunping.target_profile_change_cooldown_sec) printf '%s' '0' ;;
        *) printf '%s' '' ;;
    esac
}

log_info() { :; }
log_debug() { :; }
log_warning() { :; }
emit_event() { :; }
network__app__kpi_session_marker_clear() { :; }
network__app__priority_apply_context() { :; }
network__app__policy_version_touch() { :; }
network__app__target_state_transition() { :; }
network__app__target_app_is_stable() { return 0; }
network__app__target_change_cooldown_ok() { return 0; }
network__app__target_mark_profile_change() { :; }
network__app__detect_foreground_package() { printf '%s' "$FOREGROUND_PKG"; }
network__app__normalize_target_token() { printf '%s' "$1"; }
EV_REQUEST_PROFILE='request_profile'

# shellcheck disable=SC1090
. "$REPO_DIR/network/app/target_engine.sh"

# target_engine defines the production foreground detector when sourced; replace
# it here with the fixture-controlled value after loading the implementation.
network__app__detect_foreground_package() { printf '%s' "$FOREGROUND_PKG"; }

printf '%s' 'speed' > "$MODDIR/cache/policy.auto_request"
network__app__target_profile_cycle
auto_profile=$(cat "$MODDIR/cache/policy.request" 2>/dev/null || echo '')
auto_priority=$(cat "$MODDIR/cache/policy.request.priority" 2>/dev/null || echo '')
assert_eq 'speed' "$auto_profile" "automatic candidate is composed into policy.request by target engine"
assert_eq 'medium' "$auto_priority" "automatic candidate receives automatic priority"

printf '%s' 'gaming' > "$MODDIR/cache/policy.request"
printf '%s' 'manual' > "$MODDIR/cache/policy.request.priority"
network__app__target_profile_cycle
manual_profile=$(cat "$MODDIR/cache/policy.request" 2>/dev/null || echo '')
assert_eq 'gaming' "$manual_profile" "manual request is not replaced by automatic candidate"

rm -f "$MODDIR/cache/policy.request" "$MODDIR/cache/policy.request.priority"
BOOT_PROFILE='gaming'
network__app__target_profile_cycle
boot_profile=$(cat "$MODDIR/cache/policy.request" 2>/dev/null || echo '')
boot_priority=$(cat "$MODDIR/cache/policy.request.priority" 2>/dev/null || echo '')
assert_eq 'gaming' "$boot_profile" "target engine composes configured boot profile"
assert_eq 'boot' "$boot_priority" "boot profile is protected from automatic replacement"

# Foreground Gaming remains authoritative even if the transport selector changes
# its automatic candidate. Once the game is no longer foreground, the existing
# release path may restore the current automatic candidate.
BOOT_PROFILE=''
TARGET_ENGINE_ENABLED='1'
printf '%s\n' 'com.example.game=gaming,high' > "$MODDIR/target.prop"
printf '%s' 'stable' > "$MODDIR/cache/policy.auto_request"
rm -f \
    "$MODDIR/cache/policy.request" \
    "$MODDIR/cache/policy.request.priority" \
    "$MODDIR/cache/target.override.active" \
    "$MODDIR/cache/target.prop.cache" \
    "$MODDIR/cache/target.prop.hash"
FOREGROUND_PKG='com.example.game'
network__app__target_profile_cycle
gaming_profile=$(cat "$MODDIR/cache/policy.request" 2>/dev/null || echo '')
assert_eq 'gaming' "$gaming_profile" "mapped foreground game selects Gaming"

printf '%s' 'stable' > "$MODDIR/cache/policy.auto_request"
network__app__target_profile_cycle
gaming_after_auto_change=$(cat "$MODDIR/cache/policy.request" 2>/dev/null || echo '')
assert_eq 'gaming' "$gaming_after_auto_change" "automatic Stable candidate does not replace active Gaming"

FOREGROUND_PKG=''
network__app__target_profile_cycle
released_profile=$(cat "$MODDIR/cache/policy.request" 2>/dev/null || echo '')
released_priority=$(cat "$MODDIR/cache/policy.request.priority" 2>/dev/null || echo '')
assert_eq 'stable' "$released_profile" "closing mapped game restores automatic Stable candidate"
assert_eq 'medium' "$released_priority" "released foreground override restores automatic priority"

finish