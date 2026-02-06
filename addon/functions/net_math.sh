#!/system/bin/sh
# Network math: scoring and caches. Requires MODDIR and BC_BIN (detected by caller).

RSRP_CACHE_FILE="${MODDIR}/cache/rsrp_cache.db"
SINR_CACHE_FILE="${MODDIR}/cache/sinr_cache.db"
COMPOSITE_EMA_FILE="${MODDIR}/cache/composite.ema"
EMA_ALPHA=${EMA_ALPHA:-0.35}

to_int() {
    local val="$1"
    # remove decimal part if any
    val="${val%%.*}"
    # also if another spain language uses comma
    val="${val%%,*}"
    # remove leading plus sign if any
    val="${val#+}"

    # validate int
    if printf '%s\n' "$val" | grep -Eq '^-?[0-9]+$'; then
        printf '%s' "$val"
    else
        printf '0'
    fi
}

# lookup in cache file: key:value
cache_lookup() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    awk -F: -v k="$key" '$1==k {print $2; exit}' "$file"
}

# atomic store: replace existing key and write atomically
cache_store() {
    local file="$1" key="$2" val="$3" tmp
    tmp=$(mktemp "${file}.XXXXXX") || tmp="${file}.$$"
    if [ -f "$file" ]; then
        awk -F: -v k="$key" '$1!=k {print $0}' "$file" > "$tmp" 2>/dev/null || true
    fi
    printf '%s:%s\n' "$key" "$val" >> "$tmp" 2>/dev/null || true
    mv "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

score_rsrp_cached() {
    local rsrp_raw="$1" rsrp key score
    rsrp=$(to_int "$rsrp_raw")
    key="$rsrp"
    score=$(cache_lookup "$RSRP_CACHE_FILE" "$key")
    [ -n "$score" ] && { printf '%s' "$score"; return 0; }

    if [ -n "${BC_BIN:-}" ]; then
        score=$(echo "scale=4; 100 / (1 + e(-0.1 * ($rsrp + 105)))" | "${BC_BIN}" -l 2>/dev/null)
        score=$(echo "$score" | awk '{if($1<0) print 0; else if($1>100) print 100; else print $1}')
    else
        if [ "$rsrp" -ge -85 ]; then score=100
        elif [ "$rsrp" -ge -95 ]; then score=80
        elif [ "$rsrp" -ge -105 ]; then score=60
        elif [ "$rsrp" -ge -115 ]; then score=40
        else score=10
        fi
    fi

    cache_store "$RSRP_CACHE_FILE" "$key" "$score" >/dev/null 2>&1 || true
    printf '%s' "$score"
}

score_sinr_cached() {
    local sinr_raw="$1" sinr key score
    sinr=$(to_int "$sinr_raw")
    key="$sinr"
    score=$(cache_lookup "$SINR_CACHE_FILE" "$key")
    [ -n "$score" ] && { printf '%s' "$score"; return 0; }

    if [ -n "${BC_BIN:-}" ]; then
        score=$(echo "scale=4; 100 / (1 + e(-0.2 * ($sinr - 10)))" | "${BC_BIN}" -l 2>/dev/null)
        score=$(echo "$score" | awk '{if($1<0) print 0; else if($1>100) print 100; else print $1}')
    else
        if [ "$sinr" -ge 20 ]; then score=98
        elif [ "$sinr" -ge 15 ]; then score=88
        elif [ "$sinr" -ge 10 ]; then score=73
        elif [ "$sinr" -ge 5 ]; then score=50
        elif [ "$sinr" -ge 0 ]; then score=27
        elif [ "$sinr" -ge -5 ]; then score=12
        else score=2
        fi
    fi

    cache_store "$SINR_CACHE_FILE" "$key" "$score" >/dev/null 2>&1 || true
    printf '%s' "$score"
}

composite_ema() {
    local new="$1" ema_file="${2:-$COMPOSITE_EMA_FILE}" prev tmp
    prev=""
    if [ -f "$ema_file" ]; then
        prev=$(cat "$ema_file" 2>/dev/null || echo "")
        prev=$(printf '%s' "$prev" | awk '/^-?[0-9]+([.][0-9]+)?$/ {print; exit}')
    fi
    if [ -z "$prev" ]; then
        tmp="$new"
    else
        tmp=$(awk -v a="${EMA_ALPHA}" -v p="$prev" -v n="$new" 'BEGIN{printf "%.2f", a*n + (1-a)*p}')
    fi
    printf '%s' "$tmp" > "$ema_file" 2>/dev/null || true
    printf '%s' "$tmp"
}

# Decide profile based on composite score (returns profile name)
decide_profile() {
    local score="$1"
    if awk "BEGIN{exit !($score >= 80)}"; then
        echo "gaming"
    elif awk "BEGIN{exit !($score >= 50)}"; then
        echo "stable"
    else
        echo "speed"
    fi
}
