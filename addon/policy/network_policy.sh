#!/system/bin/sh
# Kitsunping/addon/policy/network_policy.sh - controlador de perfiles de red basado en el estado de Wi-Fi
# Parte de Kitsunping - daemon.sh

SCRIPT_DIR="${0%/*}"            # kitsunping/addon/policy
ADDON_DIR="${SCRIPT_DIR%/*}"    # kitsunping/addon
MODDIR="${ADDON_DIR%/*}"        # kitsunping (raíz del módulo)
POLICY_DIR="$SCRIPT_DIR"
LOG_DIR="$MODDIR/logs"
POLICY_LOG="$LOG_DIR/policy.log"
STATE_FILE="$MODDIR/cache/daemon.state"
LAST_EVENT_FILE="$MODDIR/cache/daemon.last"
REQUEST_FILE="$MODDIR/cache/policy.request"
CURRENT_FILE="$MODDIR/cache/policy.current"
EXECUTOR_SH="$MODDIR/addon/policy/executor.sh"
KITSUTILS_SH="$MODDIR/addon/functions/debug/shared_errors.sh"
DECIDE_PROFILE_SH="$POLICY_DIR/decide_profile.sh"
MIN_REAPPLY_SEC=20

mkdir -p "$LOG_DIR" 2>/dev/null
: >> "$POLICY_LOG" 2>/dev/null

if [ -f "$KITSUTILS_SH" ]; then
	. "$KITSUTILS_SH"
else
	echo "[POLICY][ERROR] Kitsutils not found: $KITSUTILS_SH" >> "$POLICY_LOG"
	# Basic fallback for logging and utilities when Kitsutils is not available
	log_info() { printf '[POLICY][INFO] %s\n' "$*" >> "$POLICY_LOG"; }
	log_debug() { printf '[POLICY][DEBUG] %s\n' "$*" >> "$POLICY_LOG"; }
	log_error() { printf '[POLICY][ERROR] %s\n' "$*" >> "$POLICY_LOG"; }
	command_exists() { command -v "$1" >/dev/null 2>&1; }
fi

now_epoch() {
	date +%s 2>/dev/null 2>/dev/null || echo 0
}

atomic_write() {
	local target="$1" tmp
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

# Log + persist desired profile as a request (informational)
log_info "[POLICY] decided profile=$profile wifi=$wifi_state iface=$iface event=$last_event"
printf '%s' "$profile" | atomic_write "$REQUEST_FILE" || true

# Delegate applying to the executor (single-writer for policy.target/policy.current)
current_profile=""
[ -f "$CURRENT_FILE" ] && current_profile="$(cat "$CURRENT_FILE" 2>/dev/null)"

if [ -x "$EXECUTOR_SH" ]; then
	EVENT_NAME="PROFILE_CHANGED" \
	EVENT_TS="${now:-0}" \
	EVENT_DETAILS="from=${current_profile:-} to=$profile policy=network_policy" \
	LOG_DIR="$LOG_DIR" \
	POLICY_LOG="$POLICY_LOG" \
	"$EXECUTOR_SH" >> "$POLICY_LOG" 2>&1 &
else
	log_error "[POLICY] executor not executable: $EXECUTOR_SH"
fi

exit 0