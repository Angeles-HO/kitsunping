#!/system/bin/sh

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

grep -Fq 'if wait "$native_child"; then' "$ROOT_DIR/installer/service.sh"

cat > "$TMP_DIR/supervisor.sh" <<'EOF'
#!/bin/sh
set -eu

"$1" &
native_child=$!
if wait "$native_child"; then
    native_rc=0
else
    native_rc=$?
fi
printf '%s\n' "[SYS][SERVICE][WARN] Native snapshot sidecar exited rc=$native_rc; restarting in 5s"
printf '%s\n' 'supervisor-recovery-reached'
EOF
chmod +x "$TMP_DIR/supervisor.sh"

cat > "$TMP_DIR/failing-sidecar.sh" <<'EOF'
#!/bin/sh
exit 23
EOF
chmod +x "$TMP_DIR/failing-sidecar.sh"

output=$("$TMP_DIR/supervisor.sh" "$TMP_DIR/failing-sidecar.sh")
expected='[SYS][SERVICE][WARN] Native snapshot sidecar exited rc=23; restarting in 5s
supervisor-recovery-reached'
[ "$output" = "$expected" ]

printf '%s\n' 'ok'