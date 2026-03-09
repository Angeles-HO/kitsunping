#!/system/bin/sh

log_info() { printf '[KITSUN][INFO] %s\n' "$*" >&2; }
log_debug() { printf '[KITSUN][DEBUG] %s\n' "$*" >&2; }
log_warn() { printf '[KITSUN][WARN] %s\n' "$*" >&2; }
log_error() { printf '[KITSUN][ERROR] %s\n' "$*" >&2; }
