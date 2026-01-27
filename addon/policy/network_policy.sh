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
KITSUTILS_SH="$MODDIR/addon/functions/debug/shared_errors.sh"
DECIDE_PROFILE_SH="$POLICY_DIR/decide_profile.sh"
MIN_REAPPLY_SEC=20

mkdir -p "$LOG_DIR" 2>/dev/null
: >> "$POLICY_LOG" 2>/dev/null

if [ -f "$KITSUTILS_SH" ]; then
	. "$KITSUTILS_SH"
else
	echo "[POLICY][ERROR] Kitsutils no encontrado: $KITSUTILS_SH" >> "$POLICY_LOG"
	# Fallback básico de logging y utilidades cuando no hay Kitsutils
	log_info() { printf '[POLICY][INFO] %s\n' "$*" >> "$POLICY_LOG"; }
	log_debug() { printf '[POLICY][DEBUG] %s\n' "$*" >> "$POLICY_LOG"; }
	log_error() { printf '[POLICY][ERROR] %s\n' "$*" >> "$POLICY_LOG"; }
	command_exists() { command -v "$1" >/dev/null 2>&1; }
fi

now_epoch() {
	date +%s 2>/dev/null || busybox date +%s 2>/dev/null || echo 0
}

read_state() {
	iface="none"; wifi_state="unknown"; wifi_details=""; transport="none"; wifi_egress=0
	[ ! -f "$STATE_FILE" ] && log_debug "[POLICY] state ausente; usando perfil por defecto" && return

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

# Escribir el perfil decidido en el archivo target para que el executor lo aplique
tmp="$MODDIR/cache/policy.target.$$" # archivo temporal seguro
# Logging básico del perfil decidido
log_info "[POLICY] profile=$profile wifi=$wifi_state iface=$iface event=$last_event" >> "$POLICY_LOG"
# Escribir el perfil en un archivo temporal y luego renombrarlo para evitar condiciones de carrera
echo "$profile" > "$tmp" && mv "$tmp" "$MODDIR/cache/policy.target" 

exit 0