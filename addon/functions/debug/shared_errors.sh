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
LOG_LEVEL=3

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

# Funciones de logging
log_error() {
  if [ $LOG_LEVEL -ge 0 ]; then
    echo -e "[$ERROR] $1" >&2
  fi
}

log_warning() {
  if [ $LOG_LEVEL -ge 1 ]; then
    echo -e "[$WARNING] $1" >&2
  fi
}

log_info() {
  if [ $LOG_LEVEL -ge 2 ]; then
    echo -e "[$INFO] $1"
  fi
}

log_debug() {
  if [ $LOG_LEVEL -ge 3 ]; then
    echo -e "[$DEBUG] $1"
  fi
}

log_daemon() {
  if [ $LOG_LEVEL -ge 2 ]; then
    echo -e "[DAEMON][$INFO] $1"
  fi
}

log_policy() {
  if [ $LOG_LEVEL -ge 2 ]; then
    echo -e "[POLICY][$INFO] $1"
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

