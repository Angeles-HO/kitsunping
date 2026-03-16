#!/bin/sh
# POSIX compatibility audit for shell scripts in Kitsunping.
# - Parses each .sh with `sh -n`
# - Flags common bash-specific patterns
# - Writes a human-readable report under logs/

set -u

MODE="${1:-compat}"
case "$MODE" in
    strict|compat) : ;;
    -h|--help|help)
        echo "Usage: $0 [compat|strict]"
        echo "  compat (default): ignore 'local' keyword warnings common in Android sh environments"
        echo "  strict          : include all non-POSIX patterns, including 'local'"
        exit 0
        ;;
    *)
        echo "Invalid mode: $MODE" >&2
        echo "Usage: $0 [compat|strict]" >&2
        exit 2
        ;;
esac

SCRIPT_DIR=${0%/*}
case "$SCRIPT_DIR" in
    "") SCRIPT_DIR="." ;;
esac

# Repo root is one level above tools/
REPO_DIR=${SCRIPT_DIR%/*}
if [ ! -d "$REPO_DIR" ]; then
    REPO_DIR="."
fi

# Allow callers (e.g., tools/test_all_local.sh) to redirect reports.
# Default remains repo-level logs/ for backward compatibility.
REPORT_DIR="${KITSUNPING_POSIX_REPORT_DIR:-$REPO_DIR/logs}"
mkdir -p "$REPORT_DIR" 2>/dev/null || true

TS=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo "unknown_time")
REPORT_FILE="$REPORT_DIR/posix_compat_report_${MODE}_${TS}.txt"
LATEST_LINK="$REPORT_DIR/posix_compat_report_${MODE}_latest.txt"

TMP_RESULTS="$REPORT_DIR/.posix_compat_tmp_${TS}.tsv"
: > "$TMP_RESULTS"

# Print report header
{
    echo "Kitsunping POSIX Compatibility Report"
    echo "Generated: $(date 2>/dev/null || echo unknown_date)"
    echo "Repository: $REPO_DIR"
    echo "Mode: $MODE"
    echo ""
    echo "Checks"
    echo "- sh -n parse"
    echo "- common bashism pattern scan"
    echo ""
} > "$REPORT_FILE"

scan_bashisms() {
    f="$1"
    mode="$2"
    issues=""

    # Bash/Ksh specific or non-POSIX patterns (best effort static scan).
    grep -n '[[:space:]]\[\[' "$f" >/dev/null 2>&1 && issues="${issues} [[ ]] ;"
    if [ "$mode" = "strict" ]; then
        # Detect shell "function" keyword only outside single-quoted blocks (e.g., ignore awk program bodies).
        awk "
            BEGIN { sq=0; q=sprintf(\"%c\",39) }
            {
                out=\"\"
                for (i=1; i<=length(\$0); i++) {
                    c=substr(\$0,i,1)
                    if (c==q) { sq=1-sq; out=out \" \"; continue }
                    if (sq==0) out=out c; else out=out \" \"
                }
                if (out ~ /^[[:space:]]*function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
                    found=1
                    exit
                }
            }
            END { exit(found ? 0 : 1) }
        " "$f" >/dev/null 2>&1 && issues="${issues} function keyword ;"
    fi
    grep -n '[<>](' "$f" >/dev/null 2>&1 && issues="${issues} process substitution ;"
    grep -n '^[[:space:]]*source[[:space:]]' "$f" >/dev/null 2>&1 && issues="${issues} source builtin ;"
    # Detect arithmetic *command* style (( ... )) while ignoring POSIX $(( ... )) expansion.
    awk '
        {
            line=$0
            gsub(/\$\(\([^)]*\)\)/, "", line)
            if (line ~ /(^|[^$])\(\([[:space:]]*[^)][^)]*\)\)/) {
                found=1
                exit
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$f" >/dev/null 2>&1 && issues="${issues} (( )) arithmetic command ;"
    grep -n '\$[{][^}]*\[[^]]*\][}]' "$f" >/dev/null 2>&1 && issues="${issues} array-style expansion ;"

    # `local` is not POSIX but often accepted by ash/dash.
    if [ "$mode" = "strict" ]; then
        grep -n '^[[:space:]]*local[[:space:]]' "$f" >/dev/null 2>&1 && issues="${issues} local keyword (non-POSIX) ;"
    fi

    # Trim leading/trailing spaces/semicolons.
    issues=$(printf '%s' "$issues" | sed 's/^ *//; s/ *$//; s/; *$//')
    printf '%s' "$issues"
}

count_total=0
count_pass=0
count_warn=0
count_fail=0

# Keep ordering stable for easier diffs.
find "$REPO_DIR" -type f -name '*.sh' ! -path '*/.git/*' | sort | while IFS= read -r file; do
    case "$file" in
        "$REPO_DIR"/tools/check_posix_compat.sh|./tools/check_posix_compat.sh) continue ;;
    esac

    count_total=$((count_total + 1))
    rel="$file"
    case "$file" in
        "$REPO_DIR"/*) rel=${file#"$REPO_DIR"/} ;;
    esac

    parse_err=""
    local_used="no"
    grep -n '^[[:space:]]*local[[:space:]]' "$file" >/dev/null 2>&1 && local_used="yes"

    if ! parse_err=$(sh -n "$file" 2>&1); then
        status="FAIL"
        count_fail=$((count_fail + 1))
        issues="sh -n error: $parse_err"
    else
        issues=$(scan_bashisms "$file" "$MODE")
        if [ -n "$issues" ]; then
            status="WARN"
            count_warn=$((count_warn + 1))
        else
            status="PASS"
            count_pass=$((count_pass + 1))
        fi
    fi

    printf '%s\t%s\t%s\t%s\n' "$status" "$rel" "$issues" "$local_used" >> "$TMP_RESULTS"
done

# Re-count from tmp because loop may run in subshell on some sh implementations.
count_total=$(wc -l < "$TMP_RESULTS" 2>/dev/null | tr -d ' ')
count_pass=$(awk -F '\t' '$1=="PASS" {n++} END{print n+0}' "$TMP_RESULTS")
count_warn=$(awk -F '\t' '$1=="WARN" {n++} END{print n+0}' "$TMP_RESULTS")
count_fail=$(awk -F '\t' '$1=="FAIL" {n++} END{print n+0}' "$TMP_RESULTS")
count_local=$(awk -F '\t' '$4=="yes" {n++} END{print n+0}' "$TMP_RESULTS")

{
    echo "Summary"
    echo "- Total scripts: $count_total"
    echo "- PASS: $count_pass"
    echo "- WARN: $count_warn"
    echo "- FAIL: $count_fail"
    echo "- Files using 'local': $count_local"
    echo ""

    echo "Failures (sh -n)"
    awk -F '\t' '$1=="FAIL" {print "- " $2 " :: " $3}' "$TMP_RESULTS"
    echo ""

    echo "Warnings (possible bashisms/non-POSIX patterns)"
    awk -F '\t' '$1=="WARN" {print "- " $2 " :: " $3}' "$TMP_RESULTS"
    echo ""

    echo "Passes"
    awk -F '\t' '$1=="PASS" {print "- " $2}' "$TMP_RESULTS"
    echo ""

    echo "Local Keyword Usage (non-POSIX advisory)"
    awk -F '\t' '$4=="yes" {print "- " $2}' "$TMP_RESULTS"
} >> "$REPORT_FILE"

cp "$REPORT_FILE" "$LATEST_LINK" 2>/dev/null || true
# Keep a generic pointer for convenience (last run regardless of mode).
cp "$REPORT_FILE" "$REPORT_DIR/posix_compat_report_latest.txt" 2>/dev/null || true
rm -f "$TMP_RESULTS"

echo "Report written: $REPORT_FILE"
echo "Latest report: $LATEST_LINK"

# Non-zero exit if hard parse failures exist.
[ "$count_fail" -eq 0 ] || exit 1
exit 0
