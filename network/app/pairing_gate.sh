#!/system/bin/sh
# pairing_gate.sh — router pairing validation ONLY.
# This module NEVER writes policy.request or touches local profile decisions.
# Responsibility: answer "is this device currently paired with the router?"
#                 and sync pairing-state-change events.
# Sourced by cycle.sh. MODDIR must be set. Depends on: state_io.sh (log_info).

# -----------------------------------------------------------------------
# JSON field reader (jq with sed fallback, no external deps required)
# -----------------------------------------------------------------------

network__app__read_pairing_json_field() {
    local key="$1" file="$2"
    local value_raw
    [ -f "$file" ] || { printf ''; return 0; }

    if command -v jq >/dev/null 2>&1; then
        jq -r ".${key} // empty" "$file" 2>/dev/null || true
        return 0
    fi

    value_raw="$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file" 2>/dev/null | head -n1)"
    if [ -n "$value_raw" ]; then
        printf '%s' "$value_raw"
        return 0
    fi

    value_raw="$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\([^,}]*\).*/\1/p" "$file" 2>/dev/null | head -n1 | tr -d '\"[:space:]')"
    case "$value_raw" in
        true|false|null|[0-9]*)
            printf '%s' "$value_raw"
            ;;
    esac
}

# -----------------------------------------------------------------------
# Pairing gate — decides if router-dependent features are unlocked.
# Rule: only explicit "1/true/yes/on" in the prop enables the gate.
#       auto/empty/unknown → gate disabled (local profiles always work).
# -----------------------------------------------------------------------

network__app__target_pairing_gate_ok() {
    local require_raw require_pairing paired_now

    require_raw="$(getprop persist.kitsunping.target_prop_require_pairing 2>/dev/null | tr -d '\r\n')"
    case "$require_raw" in
        0|false|FALSE|no|NO|off|OFF)
            require_pairing=0
            ;;
        1|true|TRUE|yes|YES|on|ON)
            require_pairing=1
            ;;
        auto|AUTO|'')
            # auto and empty: pairing gate is OFF — local profiles always work
            # regardless of router/KITSUNROUTER_ENABLE state.
            require_pairing=0
            ;;
        *)
            require_pairing=0
            ;;
    esac

    [ "$require_pairing" -eq 0 ] && return 0

    paired_now="$(get_router_paired_flag)"
    [ "$paired_now" = "1" ]
}

# -----------------------------------------------------------------------
# Pairing sync cycle — emits events on router paired/unpaired transitions.
# No profile decisions here: only event emission for app/daemon awareness.
# -----------------------------------------------------------------------

network__app__pairing_sync_cycle() {
    [ "${KITSUNROUTER_ENABLE:-0}" -eq 1 ] || return 0

    router_paired_now="$(get_router_paired_flag)"
    if [ "$router_paired_now" != "$last_router_paired" ]; then
        if [ "$router_paired_now" = "1" ]; then
            emit_event "$EV_ROUTER_PAIRED"   "source=pairing_gate paired=1"
        else
            emit_event "$EV_ROUTER_UNPAIRED" "source=pairing_gate paired=0"
        fi
        last_router_paired="$router_paired_now"
    fi
}
