#!/bin/sh

set -u

SCRIPT_PATH=$0
case "$SCRIPT_PATH" in /*) : ;; *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;; esac
TEST_DIR=${SCRIPT_PATH%/*}
ROOT_DIR=${TEST_DIR%/*}
REPO_DIR=${ROOT_DIR%/*}
. "$ROOT_DIR/lib/test_helpers.sh"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM
PROC_ROOT="$TMP_ROOT/proc/sys"
mkdir -p "$PROC_ROOT/net/core" "$PROC_ROOT/net/ipv4"
printf '0' > "$PROC_ROOT/net/core/bpf_jit_enable"
printf '1' > "$PROC_ROOT/net/ipv4/tcp_ecn"

MANIFEST="$TMP_ROOT/subset.json"
cat > "$MANIFEST" <<'EOF'
{
  "schema": 1,
  "mode": "research_temporary",
  "release_eligible": false,
  "experiment_id": "plps-subset-fixture-v1",
  "mechanism": "apply_param_set_proc_sys_only",
  "operations": [
    {
      "operation": "proc_sys_write",
      "path": "/proc/sys/net/core/bpf_jit_enable",
      "value": "1",
      "description": "fixture core write"
    },
    {
      "operation": "proc_sys_write",
      "path": "/proc/sys/net/ipv4/tcp_ecn",
      "value": "0",
      "description": "fixture TCP write"
    }
  ]
}
EOF
sha256sum "$MANIFEST" | awk '{print $1 "  subset.json"}' > "$MANIFEST.sha256"
EXECUTOR="$REPO_DIR/PropertyLabProcSys/bin/proc_sys_executor.sh"
RUN_DIR="$TMP_ROOT/run"
ENV_PREFIX="RESEARCH_EXECUTOR_ALLOW_NON_ROOT=1 RESEARCH_PROC_ROOT=$PROC_ROOT RESEARCH_PROC_WRITE_METHOD=direct"

printf '%064d  subset.json\n' 0 > "$TMP_ROOT/invalid.sha256"
if env $ENV_PREFIX sh "$EXECUTOR" apply --manifest "$MANIFEST" --sha256-file "$TMP_ROOT/invalid.sha256" --run-dir "$TMP_ROOT/invalid-run" >/dev/null 2>&1; then
    fail 'executor rejects invalid manifest hash'
else
    pass 'executor rejects invalid manifest hash'
fi
assert_eq '0' "$(cat "$PROC_ROOT/net/core/bpf_jit_enable")" 'invalid hash leaves proc node unchanged'

env $ENV_PREFIX sh "$EXECUTOR" apply --manifest "$MANIFEST" --sha256-file "$MANIFEST.sha256" --run-dir "$RUN_DIR" > "$TMP_ROOT/apply.out"
assert_file_contains "$TMP_ROOT/apply.out" 'applied 2 nodes' 'executor applies declared nodes'
assert_eq '0' "$(awk -F '\t' '$1 == "/proc/sys/net/core/bpf_jit_enable" {print $2}' "$RUN_DIR/before.tsv")" 'executor captures first node'
assert_eq '1' "$(cat "$PROC_ROOT/net/core/bpf_jit_enable")" 'executor writes first node'
assert_eq '0' "$(cat "$PROC_ROOT/net/ipv4/tcp_ecn")" 'executor writes second node'
assert_file_contains "$RUN_DIR/report.json" '"node_count": 2' 'report records node count'
assert_file_contains "$RUN_DIR/report.json" '"path":"/proc/sys/net/core/bpf_jit_enable"' 'report records logical proc path'

env $ENV_PREFIX sh "$EXECUTOR" result --run-dir "$RUN_DIR" --result no_reproduce --observations 'manual observation recorded'
assert_file_contains "$RUN_DIR/report.json" '"manual_result": "no_reproduce"' 'report records manual result'

env $ENV_PREFIX sh "$EXECUTOR" restore --run-dir "$RUN_DIR" > "$TMP_ROOT/restore.out"
assert_file_contains "$TMP_ROOT/restore.out" 'restored pre-apply proc state' 'executor reports restore completion'
assert_eq '0' "$(cat "$PROC_ROOT/net/core/bpf_jit_enable")" 'restore returns first node'
assert_eq '1' "$(cat "$PROC_ROOT/net/ipv4/tcp_ecn")" 'restore returns second node'
assert_file_contains "$RUN_DIR/report.json" '"status": "restored"' 'report records restore completion'

finish
