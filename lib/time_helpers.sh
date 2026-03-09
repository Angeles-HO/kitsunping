#!/system/bin/sh

now_epoch() {
    date +%s 2>/dev/null || echo 0
}
