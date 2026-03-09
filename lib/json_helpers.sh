#!/system/bin/sh

json_escape() {
    printf '%s' "$1" \
      | sed 's/\\\\/\\\\\\\\/g; s/"/\\\\"/g; s/\t/\\\\t/g; s/\r/\\\\r/g; s/\n/\\\\n/g'
}
