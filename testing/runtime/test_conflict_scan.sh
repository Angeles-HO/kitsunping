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

MODDIR="$TMP_DIR/moddir"
MODULES_DIR="$TMP_DIR/modules"

mkdir -p "$MODDIR" "$MODULES_DIR/RiskyModule" "$MODULES_DIR/BenignModule"
cat > "$MODULES_DIR/RiskyModule/service.sh" <<'EOF'
#!/system/bin/sh
sysctl -w net.ipv4.tcp_ecn=1
iptables -t mangle -A OUTPUT -j MARK --set-mark 1
EOF
cat > "$MODULES_DIR/BenignModule/service.sh" <<'EOF'
#!/system/bin/sh
echo ok
EOF

scan_output="$(MODDIR="$MODDIR" KITSUNPING_MODULES_DIR="$MODULES_DIR" sh "$REPO_DIR/tools/detect_module_conflicts.sh")"

assert_contains "highest_risk=high" "$scan_output" "scanner reports high-risk overlap"
assert_file_contains "$MODDIR/cache/conflicts.state" "highest_risk=high" "state file persists highest risk"
assert_file_contains "$MODDIR/logs/conflicts_report.log" "module=RiskyModule risk=high" "report includes risky module"
assert_file_contains "$MODDIR/logs/conflicts_report.log" "summary modules_scanned=2" "report includes module summary"

finish