#!/bin/sh
# Local release gate for metadata + changelog consistency.

set -u

SCRIPT_PATH="$0"
case "$SCRIPT_PATH" in
    /*) : ;;
    *) SCRIPT_PATH="$PWD/$SCRIPT_PATH" ;;
esac

TOOLS_DIR=${SCRIPT_PATH%/*}
REPO_DIR=${TOOLS_DIR%/*}

RUN_TESTS=1
if [ "${1:-}" = "--skip-tests" ]; then
    RUN_TESTS=0
fi

fail=0

log() {
    printf '%s\n' "$*"
}

ok() {
    printf '[OK ] %s\n' "$*"
}

ko() {
    printf '[FAIL] %s\n' "$*" >&2
    fail=1
}

require_file() {
    file_path="$1"
    if [ -f "$file_path" ]; then
        ok "file exists: $file_path"
    else
        ko "missing required file: $file_path"
    fi
}

prop_get() {
    key="$1"
    file_path="$2"
    sed -n "s/^${key}=//p" "$file_path" | head -n1 | tr -d '\r\n'
}

json_get() {
    key="$1"
    file_path="$2"
    sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$file_path" | head -n1 | tr -d '\r\n'
}

cd "$REPO_DIR" || {
    ko "cannot enter repo: $REPO_DIR"
    exit 1
}

log "[RUN] release gate checks"

require_file "module.prop"
require_file "update.json"
require_file "CHANGELOG.md"
require_file "tools/test_all_local.sh"

MODULE_VERSION="$(prop_get version module.prop)"
MODULE_VERSION_CODE="$(prop_get versionCode module.prop)"
JSON_VERSION="$(json_get version update.json)"
JSON_VERSION_CODE="$(json_get versionCode update.json)"
JSON_RELEASE_TAG="$(json_get releaseTag update.json)"
JSON_ZIP_URL="$(json_get zipUrl update.json)"
EXPECTED_ZIP_NAME="Kitsunping.zip"

[ -n "$JSON_RELEASE_TAG" ] || JSON_RELEASE_TAG="v${MODULE_VERSION}"

if [ -n "$MODULE_VERSION" ]; then
    ok "module.prop version: $MODULE_VERSION"
else
    ko "module.prop version is empty"
fi

if [ -n "$MODULE_VERSION_CODE" ]; then
    ok "module.prop versionCode: $MODULE_VERSION_CODE"
else
    ko "module.prop versionCode is empty"
fi

if [ "$MODULE_VERSION" = "$JSON_VERSION" ] && [ -n "$JSON_VERSION" ]; then
    ok "module.prop version matches update.json"
else
    ko "version mismatch (module.prop=$MODULE_VERSION, update.json=$JSON_VERSION)"
fi

if [ "$MODULE_VERSION_CODE" = "$JSON_VERSION_CODE" ] && [ -n "$JSON_VERSION_CODE" ]; then
    ok "module.prop versionCode matches update.json"
else
    ko "versionCode mismatch (module.prop=$MODULE_VERSION_CODE, update.json=$JSON_VERSION_CODE)"
fi

case "$JSON_ZIP_URL" in
    *"/${JSON_RELEASE_TAG}/"*) ok "zipUrl includes release tag ${JSON_RELEASE_TAG}" ;;
    *) ko "zipUrl does not include ${JSON_RELEASE_TAG}: $JSON_ZIP_URL" ;;
esac

case "$JSON_ZIP_URL" in
    *"/${EXPECTED_ZIP_NAME}") ok "zipUrl uses required asset name: ${EXPECTED_ZIP_NAME}" ;;
    *) ko "zipUrl must end with /${EXPECTED_ZIP_NAME}: $JSON_ZIP_URL" ;;
esac

if grep -Fq "## ${MODULE_VERSION} -" CHANGELOG.md; then
    ok "CHANGELOG contains section for ${MODULE_VERSION}"
else
    ko "CHANGELOG missing section header: ## ${MODULE_VERSION} - ..."
fi

if [ "$RUN_TESTS" -eq 1 ]; then
    log "[RUN] local verification suite"
    if sh ./tools/test_all_local.sh; then
        ok "tools/test_all_local.sh passed"
    else
        ko "tools/test_all_local.sh failed"
    fi
else
    log "[SKIP] tests skipped (--skip-tests)"
fi

if [ "$fail" -ne 0 ]; then
    log "Release gate failed."
    exit 1
fi

log "Release gate passed."
exit 0
