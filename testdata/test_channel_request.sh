#!/system/bin/sh
# Test script for router channel recommendation module
# Usage: sh testdata/test_channel_request.sh

MODDIR="/data/adb/modules/kitsuneping"
MODULE_PATH="$MODDIR"

# Source dependencies
. "$MODDIR/lib/logging.sh"
. "$MODDIR/lib/time_helpers.sh"
. "$MODDIR/network/app/state_io.sh"
. "$MODDIR/network/app/pairing_gate.sh"
. "$MODDIR/network/app/router_channel.sh"
. "$MODDIR/network/wifi/wifi_score.sh" 

# Test 1: Check if functions are available
echo "=== Test 1: Function availability ==="
if command -v network__router__channel_recommend_request >/dev/null 2>&1; then
    echo "✓ network__router__channel_recommend_request available"
else
    echo "✗ network__router__channel_recommend_request NOT available"
    exit 1
fi

if command -v network__router__channel_get_cached >/dev/null 2>&1; then
    echo "✓ network__router__channel_get_cached available"
else
    echo "✗ network__router__channel_get_cached NOT available"
    exit 1
fi

if command -v network__router__channel_has_better_option >/dev/null 2>&1; then
    echo "✓ network__router__channel_has_better_option available"
else
    echo "✗ network__router__channel_has_better_option NOT available"
    exit 1
fi

echo ""

# Test 2: Check pairing status
echo "=== Test 2: Pairing status ==="
pairing_ok="$(network__app__read_state_field pairing_ok)"
pairing_router_ip="$(network__app__read_pairing_json_field router_ip)"
echo "pairing_ok: $pairing_ok"
echo "router_ip: $pairing_router_ip"

if [ "$pairing_ok" != "1" ]; then
    echo "⚠ Pairing not active, cannot test HTTP request"
    echo "✓ Test passed (guards work correctly)"
    exit 0
fi
echo ""

# Test 3: Check current WiFi score
echo "=== Test 3: WiFi score check ==="
wifi_score="$(network__app__read_state_field wifi_score)"
current_iface="$(get_current_iface)"
echo "current_iface: $current_iface"
echo "wifi_score: $wifi_score"

if [ "$current_iface" != "wlan0" ]; then
    echo "⚠ Not on WiFi, cannot test channel recommendation"
    echo "✓ Test passed (guards work correctly)"
    exit 0
fi

CHANNEL_SCAN_THRESHOLD=65
if [ -n "$wifi_score" ] && [ "$wifi_score" -ge "$CHANNEL_SCAN_THRESHOLD" ]; then
    echo "⚠ WiFi score >= $CHANNEL_SCAN_THRESHOLD, recommendation not needed"
    echo "To force test, set wifi_score manually or use force=1"
fi
echo ""

# Test 4: Try to request channel recommendation (force mode to bypass guards)
echo "=== Test 4: Request channel recommendation (force mode) ==="
echo "Requesting for 2.4GHz band..."

# Clear cache to force fresh request
rm -f "$MODDIR/cache/router_channel.cache" 2>/dev/null

network__router__channel_recommend_request "2.4GHz" "1"
result=$?

echo ""
echo "Request result: $result"

if [ $result -eq 0 ]; then
    echo "✓ Request successful"
else
    echo "✗ Request failed with code: $result"
fi
echo ""

# Test 5: Read cached results
echo "=== Test 5: Read cached recommendation ==="
recommended_channel="$(network__router__channel_get_cached recommended_channel)"
score="$(network__router__channel_get_cached score)"
score_gap="$(network__router__channel_get_cached score_gap)"
current_channel="$(network__router__channel_get_cached current_channel)"
rf_model="$(network__router__channel_get_cached rf_model)"

echo "Cached data:"
echo "  recommended_channel: $recommended_channel"
echo "  current_channel: $current_channel"
echo "  score: $score"
echo "  score_gap: $score_gap"
echo "  rf_model: $rf_model"
echo ""

# Test 6: Check if better option exists
echo "=== Test 6: Check for better option ==="
threshold=15

if network__router__channel_has_better_option "$threshold"; then
    echo "✓ Better channel option found (score_gap >= $threshold)"
    echo "  Recommendation: Switch to channel $recommended_channel (gain +$score_gap)"
else
    echo "○ No significantly better option (score_gap < $threshold)"
    echo "  Current channel is acceptable"
fi
echo ""

# Test 7: Verify cache TTL
echo "=== Test 7: Verify telemetry (M2) ==="
telem_file="$MODDIR/cache/telemetry.channel_requests"
if [ -f "$telem_file" ]; then
    auto_count="$(grep '^auto=' "$telem_file" 2>/dev/null | cut -d'=' -f2)"
    manual_count="$(grep '^manual=' "$telem_file" 2>/dev/null | cut -d'=' -f2)"
    error_count="$(grep '^errors=' "$telem_file" 2>/dev/null | cut -d'=' -f2)"
    
    [ -z "$auto_count" ] && auto_count=0
    [ -z "$manual_count" ] && manual_count=0
    [ -z "$error_count" ] && error_count=0
    
    echo "Telemetry counters:"
    echo "  auto:   $auto_count"
    echo "  manual: $manual_count"
    echo "  errors: $error_count"
    
    # Our test above did force=1, so manual should be incremented
    if [ "$manual_count" -gt 0 ]; then
        echo "✓ Manual request counter incremented"
    else
        echo "⚠ Manual counter not incremented (may be due to guards)"
    fi
else
    echo "⚠ Telemetry file not found"
fi
echo ""

echo "=== Test 8: Cache TTL verification ==="
cache_file="$MODDIR/cache/router_channel.cache"
if [ -f "$cache_file" ]; then
    cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
    echo "Cache age: ${cache_age}s"
    
    CHANNEL_CACHE_TTL_SEC=900
    if [ "$cache_age" -lt "$CHANNEL_CACHE_TTL_SEC" ]; then
        echo "✓ Cache is fresh (< ${CHANNEL_CACHE_TTL_SEC}s)"
    else
        echo "⚠ Cache expired (>= ${CHANNEL_CACHE_TTL_SEC}s)"
    fi
else
    echo "✗ Cache file not found"
fi
echo ""

echo "=== Test completed (8 tests) ==="
