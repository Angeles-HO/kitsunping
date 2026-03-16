#!/system/bin/sh

# Static/shared daemon helpers extracted from daemon.sh.
# Keep functions side-effect free and safe to source multiple times.

command -v json_escape >/dev/null 2>&1 || json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}

command -v atomic_write >/dev/null 2>&1 || atomic_write() {
    local target="$1" tmp target_dir

    [ -n "$target" ] || return 1
    target_dir="$(dirname "$target")"
    [ -n "$target_dir" ] || target_dir="."
    mkdir -p "$target_dir" 2>/dev/null || return 1

    tmp=$(mktemp "$target_dir/.atomic_write.XXXXXX" 2>/dev/null) || \
        tmp="$target_dir/.atomic_write.$$.$(date +%s).tmp"

    if ! cat - > "$tmp" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi

    if mv -f "$tmp" "$target" 2>/dev/null; then
        return 0
    fi

    # Fallback: overwrite in place when rename is blocked by FS constraints.
    if cat "$tmp" > "$target" 2>/dev/null; then
        rm -f "$tmp" 2>/dev/null || true
        return 0
    fi

    rm -f "$tmp" 2>/dev/null || true
    return 1
}

command -v now_epoch >/dev/null 2>&1 || now_epoch() {
    date +%s 2>/dev/null || awk 'BEGIN{print systime()}' 2>/dev/null || echo 0
}

command -v build_router_signature >/dev/null 2>&1 || build_router_signature() {
    local bssid="$1" band="$2" chan="$3" freq="$4" width="$5" caps="$6" caps_norm
    caps_norm=$(printf '%s' "$caps" | tr '|' ',')
    printf '%s|%s|%s|%s|%s|%s' "${bssid:-}" "${band:-}" "${chan:-}" "${freq:-}" "${width:-}" "${caps_norm:-}"
}

command -v router_dni_short >/dev/null 2>&1 || router_dni_short() {
    local sig="$1" cksum_out
    if command_exists cksum; then
        cksum_out=$(printf '%s' "$sig" | cksum 2>/dev/null | awk '{print $1; exit}')
        [ -n "$cksum_out" ] && { printf '%s' "$cksum_out"; return 0; }
    fi
    printf '%s' "$sig"
}

command -v should_emit_router_caps >/dev/null 2>&1 || should_emit_router_caps() {
    local vendor="$1" caps="$2"
    [ "$vendor" = "gl-inet" ] && printf '%s' "$caps" | grep -E "(vht|he|beamforming|mu-mimo)" >/dev/null 2>&1
}

command -v router_debug_trunc >/dev/null 2>&1 || router_debug_trunc() {
    printf '%s' "$1" | awk '{print substr($0, 1, 800)}'
}

command -v router_debug_log >/dev/null 2>&1 || router_debug_log() {
    [ "${ROUTER_DEBUG:-0}" -eq 1 ] || return 0
    log_debug "$*"
}

# HMAC-SHA256 using sha256sum + awk (no openssl required).
# Usage: kitsunping_hmac_sha256_hex <key_ascii> <message>
# key_ascii: the pairing token as an ASCII string (not hex-decoded).
# This matches openssl's -hmac behavior and is compatible with the router side.
command -v kitsunping_hmac_sha256_hex >/dev/null 2>&1 || kitsunping_hmac_sha256_hex() {
    local _k="$1" _m="$2" _tf _ih
    [ -n "$_k" ] || return 1

    # Fast path: openssl available (real HMAC-SHA256, key treated as ASCII string)
    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$_m" | openssl dgst -sha256 -hmac "$_k" 2>/dev/null | awk '{print $NF}'
        return
    fi

    # Fallback: HMAC-SHA256 via sha256sum + awk (BusyBox compatible).
    # bxor(a,b): bitwise XOR for byte values 0-255.
    # ord[c]: ASCII code of character c, built from sprintf("%c",i).
    _tf="${MODDIR:-/data/adb/modules/Kitsunping}/cache/.kp_hmac.$$.tmp"

    # Inner hash: sha256(ipad_key64 || msg)
    # ipad_key64 = each byte of key XOR 0x36, zero-padded to 64 bytes.
    {
        printf '%s\n' "$_k" | awk '
            function bxor(a,b,  r,i,ta,tb) {
                r=0; ta=a; tb=b
                for (i=128; i>=1; i=int(i/2)) {
                    ai=(ta>=i?1:0); bi=(tb>=i?1:0)
                    if (ai!=bi) r+=i
                    if (ai) ta-=i
                    if (bi) tb-=i
                }
                return r
            }
            BEGIN { for (i=0; i<128; i++) ord[sprintf("%c",i)]=i }
            {
                n=length($0)
                for (j=1; j<=64; j++) {
                    b=(j<=n ? ord[substr($0,j,1)] : 0)
                    printf "%c", bxor(b, 54)
                }
                exit
            }'
        printf '%s' "$_m"
    } | sha256sum | awk '{print $1}' > "$_tf" 2>/dev/null || { rm -f "$_tf" 2>/dev/null; return 1; }
    _ih=$(cat "$_tf" 2>/dev/null)
    rm -f "$_tf" 2>/dev/null
    [ -n "$_ih" ] || return 1

    # Outer hash: sha256(opad_key64 || binary(inner_hash))
    # opad_key64 = each byte of key XOR 0x5c, zero-padded to 64 bytes.
    {
        printf '%s\n' "$_k" | awk '
            function bxor(a,b,  r,i,ta,tb) {
                r=0; ta=a; tb=b
                for (i=128; i>=1; i=int(i/2)) {
                    ai=(ta>=i?1:0); bi=(tb>=i?1:0)
                    if (ai!=bi) r+=i
                    if (ai) ta-=i
                    if (bi) tb-=i
                }
                return r
            }
            BEGIN { for (i=0; i<128; i++) ord[sprintf("%c",i)]=i }
            {
                n=length($0)
                for (j=1; j<=64; j++) {
                    b=(j<=n ? ord[substr($0,j,1)] : 0)
                    printf "%c", bxor(b, 92)
                }
                exit
            }'
        printf '%s' "$_ih" | awk '{
            n=length($0)/2
            for (i=1; i<=n; i++) {
                h=substr($0,(i-1)*2+1,2)
                c1=substr(h,1,1); c2=substr(h,2,1)
                v=(index("0123456789abcdef",c1)-1)*16+(index("0123456789abcdef",c2)-1)
                printf "%c", v
            }
        }'
    } | sha256sum | awk '{print $1}'
}
