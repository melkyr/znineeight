#!/bin/sh
# tier_m2_fight.sh — UNDERSANDED M2 fight-core acceptance tier (spec §34/§41).
#
# FAST, native only (no Wine/DDraw evidence in this gate):
#   * build+run the four native drivers with `-fsafe -W -osl` +
#     build_target.sh linux: core_test, behavior_test, fight_test, ui_test
#   * the scripted full-fight goldens in fight_test (fixed seed + fixed action
#     stream -> exact outcome + exact full-log bytes): Subdue, Kill, Overkill,
#     and the rare modal path; plus the 20-fight evidence table, which must
#     cover Subdue/Kill/Overkill and at least one modal fight
#   * purity: game.zig / fight.zig / behavior.zig import no std_gfx or std_io
#   * z9edit tier_edit.sh green with unchanged lexer goldens (md5 pinned)
#   * no committed .py tooling under examples/z98/undersanded/
#
# Env: ZIG  compiler (default /tmp/zig1-m1/zig1_5_clean)
#      OUT  scratch dir (default /tmp/undersanded_m2_tier)
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# failure and prints `TIER_M2 PASS <n> passed / <m> failed`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/zig1-m1/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m2_tier}"
TESTS="examples/z98/undersanded/tests"
EXPECTED_LEXER_MD5="dcc81009e9a36c86e4d90e104c439871"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/zig1-m1"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 1: four native drivers (-fsafe -W clean, build_target.sh linux, PASS)
# ---------------------------------------------------------------------------
echo "== FAST: four native drivers =="
for t in core_test behavior_test fight_test ui_test; do
    TD="$OUT/$t"
    mkdir -p "$TD"
    if "$ZIG" -fsafe -W -osl --output-dir "$TD" "$TESTS/$t.zig" >"$TD/zig.log" 2>&1; then
        pass_case "$t -fsafe -W compile clean"
    else
        fail_case "$t -fsafe -W compile failed (see $TD/zig.log)"
        tail -20 "$TD/zig.log" | sed 's/^/       /'
        continue
    fi
    if sh "$TD/build_target.sh" linux "$TD/$t" >"$TD/build.log" 2>&1; then
        pass_case "$t built natively (build_target.sh linux)"
    else
        fail_case "$t native link failed (see $TD/build.log)"
        tail -20 "$TD/build.log" | sed 's/^/       /'
        continue
    fi
    timeout 120 "$TD/$t" >"$TD/run.log" 2>&1
    RC=$?
    sed 's/^/       /' "$TD/run.log"
    if [ "$RC" -eq 0 ] && grep -qx "$t PASS" "$TD/run.log" \
        && ! grep -q '^FAIL - ' "$TD/run.log"; then
        CASES="$(grep -c '^ok - ' "$TD/run.log")"
        pass_case "$t PASS (exit 0; $CASES cases)"
    else
        fail_case "$t did not pass (rc=$RC; see $TD/run.log)"
    fi
done

# ---------------------------------------------------------------------------
# FAST 2: scripted full-fight goldens + 20-fight evidence table
# ---------------------------------------------------------------------------
echo "== FAST: scripted full-fight goldens + 20-fight table =="
FT_LOG="$OUT/fight_test/run.log"
if [ ! -f "$FT_LOG" ]; then
    fail_case "fight_test run log missing (driver build failed)"
else
    for c in scripted_golden_subdue_bytes scripted_golden_kill_bytes \
        scripted_golden_overkill_bytes scripted_golden_rare_modal_bytes \
        scripted_20_fight_table; do
        if grep -qx "ok - $c" "$FT_LOG"; then
            pass_case "fight_test: $c"
        else
            fail_case "fight_test: $c missing/failed"
        fi
    done

    FIGHT_N="$(grep -c '^FIGHT ' "$FT_LOG")"
    if [ "$FIGHT_N" -eq 20 ]; then
        pass_case "20 scripted fights recorded ($FIGHT_N FIGHT lines)"
    else
        fail_case "expected 20 FIGHT lines, found $FIGHT_N"
    fi
    for o in SUBDUE KILL OVERKILL; do
        if grep -q " outcome=$o " "$FT_LOG"; then
            pass_case "20-fight coverage: $o"
        else
            fail_case "20-fight coverage: no $o outcome"
        fi
    done
    if grep -q ' modal=yes ' "$FT_LOG"; then
        pass_case "20-fight coverage: rare modal path"
    else
        fail_case "20-fight coverage: no modal fight"
    fi
fi

# ---------------------------------------------------------------------------
# FAST 3: purity — no std_gfx/std_io imports in the pure game modules
# ---------------------------------------------------------------------------
echo "== FAST: purity (no std_gfx/std_io in game/fight/behavior) =="
for f in game fight behavior; do
    PURE="$UNDDIR/$f.zig"
    if [ ! -f "$PURE" ]; then
        fail_case "purity: $f.zig missing"
    elif grep -Eq '@import\("std_(gfx|io)(\.zig)?"' "$PURE"; then
        fail_case "purity: $f.zig imports std_gfx/std_io"
        grep -nE '@import\("std_(gfx|io)(\.zig)?"' "$PURE" | sed 's/^/       /'
    else
        pass_case "purity: $f.zig has no std_gfx/std_io import"
    fi
done

# ---------------------------------------------------------------------------
# FAST 4: z9edit tier + unchanged lexer goldens (regression)
# ---------------------------------------------------------------------------
echo "== FAST: z9edit tier + goldens =="
ZLOG="$OUT/tier_edit.log"
if ZIG="$ZIG" OUT="$OUT/z9edit" sh examples/z98/z9edit/tests/tier_edit.sh \
    >"$ZLOG" 2>&1; then
    pass_case "z9edit tier_edit.sh green"
else
    fail_case "z9edit tier_edit.sh failed (see $ZLOG)"
fi
tail -6 "$ZLOG" | sed 's/^/       /'
LEX_LINE="$(grep '^lexer md5 3x:' "$ZLOG" | tail -1)"
if [ -n "$LEX_LINE" ]; then
    MD1="$(printf '%s\n' "$LEX_LINE" | awk '{print $4}')"
    MD2="$(printf '%s\n' "$LEX_LINE" | awk '{print $5}')"
    MD3="$(printf '%s\n' "$LEX_LINE" | awk '{print $6}')"
    if [ -n "$MD1" ] && [ "$MD1" = "$MD2" ] && [ "$MD2" = "$MD3" ]; then
        pass_case "z9edit lexer goldens byte-identical 3x ($MD1)"
    else
        fail_case "z9edit lexer goldens differ ($MD1 / $MD2 / $MD3)"
    fi
    if [ "$MD1" = "$EXPECTED_LEXER_MD5" ]; then
        pass_case "z9edit lexer md5 unchanged ($MD1)"
    else
        fail_case "z9edit lexer md5 changed (got $MD1, want $EXPECTED_LEXER_MD5)"
    fi
else
    fail_case "z9edit lexer md5 line missing from tier output"
fi

# ---------------------------------------------------------------------------
# FAST 5: no committed Python tooling under the example
# ---------------------------------------------------------------------------
echo "== FAST: no committed .py tooling =="
PY_FILES="$(git -C "$ROOT" ls-files examples/z98/undersanded | grep '\.py$' || true)"
if [ -z "$PY_FILES" ]; then
    pass_case "no committed .py tooling under examples/z98/undersanded/"
else
    fail_case "committed .py tooling found under examples/z98/undersanded/"
    printf '%s\n' "$PY_FILES" | sed 's/^/       /'
fi

echo
echo "== tier_m2_fight summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M2 FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "TIER_M2 PASS $PASSES passed / $FAILS failed"
exit 0
