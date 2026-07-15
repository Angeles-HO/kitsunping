#!/system/bin/sh
# Entorno Android = #!/system/bin/sh
# MODDIR: Direccion absoluta (!)[Magisk Kitsune/Delta] almacenada en: /data/user/0/io.github.huskydg.magisk/cache/flash
# MODDIR=${0%/*}

# Actualizacion: Variables de entorno
ERROR="ERROR"
WARNING="WARNING"
INFO="INFO"
DEBUG="DEBUG"

# Runtime policy: `persist.kitsunping.debug=0` keeps warnings/errors only;
# `=1` enables informational and diagnostic output. The property is read at
# emission time so the app can change it without restarting the daemon.
KITSUNPING_DEBUG_PROP="${KITSUNPING_DEBUG_PROP:-persist.kitsunping.debug}"

kitsunping_debug_enabled() {
  local raw prop_file
  raw="${KITSUNPING_DEBUG_OVERRIDE:-}"

  if [ -z "$raw" ] && command -v getprop >/dev/null 2>&1; then
    raw="$(getprop "$KITSUNPING_DEBUG_PROP" 2>/dev/null | tr -d '\r\n')"
  fi

  if [ -z "$raw" ]; then
    prop_file="${MODDIR:-}/system.prop"
    [ -f "$prop_file" ] || prop_file="${NEWMODPATH:-}/system.prop"
    if [ -f "$prop_file" ]; then
      raw="$(sed -n 's/^[[:space:]]*persist\.kitsunping\.debug[[:space:]]*=[[:space:]]*//p' "$prop_file" | tail -n 1 | tr -d '\r\n')"
    fi
  fi

  case "$raw" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# 0=ERROR, 1=WARNING, 2=INFO, 3=DEBUG. INFO and DEBUG are deliberately
# suppressed in normal runtime mode to keep logs actionable and bounded.
runtime_log_level() {
  if kitsunping_debug_enabled; then
    printf '%s' 3
  else
    printf '%s' 1
  fi
}

LOG_LEVEL="$(runtime_log_level)"

# Color output is enabled only for plain terminal output.
# If ui_print exists (Magisk installer context), keep plain text for compatibility.
LOG_COLOR_ENABLED=0
LOG_COLOR_RESET=""
LOG_COLOR_ERROR=""
LOG_COLOR_WARNING=""
LOG_COLOR_INFO=""
LOG_COLOR_DEBUG=""

init_log_colors() {
  if command -v ui_print >/dev/null 2>&1; then
    LOG_COLOR_ENABLED=0
    return 0
  fi

  if [ -n "${NO_COLOR:-}" ] || [ "${KITSUNPING_NO_COLOR:-0}" = "1" ]; then
    LOG_COLOR_ENABLED=0
    return 0
  fi

  case "${TERM:-}" in
    ""|dumb) LOG_COLOR_ENABLED=0; return 0 ;;
  esac

  # Use stderr as default stream for logs outside ui_print.
  if [ -t 2 ]; then
    LOG_COLOR_ENABLED=1
    LOG_COLOR_RESET='\033[0m'
    LOG_COLOR_ERROR='\033[1;31m'
    LOG_COLOR_WARNING='\033[1;33m'
    LOG_COLOR_INFO='\033[1;36m'
    LOG_COLOR_DEBUG='\033[0;37m'
  else
    LOG_COLOR_ENABLED=0
  fi
}

# Establecer nivel de logging
# 0=ERROR, 1=WARNING, 2=INFO, 3=DEBUG
set_log_level() {
  case "$1" in
    "$ERROR") LOG_LEVEL=0 ;;
    "$WARNING") LOG_LEVEL=1 ;;
    "$INFO") LOG_LEVEL=2 ;;
    "$DEBUG") LOG_LEVEL=3 ;;
    *) log_error "Nivel de log desconocido: $1" ;;
  esac
}

should_emit_log_level() {
  local level="$1" active
  active="$(runtime_log_level)"
  case "$level" in
    "$ERROR") [ "$active" -ge 0 ] ;;
    "$WARNING") [ "$active" -ge 1 ] ;;
    "$INFO") [ "$active" -ge 2 ] ;;
    "$DEBUG") [ "$active" -ge 3 ] ;;
    *) return 1 ;;
  esac
}

emit_line() {
  if command -v ui_print >/dev/null 2>&1; then
    ui_print "$1"
  else
    echo "$1"
  fi
}

emit_line_level() {
  level="$1"
  msg="$2"

  if command -v ui_print >/dev/null 2>&1; then
    ui_print "[$level] $msg"
    return 0
  fi

  if [ "${LOG_COLOR_ENABLED:-0}" -eq 1 ]; then
    case "$level" in
      "$ERROR") color="$LOG_COLOR_ERROR" ;;
      "$WARNING") color="$LOG_COLOR_WARNING" ;;
      "$INFO") color="$LOG_COLOR_INFO" ;;
      "$DEBUG") color="$LOG_COLOR_DEBUG" ;;
      *) color="" ;;
    esac
    if [ -n "$color" ]; then
      printf '%b[%s] %s%b\n' "$color" "$level" "$msg" "$LOG_COLOR_RESET" >&2
      return 0
    fi
  fi

  printf '[%s] %s\n' "$level" "$msg" >&2
}

# Funciones de logging
log_error() {
  if should_emit_log_level "$ERROR"; then
    emit_line_level "$ERROR" "$1"
  fi
}

log_warning() {
  if should_emit_log_level "$WARNING"; then
    emit_line_level "$WARNING" "$1"
  fi
}

log_info() {
  # Installer guidance is user-facing, not diagnostic runtime logging.  Magisk
  # exposes ui_print only while flashing, so always render it even when normal
  # runtime Debug Mode suppresses informational logs.
  if command -v ui_print >/dev/null 2>&1; then
    emit_line_level "$INFO" "$1"
    return 0
  fi

  if should_emit_log_level "$INFO"; then
    emit_line_level "$INFO" "$1"
  fi
}

log_debug() {
  if should_emit_log_level "$DEBUG"; then
    emit_line_level "$DEBUG" "$1"
  fi
}

log_daemon() {
  if should_emit_log_level "$INFO"; then
    if command -v ui_print >/dev/null 2>&1; then
      ui_print "[DAEMON][$INFO] $1"
    else
      if [ "${LOG_COLOR_ENABLED:-0}" -eq 1 ]; then
        printf '%b[DAEMON][%s] %s%b\n' "$LOG_COLOR_INFO" "$INFO" "$1" "$LOG_COLOR_RESET" >&2
      else
        printf '[DAEMON][%s] %s\n' "$INFO" "$1" >&2
      fi
    fi
  fi
}

log_policy() {
  if should_emit_log_level "$INFO"; then
    if command -v ui_print >/dev/null 2>&1; then
      ui_print "[POLICY][$INFO] $1"
    else
      if [ "${LOG_COLOR_ENABLED:-0}" -eq 1 ]; then
        printf '%b[POLICY][%s] %s%b\n' "$LOG_COLOR_INFO" "$INFO" "$1" "$LOG_COLOR_RESET" >&2
      else
        printf '[POLICY][%s] %s\n' "$INFO" "$1" >&2
      fi
    fi
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

init_log_colors

