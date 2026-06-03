#!/bin/sh

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) : ;;
    *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac

TEST_DIR=${SCRIPT_PATH%/*}
FAIL=0

for suite_dir in "$TEST_DIR/runtime" "$TEST_DIR/network"; do
    [ -d "$suite_dir" ] || continue
    for test_script in "$suite_dir"/test_*.sh; do
        [ -f "$test_script" ] || continue
        test_name=${test_script##*/}
        echo "[RUN] $test_name"
        if sh "$test_script"; then
            echo "[OK ] $test_name"
        else
            echo "[FAIL] $test_name" >&2
            FAIL=1
        fi
        echo ""
    done
done

if [ "$FAIL" -ne 0 ]; then
    echo "Runtime fixture tests completed with failures." >&2
    exit 1
fi

echo "Runtime fixture tests completed successfully."
exit 0