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

ML_PROP_VALUE=0

getprop() {
    case "$1" in
        persist.kitsunping.ml_feature_log_enable) printf '%s' "$ML_PROP_VALUE" ;;
        *) printf '%s' '' ;;
    esac
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

num_or_null() {
    value="$1"
    case "$value" in
        ''|*[!0-9.-]*) printf '%s' null ;;
        *) printf '%s' "$value" ;;
    esac
}

atomic_write() {
    target="$1"
    tmp_file="${target}.tmp"
    cat > "$tmp_file" && mv "$tmp_file" "$target"
}

log_info() {
    printf '%s\n' "$*"
}

calibrate_get_wifi_rssi_dbm() {
    printf '%s' '-55'
}

calibrate_get_radio_network_type() {
    printf '%s' 'nr'
}

trace_log="$TMP_DIR/trace.log"
ml_features_file="$TMP_DIR/calibration_features.jsonl"
ml_last_file="$TMP_DIR/last_calibration_feature.json"
BEST_ro_ril_hsupa_category=11
BEST_ro_ril_hsdpa_category=12
BEST_ro_ril_lte_category=13
BEST_ro_ril_ltea_category=14
BEST_ro_ril_nr5g_category=15

source_range "$REPO_DIR/calibration/calibrate.sh" 276 345

unset KITSUNPING_ML_FEATURE_LOG
calibrate_ml_feature_log_enabled
assert_rc 1 "$?" "ML feature logging is disabled by default"

KITSUNPING_ML_FEATURE_LOG=1
calibrate_ml_feature_log_enabled
assert_rc 0 "$?" "ML feature logging can be enabled by environment"
unset KITSUNPING_ML_FEATURE_LOG

ML_PROP_VALUE=1
calibrate_ml_feature_log_enabled
assert_rc 0 "$?" "ML feature logging can be enabled by property"

calibrate_ml_append_feature "CarrierX" "wifi" "wlan0" "8.8.8.8" "full" \
    "50 5 0 60 70" "65.5" "40 3 0 45 50" "72.0" "1" "10" "6.5"
assert_file_exists "$ml_features_file" "ML append writes rolling feature log"
assert_file_exists "$ml_last_file" "ML append writes latest snapshot"
assert_file_contains "$ml_last_file" '"success":1' "latest ML snapshot records success flag"
assert_file_contains "$ml_features_file" '"provider":"CarrierX"' "feature log contains provider payload"

finish