#!/system/bin/sh
# channel_stats.sh — Display channel recommendation telemetry and configuration
# Usage: sh tools/channel_stats.sh

MODDIR="/data/adb/modules/kitsuneping"
TELEM_FILE="$MODDIR/cache/telemetry.channel_requests"
CACHE_FILE="$MODDIR/cache/router_channel_recommendation.json"
LAST_REQUEST_FILE="$MODDIR/cache/router_channel_last_request.ts"

echo "=== Channel Recommendation Statistics (M2) ==="
echo ""

# Configuration
echo "--- Configuration ---"
threshold="$(getprop kitsuneping.channel.score_threshold 2>/dev/null | tr -d '\r\n')"
[ -z "$threshold" ] && threshold="65 (default)"
echo "Score threshold:     $threshold"

ttl="$(getprop kitsuneping.channel.cache_ttl_sec 2>/dev/null | tr -d '\r\n')"
[ -z "$ttl" ] && ttl="900 (15 min, default)"
echo "Cache TTL:           ${ttl}s"

interval="$(getprop kitsuneping.channel.request_interval_sec 2>/dev/null | tr -d '\r\n')"
[ -z "$interval" ] && interval="300 (5 min, default)"
echo "Request interval:    ${interval}s"

trigger_iter="$(getprop kitsuneping.channel.trigger_iterations 2>/dev/null | tr -d '\r\n')"
[ -z "$trigger_iter" ] && trigger_iter="3 (default)"
echo "Trigger iterations:  $trigger_iter"

echo ""

# Telemetry counters
echo "--- Telemetry ---"
if [ -f "$TELEM_FILE" ]; then
    auto_count="$(grep '^auto=' "$TELEM_FILE" 2>/dev/null | cut -d'=' -f2)"
    manual_count="$(grep '^manual=' "$TELEM_FILE" 2>/dev/null | cut -d'=' -f2)"
    error_count="$(grep '^errors=' "$TELEM_FILE" 2>/dev/null | cut -d'=' -f2)"
    
    [ -z "$auto_count" ] && auto_count=0
    [ -z "$manual_count" ] && manual_count=0
    [ -z "$error_count" ] && error_count=0
    
    total=$((auto_count + manual_count))
    
    echo "Auto requests:       $auto_count"
    echo "Manual requests:     $manual_count"
    echo "Total requests:      $total"
    echo "Errors:              $error_count"
    
    if [ "$total" -gt 0 ]; then
        error_rate=$(awk "BEGIN {printf \"%.1f\", ($error_count / $total) * 100}")
        echo "Error rate:          ${error_rate}%"
    fi
else
    echo "No telemetry data yet"
fi

echo ""

# Last request
echo "--- Last Request ---"
if [ -f "$LAST_REQUEST_FILE" ]; then
    last_ts="$(cat "$LAST_REQUEST_FILE" 2>/dev/null || echo 0)"
    now_ts="$(date +%s)"
    elapsed=$((now_ts - last_ts))
    
    if [ "$elapsed" -lt 60 ]; then
        echo "Last request:        ${elapsed}s ago"
    elif [ "$elapsed" -lt 3600 ]; then
        minutes=$((elapsed / 60))
        echo "Last request:        ${minutes}m ago"
    else
        hours=$((elapsed / 3600))
        minutes=$(((elapsed % 3600) / 60))
        echo "Last request:        ${hours}h ${minutes}m ago"
    fi
else
    echo "No requests yet"
fi

echo ""

# Cache status
echo "--- Cache Status ---"
if [ -f "$CACHE_FILE" ]; then
    cached_at="$(grep -m1 '"cached_at"' "$CACHE_FILE" 2>/dev/null | sed 's/.*:[[:space:]]*//; s/,.*//; s/[[:space:]]*$//')"
    
    if [ -n "$cached_at" ]; then
        now_ts="$(date +%s)"
        cache_age=$((now_ts - cached_at))
        cache_ttl="$(grep -m1 '"ttl_sec"' "$CACHE_FILE" 2>/dev/null | sed 's/.*:[[:space:]]*//; s/,.*//; s/[[:space:]]*$//')"
        [ -z "$cache_ttl" ] && cache_ttl=900
        
        if [ "$cache_age" -lt "$cache_ttl" ]; then
            echo "Cache:               VALID (${cache_age}s / ${cache_ttl}s)"
        else
            echo "Cache:               EXPIRED (${cache_age}s > ${cache_ttl}s)"
        fi
        
        # Show recommendation if cache valid
        if [ "$cache_age" -lt "$cache_ttl" ]; then
            echo ""
            echo "--- Cached Recommendation ---"
            recommended="$(grep -m1 '"recommended_channel"' "$CACHE_FILE" 2>/dev/null | sed 's/.*:[[:space:]]*//; s/[",].*//; s/[[:space:]]*$//')"
            current="$(grep -m1 '"current_channel"' "$CACHE_FILE" 2>/dev/null | sed 's/.*:[[:space:]]*//; s/[",].*//; s/[[:space:]]*$//')"
            score="$(grep -m1 '"score"' "$CACHE_FILE" 2>/dev/null | sed 's/.*:[[:space:]]*//; s/[",].*//; s/[[:space:]]*$//')"
            score_gap="$(grep -m1 '"score_gap"' "$CACHE_FILE" 2>/dev/null | sed 's/.*:[[:space:]]*//; s/[",].*//; s/[[:space:]]*$//')"
            rf_model="$(grep -m1 '"rf_model"' "$CACHE_FILE" 2>/dev/null | sed 's/.*:[[:space:]]*"//; s/".*//; s/[[:space:]]*$//')"
            
            echo "Current channel:     $current"
            echo "Recommended:         $recommended"
            echo "Score:               $score"
            echo "Score gap:           $score_gap"
            echo "RF model:            $rf_model"
            
            if [ -n "$recommended" ] && [ -n "$current" ] && [ "$recommended" != "$current" ]; then
                if [ -n "$score_gap" ] && [ "$score_gap" -ge 15 ]; then
                    echo ""
                    echo " [!] Better channel available! Score gain: +$score_gap"
                    echo "   Consider switching to channel $recommended"
                fi
            fi
        fi
    else
        echo "Cache:               INVALID (corrupted)"
    fi
else
    echo "Cache:               NONE"
fi

echo ""
echo "=== Configuration Commands ==="
echo "Set score threshold:     setprop kitsuneping.channel.score_threshold <10-100>"
echo "Set cache TTL:           setprop kitsuneping.channel.cache_ttl_sec <60-7200>"
echo "Set request interval:    setprop kitsuneping.channel.request_interval_sec <60-3600>"
echo "Set trigger iterations:  setprop kitsuneping.channel.trigger_iterations <1-10>"
echo ""
echo "Clear telemetry:         rm $TELEM_FILE"
echo "Clear cache:             rm $CACHE_FILE"
echo ""
