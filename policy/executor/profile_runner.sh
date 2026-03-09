#!/system/bin/sh
# policy/executor/profile_runner.sh

if [ -z "${SCRIPT_DIR:-}" ] || [ ! -d "${SCRIPT_DIR:-/}" ]; then
    SCRIPT_DIR="${0%/*}"
fi

if [ -z "${NEWMODPATH:-}" ] || [ ! -d "${NEWMODPATH:-/}" ]; then
    case "$SCRIPT_DIR" in
        */policy/executor) NEWMODPATH="${SCRIPT_DIR%%/policy/executor}" ;;
        */addon/policy) NEWMODPATH="${SCRIPT_DIR%%/addon/policy}" ;;
        */addon/*) NEWMODPATH="${SCRIPT_DIR%%/addon/*}" ;;
        */addon) NEWMODPATH="${SCRIPT_DIR%%/addon}" ;;
        *) NEWMODPATH="${SCRIPT_DIR%/*}" ;;
    esac
fi

: "${MODDIR:=$NEWMODPATH}"
: "${ADDON_DIR:=$NEWMODPATH/addon}"

SERVICES_LOGS_CALLED_BY_DAEMON="$NEWMODPATH/logs/services_daemon.log"
[ -f "$NEWMODPATH/addon/functions/utils/Kitsutils.sh" ] && . "$NEWMODPATH/addon/functions/utils/Kitsutils.sh"

PROFILE_WIFI_TWEAK_STATE_DIR="$MODDIR/cache/profile_wifi_tweaks"
PROFILE_WIFI_TWEAK_SCAN_THROTTLE_FILE="$PROFILE_WIFI_TWEAK_STATE_DIR/wifi_scan_throttle_enabled.prev"
PROFILE_WIFI_TWEAK_ACTIVE_FILE="$PROFILE_WIFI_TWEAK_STATE_DIR/gaming.active"
PROFILE_WIFI_TWEAK_LAST_ACTION_FILE="$PROFILE_WIFI_TWEAK_STATE_DIR/last_action"
PROFILE_WIFI_PREFLIGHT_FILE="$MODDIR/cache/preflight.state"

profile_wifi_tweak_log() {
    echo "[SYS][SERVICE][WIFI_TWEAK] $*" >> "$SERVICES_LOGS_CALLED_BY_DAEMON"
}

profile_wifi_tweak_mark_action() {
    action="$1"
    now_ts="$(date +%s 2>/dev/null || echo 0)"
    printf '%s|%s\n' "$now_ts" "$action" > "$PROFILE_WIFI_TWEAK_LAST_ACTION_FILE" 2>/dev/null || true
}

_preflight_cmd_wifi_low_latency_ok() {
    [ -f "$PROFILE_WIFI_PREFLIGHT_FILE" ] || return 1
    grep -q 'cmd_wifi_low_latency=1' "$PROFILE_WIFI_PREFLIGHT_FILE" 2>/dev/null
}

_preflight_cmd_wifi_hi_perf_ok() {
    [ -f "$PROFILE_WIFI_PREFLIGHT_FILE" ] || return 1
    grep -q 'cmd_wifi_hi_perf=1' "$PROFILE_WIFI_PREFLIGHT_FILE" 2>/dev/null
}

profile_wifi_tweak_apply_gaming() {
    mkdir -p "$PROFILE_WIFI_TWEAK_STATE_DIR" 2>/dev/null || true

    if [ ! -f "$PROFILE_WIFI_TWEAK_ACTIVE_FILE" ]; then
        prev_scan_throttle=""
        if command -v settings >/dev/null 2>&1; then
            prev_scan_throttle="$(settings get global wifi_scan_throttle_enabled 2>/dev/null | tr -d '\r\n')"
        fi
        case "$prev_scan_throttle" in
            ""|null) prev_scan_throttle="__UNSET__" ;;
        esac
        printf '%s' "$prev_scan_throttle" > "$PROFILE_WIFI_TWEAK_SCAN_THROTTLE_FILE" 2>/dev/null || true
        : > "$PROFILE_WIFI_TWEAK_ACTIVE_FILE" 2>/dev/null || true
        profile_wifi_tweak_log "backup saved wifi_scan_throttle_enabled=$prev_scan_throttle"
    fi

    if command -v settings >/dev/null 2>&1; then
        settings put global wifi_scan_throttle_enabled 0 >/dev/null 2>&1 || true
    fi

    if command -v cmd >/dev/null 2>&1; then
        cmd wifi set-connected-score 60 >/dev/null 2>&1 || true
        if _preflight_cmd_wifi_low_latency_ok; then
            cmd wifi force-low-latency-mode enabled >/dev/null 2>&1 || true
        fi
    fi

    profile_wifi_tweak_log "gaming applied: wifi_scan_throttle_enabled=0, score=60, low_latency_mode=enabled"
    profile_wifi_tweak_mark_action "gaming_applied"
}

profile_wifi_tweak_apply_benchmark() {
    mkdir -p "$PROFILE_WIFI_TWEAK_STATE_DIR" 2>/dev/null || true

    if [ ! -f "$PROFILE_WIFI_TWEAK_ACTIVE_FILE" ]; then
        prev_scan_throttle=""
        if command -v settings >/dev/null 2>&1; then
            prev_scan_throttle="$(settings get global wifi_scan_throttle_enabled 2>/dev/null | tr -d '\r\n')"
        fi
        case "$prev_scan_throttle" in
            ""|null) prev_scan_throttle="__UNSET__" ;;
        esac
        printf '%s' "$prev_scan_throttle" > "$PROFILE_WIFI_TWEAK_SCAN_THROTTLE_FILE" 2>/dev/null || true
        : > "$PROFILE_WIFI_TWEAK_ACTIVE_FILE" 2>/dev/null || true
        profile_wifi_tweak_log "backup saved wifi_scan_throttle_enabled=$prev_scan_throttle"
    fi

    if command -v settings >/dev/null 2>&1; then
        settings put global wifi_scan_throttle_enabled 0 >/dev/null 2>&1 || true
    fi

    if command -v cmd >/dev/null 2>&1; then
        cmd wifi set-connected-score 80 >/dev/null 2>&1 || true
        if _preflight_cmd_wifi_low_latency_ok; then
            cmd wifi force-low-latency-mode enabled >/dev/null 2>&1 || true
        fi
        if _preflight_cmd_wifi_hi_perf_ok; then
            cmd wifi force-hi-perf-mode enabled >/dev/null 2>&1 || true
        fi
    fi

    profile_wifi_tweak_log "benchmark applied: wifi_scan_throttle_enabled=0, score=80, low_latency_mode=enabled, hi_perf_mode=enabled_if_supported"
    profile_wifi_tweak_mark_action "benchmark_applied"
}

profile_wifi_tweak_apply_benchmark_speed() {
    mkdir -p "$PROFILE_WIFI_TWEAK_STATE_DIR" 2>/dev/null || true

    if [ ! -f "$PROFILE_WIFI_TWEAK_ACTIVE_FILE" ]; then
        prev_scan_throttle=""
        if command -v settings >/dev/null 2>&1; then
            prev_scan_throttle="$(settings get global wifi_scan_throttle_enabled 2>/dev/null | tr -d '\r\n')"
        fi
        case "$prev_scan_throttle" in
            ""|null) prev_scan_throttle="__UNSET__" ;;
        esac
        printf '%s' "$prev_scan_throttle" > "$PROFILE_WIFI_TWEAK_SCAN_THROTTLE_FILE" 2>/dev/null || true
        : > "$PROFILE_WIFI_TWEAK_ACTIVE_FILE" 2>/dev/null || true
        profile_wifi_tweak_log "backup saved wifi_scan_throttle_enabled=$prev_scan_throttle"
    fi

    if command -v settings >/dev/null 2>&1; then
        settings put global wifi_scan_throttle_enabled 0 >/dev/null 2>&1 || true
    fi

    if command -v cmd >/dev/null 2>&1; then
        cmd wifi set-connected-score 100 >/dev/null 2>&1 || true
        if _preflight_cmd_wifi_low_latency_ok; then
            cmd wifi force-low-latency-mode disabled >/dev/null 2>&1 || true
        fi
        if _preflight_cmd_wifi_hi_perf_ok; then
            cmd wifi force-hi-perf-mode enabled >/dev/null 2>&1 || true
        fi
    fi

    profile_wifi_tweak_log "benchmark_speed applied: wifi_scan_throttle_enabled=0, score=100, hi_perf_mode=enabled"
    profile_wifi_tweak_mark_action "benchmark_speed_applied"
}

profile_wifi_tweak_restore_non_gaming() {
    [ -f "$PROFILE_WIFI_TWEAK_ACTIVE_FILE" ] || return 0

    prev_scan_throttle="__UNSET__"
    [ -f "$PROFILE_WIFI_TWEAK_SCAN_THROTTLE_FILE" ] && prev_scan_throttle="$(cat "$PROFILE_WIFI_TWEAK_SCAN_THROTTLE_FILE" 2>/dev/null || echo "__UNSET__")"

    if command -v settings >/dev/null 2>&1; then
        case "$prev_scan_throttle" in
            __UNSET__)
                settings delete global wifi_scan_throttle_enabled >/dev/null 2>&1 || true
                ;;
            *)
                settings put global wifi_scan_throttle_enabled "$prev_scan_throttle" >/dev/null 2>&1 || true
                ;;
        esac
    fi

    if command -v cmd >/dev/null 2>&1; then
        if _preflight_cmd_wifi_low_latency_ok; then
            cmd wifi force-low-latency-mode disabled >/dev/null 2>&1 || true
        fi
        if _preflight_cmd_wifi_hi_perf_ok; then
            cmd wifi force-hi-perf-mode disabled >/dev/null 2>&1 || true
        fi
        cmd wifi reset-connected-score >/dev/null 2>&1 || true
    fi

    rm -f "$PROFILE_WIFI_TWEAK_ACTIVE_FILE" "$PROFILE_WIFI_TWEAK_SCAN_THROTTLE_FILE" 2>/dev/null || true
    profile_wifi_tweak_log "restored non-gaming state: wifi_scan_throttle_enabled=$prev_scan_throttle low_latency_mode=disabled"
    profile_wifi_tweak_mark_action "non_gaming_restored"
    # telemetry: cumulative restore counter
    _tweak_restore_ctr="$MODDIR/cache/telemetry.tweak_restores"
    _tweak_restore_val=0
    [ -f "$_tweak_restore_ctr" ] && _tweak_restore_val="$(cat "$_tweak_restore_ctr" 2>/dev/null || echo 0)"
    case "$_tweak_restore_val" in ''|*[!0-9]*) _tweak_restore_val=0 ;; esac
    _tweak_restore_val=$((_tweak_restore_val + 1))
    printf '%s' "$_tweak_restore_val" > "$_tweak_restore_ctr" 2>/dev/null || true
}

profile_wifi_tweak_apply_for_profile() {
    case "$1" in
        gaming) profile_wifi_tweak_apply_gaming ;;
        benchmark|benchmark_gaming) profile_wifi_tweak_apply_benchmark ;;
        benchmark_speed) profile_wifi_tweak_apply_benchmark_speed ;;
        speed|stable) profile_wifi_tweak_restore_non_gaming ;;
    esac
}

run_profile_script() {
    profile_name="$1"
    profile_script=""

    case "$profile_name" in
        speed) profile_script="$NEWMODPATH/net_profiles/speed_profile.sh" ;;
        stable) profile_script="$NEWMODPATH/net_profiles/stable_profile.sh" ;;
        gaming) profile_script="$NEWMODPATH/net_profiles/gaming_profile.sh" ;;
        benchmark|benchmark_gaming) profile_script="$NEWMODPATH/net_profiles/benchmark_gaming_profile.sh" ;;
        benchmark_speed) profile_script="$NEWMODPATH/net_profiles/benchmark_speed_profile.sh" ;;
        *) echo "[SYS][SERVICE][WARN] Perfil desconocido: $profile_name" >> "$SERVICES_LOGS_CALLED_BY_DAEMON"; return 1 ;;
    esac

    if [ ! -f "$profile_script" ]; then
        echo "[SYS][SERVICE][WARN] Script de perfil no encontrado: $profile_script" >> "$SERVICES_LOGS_CALLED_BY_DAEMON"
        return 1
    fi

    profile_wifi_tweak_apply_for_profile "$profile_name"

    echo "[SYS][SERVICE] Aplicando perfil: $profile_name ($profile_script)" >> "$SERVICES_LOGS_CALLED_BY_DAEMON"
    . "$profile_script" >>"$SERVICES_LOGS_CALLED_BY_DAEMON" 2>&1 || {
        echo "[SYS][SERVICE][ERROR] Fallo al aplicar perfil: $profile_name" >> "$SERVICES_LOGS_CALLED_BY_DAEMON"
        return 1
    }

    return 0
}