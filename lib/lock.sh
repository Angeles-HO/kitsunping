#!/system/bin/sh

lock_acquire() {
    local lock_dir="$1"
    [ -n "$lock_dir" ] || return 1
    mkdir "$lock_dir" 2>/dev/null
}

lock_release() {
    local lock_dir="$1"
    [ -n "$lock_dir" ] || return 1
    rmdir "$lock_dir" 2>/dev/null || rm -rf "$lock_dir" 2>/dev/null
}
