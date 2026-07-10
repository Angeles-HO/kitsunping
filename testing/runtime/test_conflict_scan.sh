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

# Medium-only overlap should surface highest_risk=medium.
rm -rf "$MODULES_DIR"
mkdir -p "$MODULES_DIR/MediumModule"
cat > "$MODULES_DIR/MediumModule/service.sh" <<'EOF'
#!/system/bin/sh
cmd wifi status
EOF

scan_output="$(MODDIR="$MODDIR" KITSUNPING_MODULES_DIR="$MODULES_DIR" sh "$REPO_DIR/tools/detect_module_conflicts.sh")"

assert_contains "highest_risk=medium" "$scan_output" "scanner reports medium overlap when only medium patterns exist"
assert_file_contains "$MODDIR/cache/conflicts.state" "highest_risk=medium" "state file persists medium risk"
assert_file_contains "$MODDIR/logs/conflicts_report.log" "module=MediumModule risk=medium" "report includes medium module"

# Disabled/removed modules must be ignored even when content is risky.
rm -rf "$MODULES_DIR"
mkdir -p "$MODULES_DIR/DisabledRisky" "$MODULES_DIR/RemovedRisky" "$MODULES_DIR/ActiveBenign"
cat > "$MODULES_DIR/DisabledRisky/service.sh" <<'EOF'
#!/system/bin/sh
iptables -t mangle -A OUTPUT -j MARK --set-mark 1
EOF
touch "$MODULES_DIR/DisabledRisky/disable"

cat > "$MODULES_DIR/RemovedRisky/service.sh" <<'EOF'
#!/system/bin/sh
ip rule add from all lookup main
EOF
touch "$MODULES_DIR/RemovedRisky/remove"

cat > "$MODULES_DIR/ActiveBenign/service.sh" <<'EOF'
#!/system/bin/sh
echo healthy
EOF

scan_output="$(MODDIR="$MODDIR" KITSUNPING_MODULES_DIR="$MODULES_DIR" sh "$REPO_DIR/tools/detect_module_conflicts.sh")"

assert_contains "highest_risk=low" "$scan_output" "scanner ignores disabled/removed risky modules"
assert_file_contains "$MODDIR/cache/conflicts.state" "modules_scanned=1" "scanner counts only active modules"
assert_file_contains "$MODDIR/logs/conflicts_report.log" "module=ActiveBenign risk=low" "report includes active benign module"

finish