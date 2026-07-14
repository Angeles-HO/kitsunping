#!/system/bin/sh
# property_inventory.sh
# Collects Android property keys from static sources and runtime snapshots.
#
# Why:
# - getprop without args only shows currently-set properties.
# - build.prop files are incomplete for runtime/vendor-triggered properties.
#
# Usage examples:
#   sh tools/property_inventory.sh static
#   sh tools/property_inventory.sh static --with-binaries
#   sh tools/property_inventory.sh snapshot /sdcard/props.before.txt
#   sh tools/property_inventory.sh diff /sdcard/props.before.txt /sdcard/props.after.txt

set -u

MODE="${1:-help}"
shift 2>/dev/null || true

OUT_DIR="${PROP_INV_OUT_DIR:-/sdcard/kitsunping_prop_inventory}"
WITH_BINARIES=0
MAX_BINARY_FILES="${PROP_INV_MAX_BINARY_FILES:-300}"

PROP_REGEX='(ro|persist|sys|vendor|debug|dalvik|init\.svc)\.[A-Za-z0-9._-]+'

log() { printf '%s\n' "$*"; }
err() { printf '[ERR] %s\n' "$*" >&2; }

usage() {
    cat <<'EOF'
property_inventory.sh

Modes:
  static [--with-binaries]
      Collect property keys from static sources:
      - property_contexts (plat/vendor/odm/product)
      - init rc setprop and property: triggers
      - known *.prop files
      - (optional) strings from selected binaries

  snapshot <out_file>
      Save current getprop snapshot to out_file (sorted key=value).

  diff <before_snapshot> <after_snapshot>
      Compare two snapshots and print added/changed/removed keys.

Environment:
  PROP_INV_OUT_DIR          Output directory for static mode (default: /sdcard/kitsunping_prop_inventory)
  PROP_INV_MAX_BINARY_FILES Max files scanned in --with-binaries mode (default: 300)
EOF
}

ensure_out_dir() {
    mkdir -p "$OUT_DIR" 2>/dev/null || {
        err "Cannot create output dir: $OUT_DIR"
        return 1
    }
    return 0
}

extract_from_property_contexts() {
    local out="$1"
    : > "$out"
    for f in \
        /system/etc/selinux/plat_property_contexts \
        /vendor/etc/selinux/vendor_property_contexts \
        /odm/etc/selinux/odm_property_contexts \
        /product/etc/selinux/product_property_contexts; do
        [ -f "$f" ] || continue
        awk '
            /^[[:space:]]*#/ {next}
            /^[[:space:]]*$/ {next}
            {print $1}
        ' "$f" 2>/dev/null >> "$out"
    done
    sort -u "$out" -o "$out" 2>/dev/null || true
}

extract_from_init_rc() {
    local out="$1" tmp
    tmp="${out}.tmp.$$"
    : > "$tmp"

    for d in /system/etc/init /vendor/etc/init /odm/etc/init /product/etc/init; do
        [ -d "$d" ] || continue

        # setprop key value
        grep -RhoE '(^|[[:space:]])(setprop|resetprop)[[:space:]]+[A-Za-z0-9._-]+' "$d" 2>/dev/null \
            | awk '{print $NF}' >> "$tmp"

        # on property:key=value triggers
        grep -RhoE 'property:[A-Za-z0-9._-]+=' "$d" 2>/dev/null \
            | sed 's/^property://; s/=$//' >> "$tmp"
    done

    grep -E "$PROP_REGEX" "$tmp" 2>/dev/null | sort -u > "$out" 2>/dev/null || : > "$out"
    rm -f "$tmp" 2>/dev/null || true
}

extract_from_prop_files() {
    local out="$1" tmp
    tmp="${out}.tmp.$$"
    : > "$tmp"

    for f in \
        /system/build.prop \
        /vendor/build.prop \
        /odm/build.prop \
        /product/build.prop \
        /default.prop \
        /system/default.prop \
        /vendor/default.prop; do
        [ -f "$f" ] || continue
        awk -F= '
            /^[[:space:]]*#/ {next}
            /^[[:space:]]*$/ {next}
            NF>=1 {
                k=$1
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
                if (k != "") print k
            }
        ' "$f" 2>/dev/null >> "$tmp"
    done

    grep -E "$PROP_REGEX" "$tmp" 2>/dev/null | sort -u > "$out" 2>/dev/null || : > "$out"
    rm -f "$tmp" 2>/dev/null || true
}

extract_from_binaries_strings() {
    local out="$1" list_tmp py_tmp
    : > "$out"

    list_tmp="$(mktemp)" || return 0
    py_tmp="$(mktemp)" || {
        rm -f "$list_tmp" 2>/dev/null || true
        return 0
    }

    {
        for d in \
            /system/bin /system/xbin /vendor/bin \
            /system/lib /system/lib64 /vendor/lib /vendor/lib64 \
            /odm/lib /odm/lib64 /product/lib /product/lib64; do
            [ -d "$d" ] || continue
            find "$d" -type f 2>/dev/null
        done
    } | head -n "$MAX_BINARY_FILES" > "$list_tmp"

    if [ ! -s "$list_tmp" ]; then
        rm -f "$list_tmp" "$py_tmp" 2>/dev/null || true
        return 0
    fi

    if command -v strings >/dev/null 2>&1; then
        while IFS= read -r file; do
            strings "$file" 2>/dev/null | grep -Eo "$PROP_REGEX" >> "$out" 2>/dev/null || true
        done < "$list_tmp"
    elif command -v python3 >/dev/null 2>&1; then
        cat > "$py_tmp" <<'PYEOF'
import re,sys
rx = re.compile(rb'((?:ro|persist|sys|vendor|debug|dalvik|init\.svc)\.[A-Za-z0-9._-]+)')
for line in sys.stdin:
    p=line.strip()
    if not p:
        continue
    try:
        with open(p,'rb') as f:
            b=f.read()
    except Exception:
        continue
    for m in rx.finditer(b):
        try:
            print(m.group(1).decode('utf-8','ignore'))
        except Exception:
            pass
PYEOF
        python3 "$py_tmp" < "$list_tmp" >> "$out" 2>/dev/null || true
    else
        err "strings/python3 unavailable; skipping binary scan"
    fi

    sort -u "$out" -o "$out" 2>/dev/null || true
    rm -f "$list_tmp" "$py_tmp" 2>/dev/null || true
}

run_static() {
    local ts
    ts="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo unknown)"

    ensure_out_dir || return 1

    local f_ctx="$OUT_DIR/property_contexts_${ts}.txt"
    local f_init="$OUT_DIR/init_rc_props_${ts}.txt"
    local f_prop="$OUT_DIR/prop_files_${ts}.txt"
    local f_bin="$OUT_DIR/binaries_strings_${ts}.txt"
    local f_all="$OUT_DIR/all_static_props_${ts}.txt"

    log "[RUN] static collection"
    extract_from_property_contexts "$f_ctx"
    extract_from_init_rc "$f_init"
    extract_from_prop_files "$f_prop"

    if [ "$WITH_BINARIES" -eq 1 ]; then
        log "[RUN] binary strings scan (max files: $MAX_BINARY_FILES)"
        extract_from_binaries_strings "$f_bin"
    else
        : > "$f_bin"
    fi

    cat "$f_ctx" "$f_init" "$f_prop" "$f_bin" 2>/dev/null | grep -E "$PROP_REGEX" | sort -u > "$f_all" 2>/dev/null || : > "$f_all"

    log "[OK ] property_contexts: $f_ctx"
    log "[OK ] init_rc_props:    $f_init"
    log "[OK ] prop_files:       $f_prop"
    [ "$WITH_BINARIES" -eq 1 ] && log "[OK ] binaries_strings: $f_bin"
    [ "$WITH_BINARIES" -eq 1 ] && log "[INFO] binary keys:   $(wc -l < "$f_bin" 2>/dev/null || echo 0)"
    log "[OK ] merged static:    $f_all"
    log "[INFO] total keys: $(wc -l < "$f_all" 2>/dev/null || echo 0)"
}

run_snapshot() {
    local out_file="${1:-}"
    [ -n "$out_file" ] || {
        err "snapshot mode requires output file"
        usage
        return 1
    }

    getprop 2>/dev/null | sed -n 's/^\[\([^]]*\)\]: \[\(.*\)\]$/\1=\2/p' | sort > "$out_file"
    log "[OK ] snapshot saved: $out_file"
    log "[INFO] rows: $(wc -l < "$out_file" 2>/dev/null || echo 0)"
}

run_diff() {
    local before="${1:-}" after="${2:-}"
    [ -f "$before" ] || { err "before snapshot not found: $before"; return 1; }
    [ -f "$after" ] || { err "after snapshot not found: $after"; return 1; }

    local bkeys akeys
    bkeys="$(mktemp)" || return 1
    akeys="$(mktemp)" || { rm -f "$bkeys"; return 1; }
    trap 'rm -f "$bkeys" "$akeys"' EXIT INT TERM

    cut -d= -f1 "$before" | sort -u > "$bkeys"
    cut -d= -f1 "$after" | sort -u > "$akeys"

    log "=== added keys ==="
    comm -13 "$bkeys" "$akeys" || true

    log "=== removed keys ==="
    comm -23 "$bkeys" "$akeys" || true

    log "=== changed values ==="
    awk -F= 'NR==FNR{a[$1]=$0; next} {if(($1 in a) && a[$1]!=$0) print $1}' "$before" "$after" | sort -u

    rm -f "$bkeys" "$akeys"
    trap - EXIT INT TERM
}

case "$MODE" in
    static)
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --with-binaries) WITH_BINARIES=1 ;;
                --out-dir)
                    shift
                    OUT_DIR="${1:-$OUT_DIR}"
                    ;;
                *) err "Unknown static option: $1"; usage; exit 1 ;;
            esac
            shift
        done
        run_static
        ;;
    snapshot)
        run_snapshot "${1:-}"
        ;;
    diff)
        run_diff "${1:-}" "${2:-}"
        ;;
    help|-h|--help|'')
        usage
        ;;
    *)
        err "Unknown mode: $MODE"
        usage
        exit 1
        ;;
esac
