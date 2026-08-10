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
NATIVE_PACKAGE='com.example.native'
METRIC_FILE="$MODDIR/cache/metric"

get_native_foreground_package() { printf '%s' "$NATIVE_PACKAGE"; }
kitsunpingd_metrics_record() { printf '%s:%s:%s' "$1" "$4" "$5" > "$METRIC_FILE"; }
dumpsys() {
    : > "$MODDIR/cache/dumpsys_called"
    case "$1:$2" in
        'window:windows') printf '%s\n' 'mCurrentFocus=Window{abc u0 com.example.legacy/.MainActivity}' ;;
        'activity:activities') printf '%s\n' 'mResumedActivity: ActivityRecord{u0 com.example.activity/.MainActivity}' ;;
    esac
}

# shellcheck disable=SC1090
. "$REPO_DIR/network/app/target_engine.sh"

native_result=$(network__app__detect_foreground_package)
assert_eq 'com.example.native' "$native_result" "native foreground package takes authority"
assert_eq 'foreground_package:2:8' "$(cat "$METRIC_FILE")" "native foreground package records avoided Shell work"
assert_file_not_exists "$MODDIR/cache/dumpsys_called" "native foreground package skips Bash dumpsys fallback"

NATIVE_PACKAGE=''
legacy_result=$(network__app__detect_foreground_package)
assert_eq 'com.example.legacy' "$legacy_result" "missing native package falls back to legacy detector"

finish