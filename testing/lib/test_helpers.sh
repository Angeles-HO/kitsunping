#!/bin/sh

set -u

FAILURES=0

fail() {
    printf '[FAIL] %s\n' "$*" >&2
    FAILURES=$((FAILURES + 1))
}

pass() {
    printf '[PASS] %s\n' "$*"
}

assert_rc() {
    expected="$1"
    actual="$2"
    message="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$message"
    else
        fail "$message (expected rc=$expected actual rc=$actual)"
    fi
}

assert_eq() {
    expected="$1"
    actual="$2"
    message="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$message"
    else
        fail "$message (expected=$expected actual=$actual)"
    fi
}

assert_file_exists() {
    file_path="$1"
    message="$2"
    if [ -f "$file_path" ]; then
        pass "$message"
    else
        fail "$message (missing file: $file_path)"
    fi
}

assert_file_not_exists() {
    file_path="$1"
    message="$2"
    if [ ! -f "$file_path" ]; then
        pass "$message"
    else
        fail "$message (unexpected file: $file_path)"
    fi
}

assert_contains() {
    needle="$1"
    haystack="$2"
    message="$3"
    if printf '%s' "$haystack" | grep -Fq "$needle"; then
        pass "$message"
    else
        fail "$message (missing fragment: $needle)"
    fi
}

assert_file_contains() {
    file_path="$1"
    needle="$2"
    message="$3"
    if grep -Fq "$needle" "$file_path" 2>/dev/null; then
        pass "$message"
    else
        fail "$message (missing fragment: $needle in $file_path)"
    fi
}

source_range() {
    file_path="$1"
    start_line="$2"
    end_line="$3"
    tmp_file=$(mktemp)
    sed -n "${start_line},${end_line}p" "$file_path" > "$tmp_file" || {
        rm -f "$tmp_file"
        return 1
    }
    # shellcheck disable=SC1090
    . "$tmp_file"
    rc=$?
    rm -f "$tmp_file"
    return "$rc"
}

finish() {
    if [ "$FAILURES" -ne 0 ]; then
        printf 'Test failures: %s\n' "$FAILURES" >&2
        exit 1
    fi
    exit 0
}