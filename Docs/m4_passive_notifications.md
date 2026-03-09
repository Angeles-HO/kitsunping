# M4: Passive Notifications - Implementation Summary

## Overview
M4 implements passive notifications that alert users when a significantly better WiFi channel is available without requiring manual trigger. This feature complements M2's auto-scan capability by providing user feedback when improvements are detected.

## Architecture

### Backend (Module) - `network/app/router_channel.sh`

**Function:** `network__wifi__channel_notification_check [current_channel]`

**Purpose:** Compare cached channel recommendation against current WiFi state and trigger Android notification if improvement is significant.

**Configuration Constants:**
```bash
CHANNEL_NOTIFICATION_GAP=15              # Minimum score improvement to notify (default: 15 points)
CHANNEL_NOTIFICATION_INTERVAL_SEC=3600   # Rate-limit: 1 hour between notifications for same channel
CHANNEL_NOTIFICATION_STATE="$CACHE_DIR/channel_notification.state"
```

**Guards (in order):**
1. **Invalid input** - current_channel must be numeric and > 0
2. **Cache missing** - response_file must exist with status="ok"
3. **Same channel** - recommended_channel != current_channel
4. **Low improvement** - score_gap >= CHANNEL_NOTIFICATION_GAP (15)
5. **Rate limit** - If same channel notified < 1 hour ago, skip

**Notification Trigger:**
```bash
am broadcast \
    -a com.kitsunping.ACTION_CHANNEL_AVAILABLE \
    -p app.kitsunping \
    --es recommended_channel "$recommended_channel" \
    --es current_channel "$current_channel" \
    --ei score_gap "$score_gap" \
    --es band "$band"
```

**State Tracking:**
File: `channel_notification.state`
```
last_notification_ts=1234567890
last_notified_channel=11
last_score_gap=20
last_band=2g
```

### Integration Point - `network/wifi/cycle.sh`

**Location:** End of `network__wifi__cycle()` function, after M2 auto-trigger

```bash
# M4: Check if notification should be sent for better channel availability
if command -v network__wifi__channel_notification_check >/dev/null 2>&1; then
    case "$wifi_chan" in ''|*[!0-9]*|0) ;; *)
        network__wifi__channel_notification_check "$wifi_chan" >/dev/null 2>&1 || true
    ;; esac
fi
```

This runs on every WiFi cycle (~10-15s intervals), but rate-limiting ensures notifications are not spammy.

### Frontend (Android App)

#### Receiver - `MainActivity.kt`

**BroadcastReceiver:**
```kotlin
private val channelNotificationReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != "com.kitsunping.ACTION_CHANNEL_AVAILABLE") return
        
        val recommendedChannel = intent.getStringExtra("recommended_channel") ?: return
        val currentChannel = intent.getStringExtra("current_channel") ?: return
        val scoreGap = intent.getIntExtra("score_gap", 0)
        val band = intent.getStringExtra("band") ?: "unknown"
        
        NotificationHelper.showChannelAvailableNotification(
            context,
            recommendedChannel,
            currentChannel,
            scoreGap,
            band
        )
    }
}
```

**Registration:** Registered in `onStart()`, unregistered in `onStop()`

#### Notification Display - `NotificationHelper.kt`

**Channel:** `CHANNEL_ID_CHANNEL_AVAILABLE` ("Better WiFi Channel")
- **Importance:** LOW (non-intrusive)
- **Description:** "Notifications when a better WiFi channel is available"

**Notification Format:**
- **Title:** "Better WiFi channel available"
- **Text:** "Channel 11 (+20 point improvement) - 2.4 GHz"
- **Priority:** LOW
- **Auto-cancel:** true (dismissable)
- **Notification ID:** 1002 (fixed ID, replaces previous notification)

## User Experience Flow

1. **Background Monitoring:** Module continuously monitors WiFi quality via M2 auto-trigger
2. **Auto-scan:** When quality degrades (score < 65 for 3 cycles), M2 triggers channel scan
3. **Cache Update:** Router returns recommendation with score_gap
4. **Notification Check:** M4 function runs on next WiFi cycle, detects improvement
5. **User Alert:** If score_gap >= 15, Android notification appears
6. **User Action:** User can:
   - Dismiss notification (no action)
    - Open the app to view details on the "Analyze Channels" screen
   - Wait for manual channel change feature (P4 - future)

## Rate-Limiting Strategy

### Notification Spam Prevention
- **Same channel:** If channel 11 was notified 30 minutes ago, don't re-notify for channel 11 even if score_gap changes
- **Different channel:** If channel 1 becomes available, notify immediately even if channel 11 was notified recently
- **Interval:** 1 hour (3600s) - configurable via `kitsuneping.channel.notification_interval_sec`

### Integration with M2
- M2 rate-limits scans to every 5 minutes
- M4 checks cache on every cycle (~10-15s) but won't spam due to:
  1. Rate-limit state tracking
  2. Cache TTL (15 minutes) - stale recommendations expire
  3. Guard: same channel = skip notification

## Configuration

### Module (setprop)
```bash
# Minimum score improvement to trigger notification (default: 15)
setprop kitsuneping.channel.notification_gap 20

# Rate-limit interval in seconds (default: 3600 = 1 hour)
setprop kitsuneping.channel.notification_interval_sec 1800  # 30 minutes
```

### Testing Override
```bash
# Force notification for testing (bypass rate-limit)
rm /sdcard/kitsuneping_cache/channel_notification.state

# Create test recommendation
cat > /sdcard/kitsuneping_cache/router_channel_response.json <<'EOF'
{
  "status": "ok",
  "recommended_channel": 11,
  "current_channel": 6,
  "score": 85,
  "score_gap": 20,
  "band": "2g"
}
EOF

# Manually trigger notification check (requires sourcing function)
. /data/adb/modules/Kitsunping/network/app/router_channel.sh
network__wifi__channel_notification_check 6
```

## Testing

**Script:** `tools/test_channel_notification.sh`

**Test Cases:**
1. **T1:** Same channel (current=6, recommended=6) → No notification
2. **T2:** Low score gap (gap=10 < 15) → No notification
3. **T3:** Valid improvement (gap=20 >= 15) → Notification sent, state created
4. **T4:** Rate limit (same channel within 1 hour) → No notification
5. **T5:** Different channel (11→1) → New notification, state updated
6. **T6:** Invalid current_channel (0 or non-numeric) → No notification
7. **T7:** Missing cache file → No notification

**Expected:** 7/7 PASS

## Dependencies

### Module
- `router_channel.sh` - HTTP client, cache management, telemetry
- `cycle.sh` - WiFi monitoring loop, integration point
- M2 auto-trigger - Generates cache data for M4 to consume

### App
- `MainActivity.kt` - BroadcastReceiver registration
- `NotificationHelper.kt` - Notification channel creation and display
- Android notification permissions (handled by existing flow)

## Future Enhancements (P4 - Manual Channel Change)

When P4 is implemented, M4 notifications can include:
- **Action button:** "Apply Channel 11" - triggers the router CGI to change the channel
- **PendingIntent:** Opens app directly to channel recommendation screen
- **Expanded text:** "Tap to apply automatically (WiFi will disconnect for 10s)"

## Known Limitations

1. **No manual control:** User cannot apply recommended channel from notification (requires P4)
2. **Background only:** Notifications only appear when app is running in background (receiver registered in onStart)
3. **No history:** State file only tracks last notification, no log of past recommendations
4. **Fixed threshold:** score_gap >= 15 is hardcoded default, requires setprop to change
5. **No dismissal tracking:** If user dismisses notification, same channel may re-notify after 1 hour

## Files Modified

### Module
- `Kitsunping/network/app/router_channel.sh` (lines 37-56, 352-467)
- `Kitsunping/network/wifi/cycle.sh` (lines 602-612)

### App
- `KitsunpingApp/app/src/main/java/app/kitsunping/MainActivity.kt` (lines 114-163, 327-353)
- `KitsunpingApp/app/src/main/java/app/kitsunping/NotificationHelper.kt` (lines 11-16, 34-51, 153-197)

### Testing
- `tools/test_channel_notification.sh` (new file, 224 lines)

## Status

**Implementation:** ✅ Complete  
**Testing:** ⏳ Pending (requires device deployment)  
**Validation:** ⏳ Pending (user confirmation)
