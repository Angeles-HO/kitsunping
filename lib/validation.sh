#!/system/bin/sh

is_uint() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

uint_or_default() {
    local raw="$1" def="$2"
    if is_uint "$raw"; then
        printf '%s' "$raw"
    else
        printf '%s' "$def"
    fi
}

is_bool_true() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}
