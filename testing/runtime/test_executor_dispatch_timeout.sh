#!/bin/sh

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) : ;;
    *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac

TEST_DIR=${SCRIPT_PATH%/*}
ROOT_DIR=${TEST_DIR%/*}
REPO_DIR=${ROOT_DIR%/*}

# shellcheck disable=SC1090
. "$ROOT_DIR/lib/test_helpers.sh"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

mkdir -p "$TMP_DIR/bin"
EXECUTOR_SH="$TMP_DIR/executor.sh"
POLICY_LOG="$TMP_DIR/policy.log"
LOG_DIR="$TMP_DIR"

cat > "$EXECUTOR_SH" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$EXECUTOR_SH"

cat > "$TMP_DIR/bin/timeout" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" > "$TIMEOUT_CAPTURE"
shift
exec "$@"
EOF
chmod 0755 "$TMP_DIR/bin/timeout"

PATH="$TMP_DIR/bin:$PATH"
export PATH
TIMEOUT_CAPTURE="$TMP_DIR/timeout.value"
export TIMEOUT_CAPTURE

log_error() { :; }

# shellcheck disable=SC1090
. "$REPO_DIR/addon/functions/daemon_events.sh"

daemon_dispatch_executor_event "request_profile" "1" "to=speed"
wait

timeout_value=$(cat "$TIMEOUT_CAPTURE" 2>/dev/null || echo "")
assert_eq "600" "$timeout_value" "executor dispatch timeout permits bounded calibration"

finish