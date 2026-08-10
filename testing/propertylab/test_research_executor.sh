#!/bin/sh

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in /*) : ;; *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;; esac
TEST_DIR=${SCRIPT_PATH%/*}
ROOT_DIR=${TEST_DIR%/*}
REPO_DIR=${ROOT_DIR%/*}

# shellcheck disable=SC1090
. "$ROOT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM
MOCK_BIN="$TMP_ROOT/bin"
STATE_DIR="$TMP_ROOT/state"
mkdir -p "$MOCK_BIN" "$STATE_DIR"

cat > "$MOCK_BIN/resetprop" <<'EOF'
#!/bin/sh
state="${RESEARCH_TEST_PROP_STATE:?}"
calls="${RESEARCH_TEST_CALLS:?}"
case "${1:-}" in
    -n)
        printf '%s\t%s\n' "$2" "$3" >> "$calls"
        printf '%s' "$3" > "$state/$2"
        ;;
    --delete)
        printf '%s\t%s\n' "$2" '<delete>' >> "$calls"
        rm -f "$state/$2"
        ;;
    *)
        [ -f "$state/$1" ] || exit 1
        cat "$state/$1"
        ;;
esac
EOF
chmod 0755 "$MOCK_BIN/resetprop"
printf '%s' 'original-alpha' > "$STATE_DIR/alpha.prop"

MANIFEST="$TMP_ROOT/subset.json"
cat > "$MANIFEST" <<'EOF'
{
  "schema": 1,
  "mode": "research_temporary",
  "release_eligible": false,
  "experiment_id": "plr-subset-fixture-v1",
  "operations": [
    {
      "operation": "resetprop",
      "phase": "runtime_profile",
      "key": "alpha.prop",
      "value": "candidate-alpha"
    },
    {
      "operation": "resetprop",
      "phase": "runtime_profile",
      "key": "beta.prop",
      "value": "candidate-beta"
    }
  ]
}
EOF
sha256sum "$MANIFEST" | awk '{print $1 "  subset.json"}' > "$MANIFEST.sha256"

EXECUTOR="$REPO_DIR/PropertyLab/research/research_executor.sh"
RUN_DIR="$TMP_ROOT/run"
ENV_PREFIX="RESEARCH_EXECUTOR_ALLOW_NON_ROOT=1 RESEARCH_RESETPROP_BIN=$MOCK_BIN/resetprop RESEARCH_TEST_PROP_STATE=$STATE_DIR RESEARCH_TEST_CALLS=$TMP_ROOT/calls.tsv"

printf '%064d  subset.json\n' 0 > "$TMP_ROOT/invalid.sha256"
if env $ENV_PREFIX sh "$EXECUTOR" apply --manifest "$MANIFEST" --sha256-file "$TMP_ROOT/invalid.sha256" --run-dir "$TMP_ROOT/invalid-run" >/dev/null 2>&1; then
  fail 'executor rejects an invalid manifest hash'
else
  pass 'executor rejects an invalid manifest hash'
fi
assert_eq 'original-alpha' "$(cat "$STATE_DIR/alpha.prop")" 'invalid hash does not modify captured property'

env $ENV_PREFIX sh "$EXECUTOR" apply --manifest "$MANIFEST" --sha256-file "$MANIFEST.sha256" --run-dir "$RUN_DIR" > "$TMP_ROOT/apply.out"
assert_file_contains "$TMP_ROOT/apply.out" 'applied 2 properties' 'executor applies arbitrary subset manifest'
assert_eq 'present original-alpha' "$(awk -F '\t' '$1 == "alpha.prop" {print $2 " " $3}' "$RUN_DIR/before.tsv")" 'executor captures existing property'
assert_eq 'absent ' "$(awk -F '\t' '$1 == "beta.prop" {print $2 " " $3}' "$RUN_DIR/before.tsv")" 'executor captures absent property'
assert_eq 'candidate-alpha' "$(cat "$STATE_DIR/alpha.prop")" 'executor applies first property'
assert_eq 'candidate-beta' "$(cat "$STATE_DIR/beta.prop")" 'executor applies second property'
assert_eq 'alpha.prop candidate-alpha' "$(awk -F '\t' 'NR == 1 {print $1 " " $2}' "$TMP_ROOT/calls.tsv")" 'executor preserves declared first operation'
assert_eq 'beta.prop candidate-beta' "$(awk -F '\t' 'NR == 2 {print $1 " " $2}' "$TMP_ROOT/calls.tsv")" 'executor preserves declared second operation'

env $ENV_PREFIX sh "$EXECUTOR" result --run-dir "$RUN_DIR" --result reproduce --observations 'manual wifi loss reproduced'
assert_file_contains "$RUN_DIR/report.json" '"manual_result": "reproduce"' 'report records manual result'
assert_file_contains "$RUN_DIR/report.json" '"property_count": 2' 'report records property count'
assert_file_contains "$RUN_DIR/report.json" '"value":"candidate-alpha"' 'report includes exact applied value'

env $ENV_PREFIX sh "$EXECUTOR" restore --run-dir "$RUN_DIR" > "$TMP_ROOT/restore.out"
assert_file_contains "$TMP_ROOT/restore.out" 'restored pre-apply property state' 'executor reports restore success'
assert_eq 'original-alpha' "$(cat "$STATE_DIR/alpha.prop")" 'restore returns existing property to captured value'
assert_file_not_exists "$STATE_DIR/beta.prop" 'restore deletes property that was absent before apply'
assert_file_contains "$RUN_DIR/report.json" '"status": "restored"' 'report records restore completion'

finish