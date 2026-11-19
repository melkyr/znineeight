#!/bin/sh
# tier_m8_content.sh — UNDERSANDED M8 demo content-complete acceptance tier
# (spec §18, §32, §38 P26, §40 M8).
#
# FAST, native only (no Wine gate):
#   * run journal_test and the content walk driver with -fsafe -W -osl +
#     build_target.sh linux; assert exact PASS lines and every case name
#   * content walk: fresh start -> Z1-Z3 fights -> boss node locked/telegraphed
#     before six distinct non-boss creatures and open at six; journal entries
#     unlock and journal_viewed is set; both masks survive a save round-trip
#   * run tests/nav_help_overlay.sh and require its overlay-precedence cases
#   * build undtool_native.zig; byte-match the new help + journal screen dumps
#     and the boss row extracted from --dump-defs; prove help/journal reruns are
#     deterministic and that a mutated help dump no longer matches its golden
#   * nest tier_m7_save.sh (which nests M6 -> M1) and require its PASS
#
# Env: ZIG       compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT       scratch dir (default /tmp/undersanded_m8_tier)
#      FIXTURES  golden dir override (default tests/fixtures; used to prove
#                non-vacuity with a mutated /tmp copy)
#      M7_TIER   nested M7 tier path override
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# failure and prints `TIER_M8 PASS <n> passed / <m> failed`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m8_tier}"
TESTS="examples/z98/undersanded/tests"
FIXTURES="${FIXTURES:-$SCRIPT_DIR/fixtures}"
M7_TIER="${M7_TIER:-$TESTS/tier_m7_save.sh}"
DATA="$ROOT/examples/z98/undersanded/data.z98"
HELP_GOLDEN="$FIXTURES/dump_grid_help.golden"
JOURNAL_GOLDEN="$FIXTURES/dump_grid_journal.golden"
BOSS_GOLDEN="$FIXTURES/defs_boss_golden.txt"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/seed151_build"
    exit 1
fi
if [ ! -f "$DATA" ] || [ ! -f "$HELP_GOLDEN" ] \
    || [ ! -f "$JOURNAL_GOLDEN" ] || [ ! -f "$BOSS_GOLDEN" ]; then
    echo "FAIL: M8 fixture missing ($DATA, $HELP_GOLDEN, $JOURNAL_GOLDEN, $BOSS_GOLDEN)"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 1: M8 unit drivers (-fsafe -W clean, PASS, exit 0, no FAIL line)
# ---------------------------------------------------------------------------
echo "== FAST: M8 unit drivers =="
run_driver() {
    t="$1"
    td="$OUT/$t"
    mkdir -p "$td"
    if ! "$ZIG" -fsafe -W -osl --output-dir "$td" "$TESTS/$t.zig" \
        >"$td/zig.log" 2>&1; then
        fail_case "$t -fsafe -W compile failed (see $td/zig.log)"
        tail -20 "$td/zig.log" | sed 's/^/       /'
        return
    fi
    pass_case "$t -fsafe -W compile clean"
    if ! sh "$td/build_target.sh" linux "$td/$t" >"$td/build.log" 2>&1; then
        fail_case "$t native link failed (see $td/build.log)"
        tail -20 "$td/build.log" | sed 's/^/       /'
        return
    fi
    pass_case "$t built natively (build_target.sh linux)"
    timeout 180 "$td/$t" >"$td/run.log" 2>&1
    rc=$?
    sed 's/^/       /' "$td/run.log"
    if [ "$rc" -eq 0 ] && grep -qx "$t PASS" "$td/run.log" \
        && ! grep -q '^FAIL - ' "$td/run.log"; then
        cases="$(grep -c '^ok - ' "$td/run.log")"
        pass_case "$t PASS (exit 0; $cases cases)"
    else
        fail_case "$t did not pass (rc=$rc; see $td/run.log)"
    fi
}

require_case() {
    log="$1"
    case_name="$2"
    if [ -f "$log" ] && grep -qx "ok - $case_name" "$log"; then
        pass_case "$(basename "$(dirname "$log")"): $case_name"
    else
        fail_case "$(basename "$(dirname "$log")"): $case_name missing/failed"
    fi
}

require_overlay_case() {
    log="$1"
    case_name="$2"
    if [ -f "$log" ] && grep -qxF "ok   - $case_name" "$log"; then
        pass_case "nav_help_overlay: $case_name"
    else
        fail_case "nav_help_overlay: $case_name missing/failed"
    fi
}

run_driver journal_test
JOURNAL_LOG="$OUT/journal_test/run.log"
for c in journal_trigger_matrix journal_viewed_indicator help_page_map \
    tooltip_once help_overlay_no_action journal_screen_open_sets_viewed \
    zone_flavour_render content_text_keys speed_reveal_survives_save; do
    require_case "$JOURNAL_LOG" "$c"
done
run_driver help_test
HELP_TEST_LOG="$OUT/help_test/run.log"
for c in help_page_map help_pages_present help_screen_render_deterministic \
    help_overlay_no_action; do
    require_case "$HELP_TEST_LOG" "$c"
done

# ---------------------------------------------------------------------------
# FAST 2: scripted full loop start -> Z1-Z3 -> boss gate
# ---------------------------------------------------------------------------
echo "== FAST: content walk (start -> Z1-Z3 -> boss gate) =="
CW="$OUT/content_walk"
mkdir -p "$CW/run"
CW_OK=0
if "$ZIG" -fsafe -W -osl --output-dir "$CW" "$TESTS/content_walk.zig" \
    >"$CW/zig.log" 2>&1; then
    pass_case "content_walk.zig -fsafe -W compile clean"
    if sh "$CW/build_target.sh" linux "$CW/content_walk" >"$CW/build.log" 2>&1; then
        pass_case "content_walk built natively (build_target.sh linux)"
        CW_OK=1
    else
        fail_case "content_walk native link failed (see $CW/build.log)"
        tail -20 "$CW/build.log" | sed 's/^/       /'
    fi
else
    fail_case "content_walk.zig compile failed (see $CW/zig.log)"
    tail -20 "$CW/zig.log" | sed 's/^/       /'
fi

CW_SAVE="$CW/run/save0.dat"
if [ "$CW_OK" -eq 1 ]; then
    timeout 180 "$CW/content_walk" "$CW/run" >"$CW/run.log" 2>&1
    CW_RC=$?
    sed 's/^/       /' "$CW/run.log"
    if [ "$CW_RC" -eq 0 ] && grep -qx 'content_walk PASS' "$CW/run.log" \
        && ! grep -q '^FAIL - ' "$CW/run.log"; then
        pass_case "content_walk PASS (exit 0)"
    else
        fail_case "content_walk did not pass (rc=$CW_RC; see $CW/run.log)"
    fi
else
    fail_case "content_walk did not run (build failed)"
fi

for c in full_loop_z1_z3_fights_to_boss_gate \
    boss_node_locked_before_six_seen boss_node_open_telegraph_at_six_seen \
    journal_unlocks_and_viewed_bits journal_masks_survive_save_roundtrip; do
    require_case "$CW/run.log" "$c"
done

if [ -f "$CW_SAVE" ]; then
    pass_case "content_walk wrote a save file"
else
    fail_case "content_walk did not write a save file"
fi
MASK_LINE="$(grep '^journal_mask=' "$CW_SAVE" 2>/dev/null | head -n 1)"
VIEW_LINE="$(grep '^journal_viewed=' "$CW_SAVE" 2>/dev/null | head -n 1)"
if [ -n "$MASK_LINE" ] && [ "$MASK_LINE" != "journal_mask=0,0" ]; then
    pass_case "content walk save carries a non-zero journal_mask"
else
    fail_case "content walk save journal_mask missing/zero"
fi
if [ -n "$VIEW_LINE" ] && [ "$VIEW_LINE" != "journal_viewed=0,0" ]; then
    pass_case "content walk save carries a non-zero journal_viewed"
else
    fail_case "content walk save journal_viewed missing/zero"
fi

# ---------------------------------------------------------------------------
# FAST 3: help-overlay precedence regression (Task 3 follow-up)
# ---------------------------------------------------------------------------
echo "== FAST: nav_help_overlay =="
NHLOG="$OUT/nav_help_overlay.log"
if ZIG="$ZIG" OUT="$OUT/nav_help" sh "$SCRIPT_DIR/nav_help_overlay.sh" \
    >"$NHLOG" 2>&1; then
    pass_case "nav_help_overlay.sh green"
else
    fail_case "nav_help_overlay.sh failed (see $NHLOG)"
fi
sed 's/^/       /' "$NHLOG"
if grep -qx 'nav_help_overlay PASS' "$NHLOG"; then
    pass_case "nav_help_overlay PASS line present"
else
    fail_case "nav_help_overlay PASS line missing"
fi
for c in "driver exits 0" "driver asserts sentinel/no-bak/dock/money" \
    "help overlay rendered" "loop continued to the dock" \
    "no quit prompt while help was open"; do
    require_overlay_case "$NHLOG" "$c"
done

# ---------------------------------------------------------------------------
# FAST 4: native undtool + help/journal/boss goldens
# ---------------------------------------------------------------------------
echo "== FAST: native undtool + help/journal/boss goldens =="
NATIVE="$OUT/native"
mkdir -p "$NATIVE"
NATIVE="$(cd "$NATIVE" && pwd)"
NIX_OK=0
if "$ZIG" -fsafe -W -osl --output-dir "$NATIVE" \
    examples/z98/undersanded/undtool_native.zig >"$OUT/undtool_compile.log" 2>&1; then
    pass_case "undtool_native.zig -fsafe -W compile clean"
    if sh "$NATIVE/build_target.sh" linux "$NATIVE/undtool.nix" \
        >"$OUT/undtool_link.log" 2>&1; then
        pass_case "undtool.nix built natively (build_target.sh linux)"
        NIX_OK=1
    else
        fail_case "undtool.nix native link failed (see $OUT/undtool_link.log)"
        tail -20 "$OUT/undtool_link.log" | sed 's/^/       /'
    fi
else
    fail_case "undtool_native.zig compile failed (see $OUT/undtool_compile.log)"
    tail -20 "$OUT/undtool_compile.log" | sed 's/^/       /'
fi
NIX="$NATIVE/undtool.nix"

if [ "$NIX_OK" -eq 1 ]; then
    cp "$DATA" "$NATIVE/data.z98"
    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$OUT/help1.txt" --screen help ) \
        >"$OUT/help.err" 2>&1
    HELP_RC=$?
    if [ "$HELP_RC" -eq 0 ] && cmp -s "$OUT/help1.txt" "$HELP_GOLDEN"; then
        pass_case "--dump-grid --screen help byte-identical to golden"
    else
        fail_case "--dump-grid --screen help differs from golden (rc=$HELP_RC)"
        diff -u "$HELP_GOLDEN" "$OUT/help1.txt" 2>/dev/null | sed 's/^/       /'
    fi

    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$OUT/journal1.txt" --screen journal ) \
        >"$OUT/journal.err" 2>&1
    JOURNAL_RC=$?
    if [ "$JOURNAL_RC" -eq 0 ] && cmp -s "$OUT/journal1.txt" "$JOURNAL_GOLDEN"; then
        pass_case "--dump-grid --screen journal byte-identical to golden"
    else
        fail_case "--dump-grid --screen journal differs from golden (rc=$JOURNAL_RC)"
        diff -u "$JOURNAL_GOLDEN" "$OUT/journal1.txt" 2>/dev/null | sed 's/^/       /'
    fi

    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$OUT/help2.txt" --screen help ) \
        >"$OUT/help2.err" 2>&1
    if cmp -s "$OUT/help1.txt" "$OUT/help2.txt"; then
        pass_case "--dump-grid --screen help rerun is byte-identical"
    else
        fail_case "--dump-grid --screen help rerun differs"
    fi

    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$OUT/journal2.txt" --screen journal ) \
        >"$OUT/journal2.err" 2>&1
    if cmp -s "$OUT/journal1.txt" "$OUT/journal2.txt"; then
        pass_case "--dump-grid --screen journal rerun is byte-identical"
    else
        fail_case "--dump-grid --screen journal rerun differs"
    fi

    timeout 120 "$NIX" --dump-defs "$DATA" >"$OUT/defs.txt" 2>"$OUT/defs.err"
    grep '^id=17,' "$OUT/defs.txt" >"$OUT/boss_row.txt" 2>/dev/null
    if cmp -s "$OUT/boss_row.txt" "$BOSS_GOLDEN"; then
        pass_case "--dump-defs boss row byte-identical to golden"
    else
        fail_case "--dump-defs boss row differs from golden"
        diff -u "$BOSS_GOLDEN" "$OUT/boss_row.txt" 2>/dev/null | sed 's/^/       /'
    fi

    cp "$OUT/help1.txt" "$OUT/help_mutated.txt"
    printf 'NON-VACUITY EXTRA LINE\n' >>"$OUT/help_mutated.txt"
    if ! cmp -s "$OUT/help_mutated.txt" "$HELP_GOLDEN"; then
        pass_case "non-vacuity: mutated help dump no longer matches the golden"
    else
        fail_case "non-vacuity: mutated help dump still matched the golden"
    fi

    rm -f "$NATIVE/data.z98"
else
    for label in "--dump-grid --screen help byte-identical to golden" \
        "--dump-grid --screen journal byte-identical to golden" \
        "--dump-grid --screen help rerun is byte-identical" \
        "--dump-grid --screen journal rerun is byte-identical" \
        "--dump-defs boss row byte-identical to golden" \
        "non-vacuity: mutated help dump no longer matches the golden"; do
        fail_case "$label (undtool.nix did not build)"
    done
fi

# ---------------------------------------------------------------------------
# FAST 5: native --save-roundtrip preserves the content-walk journal masks
# ---------------------------------------------------------------------------
echo "== FAST: --save-roundtrip journal masks =="
if [ "$NIX_OK" -eq 1 ] && [ -f "$CW_SAVE" ]; then
    RT="$OUT/content_walk/roundtrip.dat"
    cp "$CW_SAVE" "$RT"
    cp "$RT" "$OUT/content_walk/roundtrip.before"
    timeout 120 "$NIX" --save-roundtrip "$RT" \
        >"$OUT/rt.out" 2>"$OUT/rt.err"
    RT_RC=$?
    if [ "$RT_RC" -eq 0 ]; then
        pass_case "--save-roundtrip content-walk save exits 0"
    else
        fail_case "--save-roundtrip content-walk save failed (rc=$RT_RC; see $OUT/rt.err)"
        sed 's/^/       /' "$OUT/rt.err"
    fi
    if cmp -s "$RT" "$OUT/content_walk/roundtrip.before"; then
        pass_case "--save-roundtrip leaves journal masks byte-identical"
    else
        fail_case "--save-roundtrip changed the content-walk save"
    fi
    if [ ! -f "$RT.rt" ]; then
        pass_case "--save-roundtrip removes its temp file"
    else
        fail_case "--save-roundtrip left its temp file behind"
    fi
else
    fail_case "--save-roundtrip journal masks skipped (undtool or save missing)"
fi

# ---------------------------------------------------------------------------
# FAST 6: nested M7 (which nests M6 -> ...) regression gate
# ---------------------------------------------------------------------------
echo "== FAST: M7 regression (tier_m7_save.sh) =="
M7LOG="$OUT/tier_m7_save.log"
if ZIG="$ZIG" OUT="$OUT/m7" FIXTURES="$SCRIPT_DIR/fixtures" sh "$M7_TIER" \
    >"$M7LOG" 2>&1; then
    pass_case "tier_m7_save.sh green (M1->M7 + save/dumps)"
else
    fail_case "tier_m7_save.sh failed (see $M7LOG)"
fi
tail -8 "$M7LOG" | sed 's/^/       /'
if grep -q '^TIER_M7 PASS ' "$M7LOG" && ! grep -q '^TIER_M7 FAIL ' "$M7LOG"; then
    pass_case "tier_m7_save summary PASS"
else
    fail_case "tier_m7_save summary missing/FAIL"
fi
if grep -q '^FAIL - ' "$M7LOG"; then
    fail_case "tier_m7_save reported a FAIL line"
else
    pass_case "tier_m7_save reports no FAIL - lines"
fi

echo
echo "== tier_m8_content summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M8 FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "TIER_M8 PASS $PASSES passed / $FAILS failed"
exit 0
