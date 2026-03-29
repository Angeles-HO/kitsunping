#!/system/bin/sh
# Entorno Android = #!/system/bin/sh
# MODDIR: Direccion absoluta (!)[Magisk Kitsune/Delta] almacenada en: /data/user/0/io.github.huskydg.magisk/cache/flash
# MODDIR=${0%/*}

# Actualizacion: Variables de entorno
ERROR="ERROR"
WARNING="WARNING"
INFO="INFO"
DEBUG="DEBUG"

# Actualizacion: Nivel de logging por defecto INFO
LOG_LEVEL=2

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
  if [ $LOG_LEVEL -ge 0 ]; then
    emit_line_level "$ERROR" "$1"
  fi
}

log_warning() {
  if [ $LOG_LEVEL -ge 1 ]; then
    emit_line_level "$WARNING" "$1"
  fi
}

log_info() {
  if [ $LOG_LEVEL -ge 2 ]; then
    emit_line_level "$INFO" "$1"
  fi
}

log_debug() {
  if [ $LOG_LEVEL -ge 2 ]; then
    emit_line_level "$DEBUG" "$1"
  fi
}

log_daemon() {
  if [ $LOG_LEVEL -ge 2 ]; then
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
  if [ $LOG_LEVEL -ge 2 ]; then
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

