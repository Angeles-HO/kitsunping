#!/system/bin/sh
# Kitsunping/policy/engine/network_policy.sh

SCRIPT_DIR="${0%/*}"            # kitsunping/policy/engine
POLICY_DIR="${SCRIPT_DIR%/*}"    # kitsunping/policy
MODDIR="${SCRIPT_DIR%/policy/engine}"        # kitsunping
LOG_DIR="$MODDIR/logs"
POLICY_LOG="$LOG_DIR/policy.log"
STATE_FILE="$MODDIR/cache/daemon.state"
LAST_EVENT_FILE="$MODDIR/cache/daemon.last"
AUTO_REQUEST_FILE="$MODDIR/cache/policy.auto_request"
CURRENT_FILE="$MODDIR/cache/policy.current"
EXECUTOR_SH="$MODDIR/policy/executor/executor.sh"
KITSUTILS_SH="$MODDIR/addon/functions/debug/shared_errors.sh"
DECIDE_PROFILE_SH="$MODDIR/policy/rules/decide_profile.sh"
MIN_REAPPLY_SEC=20

mkdir -p "$LOG_DIR" 2>/dev/null
: >> "$POLICY_LOG" 2>/dev/null

if [ -f "$KITSUTILS_SH" ]; then
	. "$KITSUTILS_SH"
else
	echo "[POLICY][ERROR] Kitsutils not found: $KITSUTILS_SH" >> "$POLICY_LOG"
	log_info() { printf '[POLICY][INFO] %s\n' "$*" >> "$POLICY_LOG"; }
	log_debug() { printf '[POLICY][DEBUG] %s\n' "$*" >> "$POLICY_LOG"; }
	log_error() { printf '[POLICY][ERROR] %s\n' "$*" >> "$POLICY_LOG"; }
	command_exists() { command -v "$1" >/dev/null 2>&1; }
fi

now_epoch() {
	date +%s 2>/dev/null 2>/dev/null || echo 0
}

atomic_write() {
	local target="$1" write_class="${2:-normal}" tmp
	case "$write_class" in
		debug_only)
			if command -v kitsunping_debug_enabled >/dev/null 2>&1 && ! kitsunping_debug_enabled; then
				cat >/dev/null || return 1
				return 0
			fi
			;;
		normal|"") ;;
		*) return 2 ;;
	esac
	tmp=$(mktemp "${target}.XXXXXX" 2>/dev/null) || tmp="${target}.$$.$(date +%s).tmp"
	if cat - > "$tmp" 2>/dev/null; then
		mv "$tmp" "$target" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
		return 0
	fi
	rm -f "$tmp" 2>/dev/null
	return 1
}

read_state() {
	iface="none"; wifi_state="unknown"; wifi_details=""; transport="none"; wifi_egress=0
	[ ! -f "$STATE_FILE" ] && log_debug "[POLICY] state file missing; using default profile" && return

	while IFS= read -r line; do
		case "$line" in
			iface=*) iface="${line#iface=}" ;;
			transport=*) transport="${line#transport=}" ;;
			wifi.state=*) wifi_state="${line#wifi.state=}" ;;
			wifi.reason=*) wifi_details="${line#wifi.reason=}" ;;
			wifi.egress=*) wifi_egress="${line#wifi.egress=}" ;;
			*) : ;;
		esac
	done < "$STATE_FILE"

	[ -z "$wifi_state" ] && wifi_state="unknown"
	[ -z "$iface" ] && iface="none"
}

read_last_event() {
	last_event=""
	last_ts=0
	details=""

	[ ! -f "$LAST_EVENT_FILE" ] && return

	set -- $(cat "$LAST_EVENT_FILE" 2>/dev/null)
	last_event="$1"
	last_ts="$2"
	shift 2
	details="$*"

	case "$last_ts" in
		''|*[!0-9]*) last_ts=0 ;;
	esac
}

read_state
read_last_event

now=$(now_epoch)
if [ "$now" -ne 0 ] && [ -n "$last_event" ] && [ "$last_ts" -gt 0 ]; then
	diff=$((now - last_ts))
	if [ "$diff" -lt "$MIN_REAPPLY_SEC" ]; then
		log_debug "[POLICY] Skip apply (debounce ${MIN_REAPPLY_SEC}s) last_event=$last_event ts=$last_ts"
		exit 0
	fi
fi

[ -f "$DECIDE_PROFILE_SH" ] && . "$DECIDE_PROFILE_SH"

if command_exists pick_profile; then
	profile="$(pick_profile "$wifi_state" "$iface" "$details" "$wifi_details" "$last_event")"
else
	profile="stable"
fi

log_info "[POLICY] automatic candidate=$profile wifi=$wifi_state iface=$iface event=$last_event"
printf '%s' "$profile" | atomic_write "$AUTO_REQUEST_FILE" || true

exit 0
