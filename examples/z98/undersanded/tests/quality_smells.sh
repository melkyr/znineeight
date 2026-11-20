#!/bin/sh
# quality_smells.sh — mechanical owner/registry checks for M9 Task 8.
#
# Shell only (no Python). Checks:
#   * toolOwned/toolKind/toolKindFor defined only in items.zig
#   * isKeystone/isKeystonePart defined only in items.zig
#   * isRareRefine/isDeepMaterial defined only in economy.zig
#   * stripCR/trimSpaces/findEq defined only in text_scan.zig
#   * fn join( defined only in paths.zig; no joinPath/joinOutPath copies
#   * NAV_/SCREEN_/MSG_/OUT_/TOOL_/UNLOCK_/NO_FIGHT ids only in def.zig
#   * LOC: any file fails >2000; files not grandfathered/generated fail >600,
#     grandfathered files warn >600. New files are derived by exclusion so a
#     future module is caught without editing a hardcoded new-file list.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GENERATED="fallback_rows.zig"
GRANDFATHERED="art_test.zig expedition_test.zig fight.zig fight_test.zig nav.zig persist_test.zig render_art.zig render_term.zig save_scan.zig save_ux_test.zig undtool.zig"

PASSES=0
FAILS=0
WARNS=0

pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
warn_case() { echo "WARN - $1"; WARNS=$((WARNS + 1)); }

check_owner() {
    pattern="$1"
    owner="$2"
    label="$3"
    bad="$(grep -rnE "$pattern" "$UNDDIR"/*.zig "$UNDDIR"/tests/*.zig 2>/dev/null \
        | grep -v "/$owner:")"
    if [ -n "$bad" ]; then
        fail_case "$label"
        printf '%s\n' "$bad" | while IFS= read -r line; do echo "       $line"; done
    else
        pass_case "$label"
    fi
}

check_owner '(^|[^A-Za-z0-9_])fn[[:space:]]+(toolOwned|toolKind|toolKindFor)[[:space:]]*\(' \
    "items.zig" "toolOwned/toolKind/toolKindFor owner (items.zig)"
check_owner '(^|[^A-Za-z0-9_])fn[[:space:]]+(isKeystone|isKeystonePart)[[:space:]]*\(' \
    "items.zig" "isKeystone/isKeystonePart owner (items.zig)"
check_owner '(^|[^A-Za-z0-9_])fn[[:space:]]+(isRareRefine|isDeepMaterial)[[:space:]]*\(' \
    "economy.zig" "isRareRefine/isDeepMaterial owner (economy.zig)"
check_owner '(^|[^A-Za-z0-9_])fn[[:space:]]+(stripCR|trimSpaces|findEq)[[:space:]]*\(' \
    "text_scan.zig" "stripCR/trimSpaces/findEq owner (text_scan.zig)"
check_owner '(^|[^A-Za-z0-9_])fn[[:space:]]+join[[:space:]]*\(' \
    "paths.zig" "join owner (paths.zig)"
check_owner '(^|[^A-Za-z0-9_])fn[[:space:]]+(joinPath|joinOutPath)[[:space:]]*\(' \
    "paths.zig" "joinPath/joinOutPath owner (paths.zig)"
check_owner '(^|[[:space:]])(pub[[:space:]]+)?const[[:space:]]+(NAV_|SCREEN_|MSG_|OUT_|TOOL_|UNLOCK_|NO_FIGHT)' \
    "def.zig" "id registry owner (def.zig)"

is_new() {
    [ "$1" = "$GENERATED" ] && return 1
    for n in $GRANDFATHERED; do
        [ "$1" = "$n" ] && return 1
    done
    return 0
}

for f in "$UNDDIR"/*.zig "$UNDDIR"/tests/*.zig; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    lines="$(wc -l <"$f")"
    if [ "$lines" -gt 2000 ]; then
        fail_case "$base exceeds 2000 lines ($lines)"
    elif is_new "$base" && [ "$lines" -gt 600 ]; then
        fail_case "new $base exceeds 600 lines ($lines)"
    elif [ "$lines" -gt 600 ]; then
        warn_case "$base exceeds 600 lines ($lines)"
    fi
done
pass_case "line-count limits checked"

echo
echo "== quality_smells summary: $PASSES passed, $FAILS failed, $WARNS warnings =="
if [ "$FAILS" -ne 0 ]; then
    echo "QUALITY_SMELLS FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "QUALITY_SMELLS PASS $PASSES passed / $FAILS failed"
exit 0
