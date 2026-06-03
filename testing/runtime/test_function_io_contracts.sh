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

# Some helpers in network_utils rely on MODDIR-derived defaults.
MODDIR="$REPO_DIR"
export MODDIR

# shellcheck disable=SC1090
. "$REPO_DIR/addon/functions/network_utils.sh"
# shellcheck disable=SC1090
. "$REPO_DIR/addon/functions/daemon_config.sh"

samples_dir="$REPO_DIR/testdata"

out=$(daemon_normalize_weight_value "0.45" "0.3")
assert_eq "0.45" "$out" "normalize weight keeps valid numeric input"

out=$(daemon_normalize_weight_value "abc" "0.3")
assert_eq "0.3" "$out" "normalize weight falls back to default on invalid input"

out=$(normalize_pipe_list "HT, VHT, ht, HE")
assert_eq "he|ht|vht" "$out" "normalize pipe list deduplicates and sorts values"

raw_with_tab=$(printf ' Home 5G \t (Lab)#1 ')
out=$(sanitize_kv_value "$raw_with_tab")
assert_eq "Home_5G_Lab1" "$out" "sanitize kv value strips unsupported characters"

out=$(normalize_freq_mhz "5210.2 MHz")
assert_eq "5210" "$out" "normalize frequency rounds and strips unit suffix"

out=$(derive_band_from_freq "2447")
assert_eq "2g" "$out" "derive band returns 2g for 2.4GHz frequency"

out=$(derive_band_from_freq "5210")
assert_eq "5g" "$out" "derive band returns 5g for 5GHz frequency"

out=$(derive_band_from_freq "5975")
assert_eq "6g" "$out" "derive band returns 6g for 6GHz frequency"

out=$(channel_from_freq "2447")
assert_eq "8" "$out" "channel from freq maps 2447MHz to channel 8"

out=$(channel_from_freq "5210")
assert_eq "42" "$out" "channel from freq maps 5210MHz to channel 42"

out=$(channel_from_freq "5975")
assert_eq "5" "$out" "channel from freq maps 5975MHz to channel 5"

ROUTER_INFER_WIDTH=0
ROUTER_INFER_WIDTH_2G=0
out=$(infer_wifi_width_mhz "5g" "" "866.7")
assert_eq "||" "$out" "width inference stays empty when inference is disabled"

out=$(infer_wifi_width_mhz "5g" "80" "866.7")
assert_eq "80|explicit|high" "$out" "explicit width is preserved with high confidence"

ROUTER_INFER_WIDTH=1
ROUTER_INFER_WIDTH_2G=1
out=$(infer_wifi_width_mhz "5g" "" "950")
assert_eq "160|inferred|medium" "$out" "5g width inference promotes high bitrate to 160MHz"

out=$(infer_wifi_width_mhz "2g" "" "72.2")
assert_eq "20|inferred|low" "$out" "2g width inference defaults to conservative 20MHz"

parsed=$(parse_iw_link_info_text "$(cat "$samples_dir/iw_link_2g.txt")")
rc=$?
assert_rc 0 "$rc" "2g sample parser returns success"
assert_contains "band=2g" "$parsed" "2g sample exposes 2g band"
assert_contains "chan=8" "$parsed" "2g sample exposes channel 8"
assert_contains "signal_dbm=-50" "$parsed" "2g sample exposes signal"
assert_contains "wifi_standard=n" "$parsed" "2g sample derives wifi standard n"

parsed=$(parse_iw_link_info_text "$(cat "$samples_dir/iw_link_5g_160mhz.txt")")
rc=$?
assert_rc 0 "$rc" "5g sample parser returns success"
assert_contains "band=5g" "$parsed" "5g sample exposes 5g band"
assert_contains "chan=42" "$parsed" "5g sample exposes channel 42"
assert_contains "width=160" "$parsed" "5g sample exposes explicit 160MHz width"
assert_contains "width_source=explicit" "$parsed" "5g sample width source is explicit"
assert_contains "wifi_standard=ac" "$parsed" "5g sample derives wifi standard ac"

parsed=$(parse_iw_link_info_text "$(cat "$samples_dir/iw_link_ax_he.txt")")
rc=$?
assert_rc 0 "$rc" "wifi6 sample parser returns success"
assert_contains "band=6g" "$parsed" "wifi6 sample exposes 6g band"
assert_contains "chan=5" "$parsed" "wifi6 sample exposes channel 5"
assert_contains "width=80" "$parsed" "wifi6 sample exposes explicit 80MHz width"
assert_contains "wifi_standard=ax" "$parsed" "wifi6 sample derives wifi standard ax"

parsed=$(parse_iw_link_info_text "$(cat "$samples_dir/iw_link_not_connected.txt")")
rc=$?
assert_rc 1 "$rc" "not-connected sample returns parser failure"
assert_eq "" "$parsed" "not-connected sample returns empty payload"

finish
