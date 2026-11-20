#!/bin/sh
# tier_m9_px.sh — UNDERSANDED M9 pixel tier acceptance gate
# (spec §23.1, §26, §27, §28, §29, §33, §35, §36 M9, §38 P27).
#
# FAST, native only (no Wine gate):
#   * build/run px_core_test, art_test, perf_test and px_test with -fsafe -W
#     -osl + build_target.sh linux; assert exact PASS lines and named cases
#   * px_test prints the deterministic art-fight 640x480 565 framebuffer
#     checksum; byte-compare it with art_fight.golden (cmp)
#   * non-vacuity: mutate a COPY of the art golden (one hex digit) and prove the
#     same cmp and px_test (ART_GOLDEN override) reject it; the committed art
#     fixture was re-pinned exactly once by M10 Task 4 (sprite/background wiring)
#   * build undtool_native.zig; byte-match the M8 terminal goldens for
#     --dump-grid --screen fight|dock|map|node|lore|menu|journal|help
#   * run the z9edit tier_edit.sh and require its PASS plus the pinned lexer md5
#   * byte-compare the pinned perf-log shape with perf_log.golden
#   * nest tier_m8_content.sh (which nests M7 -> ... -> M1) and require PASS;
#     prove a failing/missing nested tier propagates without weakening the real
#     run
#   * SLOW evidence only (loud skips, never FAIL): run_px_probe.sh (real COM
#     Restore) only when Wine/Xvfb are available; tier_edit_gui.sh opt-in
#
# Env: ZIG         compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT         scratch dir (default /tmp/undersanded_m9_tier)
#      FIXTURES    golden dir override (default tests/fixtures)
#      ART_GOLDEN  art checksum golden override (non-vacuity mutations)
#      M8_TIER     nested M8 tier path override (propagation probe)
#      M9_GUI_EVIDENCE=1 run the SLOW z9edit GUI evidence tier too
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# FAST failure and prints `TIER_M9 PASS <n> passed / <m> failed`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m9_tier}"
TESTS="examples/z98/undersanded/tests"
FIXTURES="${FIXTURES:-$SCRIPT_DIR/fixtures}"
ART_GOLDEN="${ART_GOLDEN:-$FIXTURES/art_fight.golden}"
PERF_GOLDEN="$FIXTURES/perf_log.golden"
M8_TIER="${M8_TIER:-$TESTS/tier_m8_content.sh}"
DATA="$ROOT/examples/z98/undersanded/data.z98"
EDIT_TIER="$ROOT/examples/z98/z9edit/tests/tier_edit.sh"
GUI_EDIT_TIER="$ROOT/examples/z98/z9edit/tests/tier_edit_gui.sh"
PROBE="$TESTS/run_px_probe.sh"
LEXER_MD5="dcc81009e9a36c86e4d90e104c439871"
SCREENS="fight dock map node lore menu journal help"

case "$ART_GOLDEN" in
    /*) : ;;
    *) ART_GOLDEN="$(cd "$(dirname "$ART_GOLDEN")" 2>/dev/null && pwd)/$(basename "$ART_GOLDEN")" ;;
esac
export ART_GOLDEN

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_case() { echo "EVIDENCE-SKIP: LOUD SKIP — $1"; SKIPS=$((SKIPS + 1)); }

indent() { while IFS= read -r line; do printf '       %s\n' "$line"; done; }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/seed151_build"
    exit 1
fi
if [ ! -f "$DATA" ] || [ ! -f "$ART_GOLDEN" ] || [ ! -f "$PERF_GOLDEN" ] \
    || [ ! -f "$EDIT_TIER" ]; then
    echo "FAIL: M9 fixture missing ($DATA, $ART_GOLDEN, $PERF_GOLDEN, $EDIT_TIER)"
    exit 1
fi
for s in $SCREENS; do
    if [ ! -f "$FIXTURES/dump_grid_$s.golden" ]; then
        echo "FAIL: M9 terminal golden missing: $FIXTURES/dump_grid_$s.golden"
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 1: native pixel/art/perf drivers (-fsafe -W clean, PASS, no FAIL line)
# ---------------------------------------------------------------------------
echo "== FAST: M9 native drivers =="
run_driver() {
    t="$1"
    td="$OUT/$t"
    mkdir -p "$td"
    if ! "$ZIG" -fsafe -W -osl --output-dir "$td" "$TESTS/$t.zig" \
        >"$td/zig.log" 2>&1; then
        fail_case "$t -fsafe -W compile failed (see $td/zig.log)"
        tail -20 "$td/zig.log" | indent
        return
    fi
    pass_case "$t -fsafe -W compile clean"
    if ! sh "$td/build_target.sh" linux "$td/$t" >"$td/build.log" 2>&1; then
        fail_case "$t native link failed (see $td/build.log)"
        tail -20 "$td/build.log" | indent
        return
    fi
    pass_case "$t built natively (build_target.sh linux)"
    timeout 180 "$td/$t" >"$td/run.log" 2>&1
    rc=$?
    indent <"$td/run.log"
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

for t in px_core_test art_test perf_test px_test; do
    run_driver "$t"
done

PX_CORE_LOG="$OUT/px_core_test/run.log"
for c in repaint_flag_set_clear bar_math_spec27 golden_320x200_framebuffer; do
    require_case "$PX_CORE_LOG" "$c"
done

ART_LOG="$OUT/art_test/run.log"
for c in golden_art_fight_640x480 bar_geometry_zero_half_max \
    bar_red_zone_dotted_border shake_on_subdue_fail \
    speed_hidden_journal_sonar msg_line_parity_all_ids \
    dirty_coalesce_order_overflow tool_status_69_cols_80_safe; do
    require_case "$ART_LOG" "$c"
done

PERF_LOG="$OUT/perf_test/run.log"
for c in format_pinned_shape percentiles_nearest_rank key_filter_parity \
    scripted_walk_dock_map_node_fight_settle_dock; do
    require_case "$PERF_LOG" "$c"
done

PX_LOG="$OUT/px_test/run.log"
for c in art_fight_640x480_565_dump art_fight_checksum_matches_golden \
    button_rects_four tool_status_line_69_cols perf_log_shape_pinned \
    surface_lost_full_repaint_after_restore; do
    require_case "$PX_LOG" "$c"
done

# ---------------------------------------------------------------------------
# FAST 2: art framebuffer golden + non-vacuity mutations
# ---------------------------------------------------------------------------
echo "== FAST: art framebuffer golden (checksum cmp) =="
ART_SUM="$OUT/art_checksum.txt"
CS_LINE="$(grep '^art_fight_checksum=' "$PX_LOG" 2>/dev/null | head -n 1)"
if [ -n "$CS_LINE" ]; then
    printf '%s\n' "${CS_LINE#art_fight_checksum=}" >"$ART_SUM"
    pass_case "px_test printed the art-fight 640x480 565 checksum"
else
    : >"$ART_SUM"
    fail_case "px_test did not print an art-fight checksum"
fi

compare_art() {
    golden="$1"
    sumfile="$2"
    cmp -s "$sumfile" "$golden"
}

if compare_art "$ART_GOLDEN" "$ART_SUM"; then
    pass_case "art-fight checksum byte-identical to golden (cmp)"
else
    fail_case "art-fight checksum differs from golden (cmp)"
    diff -u "$ART_GOLDEN" "$ART_SUM" 2>/dev/null | indent
fi

# Non-vacuity: flip one hex digit in a COPY of the committed golden and prove
# the same comparison (and px_test's ART_GOLDEN override) rejects it.
MUT_GOLDEN="$OUT/art_fight.mutated.golden"
RAW_GOLDEN="$(head -n 1 "$ART_GOLDEN")"
PREFIX="${RAW_GOLDEN%?}"
LAST_DIGIT="${RAW_GOLDEN#$PREFIX}"
case "$LAST_DIGIT" in
    0) REPLACEMENT="1" ;;
    1) REPLACEMENT="0" ;;
    2) REPLACEMENT="3" ;;
    3) REPLACEMENT="2" ;;
    4) REPLACEMENT="5" ;;
    5) REPLACEMENT="4" ;;
    6) REPLACEMENT="7" ;;
    7) REPLACEMENT="6" ;;
    8) REPLACEMENT="9" ;;
    9) REPLACEMENT="8" ;;
    a) REPLACEMENT="b" ;;
    b) REPLACEMENT="a" ;;
    c) REPLACEMENT="d" ;;
    d) REPLACEMENT="c" ;;
    e) REPLACEMENT="f" ;;
    f) REPLACEMENT="e" ;;
    *) REPLACEMENT="0" ;;
esac
printf '%s%s\n' "$PREFIX" "$REPLACEMENT" >"$MUT_GOLDEN"
if cmp -s "$MUT_GOLDEN" "$ART_GOLDEN"; then
    fail_case "non-vacuity: mutation did not change the art golden copy"
else
    pass_case "non-vacuity: one-hex-digit art golden copy differs from fixture"
fi
if compare_art "$MUT_GOLDEN" "$ART_SUM"; then
    fail_case "non-vacuity: same cmp accepted the mutated art golden"
else
    pass_case "non-vacuity: same cmp rejects the mutated art golden"
fi
if ART_GOLDEN="$MUT_GOLDEN" timeout 180 "$OUT/px_test/px_test" \
    >"$OUT/px_test_mutated.log" 2>&1; then
    fail_case "non-vacuity: px_test accepted the mutated ART_GOLDEN"
else
    if grep -qx 'FAIL - art_fight_checksum_matches_golden' \
        "$OUT/px_test_mutated.log"; then
        pass_case "non-vacuity: px_test rejects the mutated ART_GOLDEN"
    else
        fail_case "non-vacuity: px_test failed for the wrong reason (see $OUT/px_test_mutated.log)"
    fi
fi
rm -f "$MUT_GOLDEN"
if compare_art "$ART_GOLDEN" "$ART_SUM"; then
    pass_case "committed art golden unchanged after non-vacuity mutation"
else
    fail_case "committed art golden was disturbed by non-vacuity mutation"
fi

# ---------------------------------------------------------------------------
# FAST 3: perf log shape fixture
# ---------------------------------------------------------------------------
echo "== FAST: perf log shape =="
PERF_SHAPE_LINE="$(grep '^perf_shape=' "$PX_LOG" 2>/dev/null | head -n 1)"
if [ -n "$PERF_SHAPE_LINE" ]; then
    printf '%s\n' "${PERF_SHAPE_LINE#perf_shape=}" >"$OUT/perf_shape.txt"
    if cmp -s "$OUT/perf_shape.txt" "$PERF_GOLDEN"; then
        pass_case "perf log shape byte-identical to fixture"
    else
        fail_case "perf log shape differs from fixture"
        diff -u "$PERF_GOLDEN" "$OUT/perf_shape.txt" 2>/dev/null | indent
    fi
else
    fail_case "px_test did not print the perf log shape"
fi

# ---------------------------------------------------------------------------
# FAST 4: terminal --dump-grid parity with the committed M8 goldens
# ---------------------------------------------------------------------------
echo "== FAST: native undtool + terminal M8 goldens (8 screens) =="
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
        tail -20 "$OUT/undtool_link.log" | indent
    fi
else
    fail_case "undtool_native.zig compile failed (see $OUT/undtool_compile.log)"
    tail -20 "$OUT/undtool_compile.log" | indent
fi
NIX="$NATIVE/undtool.nix"

# The committed M8 goldens were authored under two content states and carry
# those bytes forward: lore/help include the data.z98 manual text, while the
# fixed dock/map/node/menu/journal/fight frames are the compiled fallback (no
# data override). Reproduce each screen's authored condition exactly; these
# terminal fixtures were not regenerated (M10 Task 4 re-pinned only the art
# checksum fixture when it wired sprites/backgrounds).
dump_one() {
    s="$1"
    GOLDEN="$FIXTURES/dump_grid_$s.golden"
    DUMP="$OUT/dump_grid_$s.txt"
    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$DUMP" --screen "$s" ) \
        >"$OUT/dump_grid_$s.err" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ] && cmp -s "$DUMP" "$GOLDEN"; then
        pass_case "--dump-grid --screen $s byte-identical to M8 golden"
    else
        fail_case "--dump-grid --screen $s differs from M8 golden (rc=$rc)"
        diff -u "$GOLDEN" "$DUMP" 2>/dev/null | indent
    fi
}

if [ "$NIX_OK" -eq 1 ]; then
    cp "$DATA" "$NATIVE/data.z98"
    dump_one lore
    dump_one help
    # --emit-fallback must reproduce the checked-in module byte-for-byte, and
    # two runs must agree (deterministic; no timestamps).
    FALLBACK_A="$OUT"
    FALLBACK_B="$OUT/fallback_b"
    mkdir -p "$FALLBACK_A" "$FALLBACK_B"
    if ( cd "$NATIVE" && timeout 120 ./undtool.nix --emit-fallback "$FALLBACK_A" ) \
        >"$OUT/fallback_a.err" 2>&1; then
        pass_case "--emit-fallback ran natively"
    else
        fail_case "--emit-fallback failed (see $OUT/fallback_a.err)"
    fi
    if ( cd "$NATIVE" && timeout 120 ./undtool.nix --emit-fallback "$FALLBACK_B" ) \
        >"$OUT/fallback_b.err" 2>&1; then
        pass_case "--emit-fallback rerun ran natively"
    else
        fail_case "--emit-fallback rerun failed (see $OUT/fallback_b.err)"
    fi
    if cmp -s "$FALLBACK_A/fallback_rows.zig" "$FALLBACK_B/fallback_rows.zig"; then
        pass_case "--emit-fallback output is deterministic (two runs byte-identical)"
    else
        fail_case "--emit-fallback output differs between runs"
    fi
    if cmp -s "$FALLBACK_A/fallback_rows.zig" "$UNDDIR/fallback_rows.zig"; then
        pass_case "--emit-fallback matches checked-in fallback_rows.zig (cmp)"
    else
        fail_case "--emit-fallback drifted from checked-in fallback_rows.zig"
        diff -u "$UNDDIR/fallback_rows.zig" "$FALLBACK_A/fallback_rows.zig" 2>/dev/null | indent
    fi
    rm -f "$NATIVE/data.z98"
    for s in fight dock map node menu journal; do
        dump_one "$s"
    done
    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$OUT/dump_grid_fight2.txt" --screen fight ) \
        >"$OUT/dump_grid_fight2.err" 2>&1
    if cmp -s "$OUT/dump_grid_fight.txt" "$OUT/dump_grid_fight2.txt"; then
        pass_case "--dump-grid fight rerun is byte-identical"
    else
        fail_case "--dump-grid fight rerun differs"
    fi
else
    for s in $SCREENS; do
        fail_case "--dump-grid --screen $s byte-identical to M8 golden (undtool.nix did not build)"
    done
    fail_case "--dump-grid fight rerun is byte-identical (undtool.nix did not build)"
fi

# ---------------------------------------------------------------------------
# FAST 5: z9edit gate + pinned lexer md5
# ---------------------------------------------------------------------------
echo "== FAST: z9edit tier_edit (lexer md5) =="
EDIT_LOG="$OUT/tier_edit.log"
if ZIG="$ZIG" OUT="$OUT/z9edit" sh "$EDIT_TIER" >"$EDIT_LOG" 2>&1; then
    pass_case "tier_edit.sh green"
else
    fail_case "tier_edit.sh failed (see $EDIT_LOG)"
fi
tail -8 "$EDIT_LOG" | indent
if grep -qx 'TIER_EDIT PASS' "$EDIT_LOG"; then
    pass_case "tier_edit summary PASS"
else
    fail_case "tier_edit summary missing/FAIL"
fi
if grep -q "lexer md5 3x: $LEXER_MD5 $LEXER_MD5 $LEXER_MD5" "$EDIT_LOG"; then
    pass_case "lexer md5 matches pinned $LEXER_MD5 (3x)"
else
    fail_case "lexer md5 drifted from pinned $LEXER_MD5"
fi
if grep -q '^FAIL - ' "$EDIT_LOG"; then
    fail_case "tier_edit reported a FAIL line"
else
    pass_case "tier_edit reports no FAIL - lines"
fi

# ---------------------------------------------------------------------------
# FAST 6: mechanical owner/registry quality smells
# ---------------------------------------------------------------------------
echo "== FAST: quality smells (owners/ids/LOC) =="
SMELLS_LOG="$OUT/quality_smells.log"
if sh "$TESTS/quality_smells.sh" >"$SMELLS_LOG" 2>&1; then
    pass_case "quality_smells.sh green"
else
    fail_case "quality_smells.sh failed (see $SMELLS_LOG)"
fi
tail -8 "$SMELLS_LOG" | indent

# ---------------------------------------------------------------------------
# FAST 7: nested M8 (which nests M7 -> ... -> M1) + propagation non-vacuity
# ---------------------------------------------------------------------------
echo "== FAST: M8 regression (tier_m8_content.sh) =="
nested_m8() {
    log="$1"
    outdir="$2"
    ZIG="$ZIG" OUT="$outdir" FIXTURES="$SCRIPT_DIR/fixtures" sh "$M8_TIER" >"$log" 2>&1
}

M8LOG="$OUT/tier_m8_content.log"
if nested_m8 "$M8LOG" "$OUT/m8"; then
    pass_case "tier_m8_content.sh green (M1->M8 + content)"
else
    fail_case "tier_m8_content.sh failed (see $M8LOG)"
fi
tail -8 "$M8LOG" | indent
if grep -q '^TIER_M8 PASS ' "$M8LOG" && ! grep -q '^TIER_M8 FAIL ' "$M8LOG"; then
    pass_case "tier_m8_content summary PASS"
else
    fail_case "tier_m8_content summary missing/FAIL"
fi
if grep -q '^FAIL - ' "$M8LOG"; then
    fail_case "tier_m8_content reported a FAIL line"
else
    pass_case "tier_m8_content reports no FAIL - lines"
fi

STUB="$OUT/fail_m8_stub.sh"
printf '#!/bin/sh\necho "TIER_M8 FAIL 0 passed / 1 failed"\nexit 1\n' >"$STUB"
SAVED_M8_TIER="$M8_TIER"
M8_TIER="$STUB"
if nested_m8 "$OUT/m8_stub.log" "$OUT/m8_stub"; then
    fail_case "non-vacuity: failing nested M8 stub was ignored"
else
    pass_case "non-vacuity: failing nested M8 tier propagates as failure"
fi
if grep -qx 'TIER_M8 FAIL 0 passed / 1 failed' "$OUT/m8_stub.log"; then
    pass_case "non-vacuity: failing M8 stub actually ran (log reached)"
else
    fail_case "non-vacuity: failing M8 stub did not run"
fi
M8_TIER="$OUT/does_not_exist_tier.sh"
if nested_m8 "$OUT/m8_missing.log" "$OUT/m8_missing"; then
    fail_case "non-vacuity: missing nested M8 tier was ignored"
else
    pass_case "non-vacuity: missing nested M8 tier propagates as failure"
fi
M8_TIER="$SAVED_M8_TIER"
if grep -q '^TIER_M8 PASS ' "$M8LOG" && ! grep -q '^TIER_M8 FAIL ' "$M8LOG"; then
    pass_case "real nested M8 run remains green after propagation probes"
else
    fail_case "real nested M8 run was weakened by propagation probes"
fi

# ---------------------------------------------------------------------------
# SLOW evidence: real COM Restore() probe (loud skip, never a gate)
# ---------------------------------------------------------------------------
echo "== SLOW evidence: px probe (Wine/Xvfb, never a gate) =="
if [ ! -f "$PROBE" ]; then
    skip_case "run_px_probe.sh absent; real COM Restore() exercise not run"
else
    MISSING=""
    for tool in wine wineserver Xvfb xdpyinfo; do
        command -v "$tool" >/dev/null 2>&1 || MISSING="$MISSING $tool"
    done
    if [ -n "$MISSING" ]; then
        skip_case "px probe not run (missing:$MISSING); real COM Restore() is SLOW evidence only"
    else
        PROBE_LOG="$OUT/px_probe.log"
        if ZIG="$ZIG" OUT="$OUT/px_probe" timeout 300 sh "$PROBE" \
            >"$PROBE_LOG" 2>&1 \
            && grep -q '^EVIDENCE-PASS:' "$PROBE_LOG"; then
            echo "EVIDENCE - px probe: $(grep '^EVIDENCE-PASS:' "$PROBE_LOG" | head -n 1)"
        else
            skip_case "px probe did not report EVIDENCE-PASS; SLOW evidence only (see $PROBE_LOG)"
            tail -8 "$PROBE_LOG" 2>/dev/null | indent
        fi
    fi
fi

if [ -f "$GUI_EDIT_TIER" ]; then
    if [ "${M9_GUI_EVIDENCE:-0}" = "1" ] \
        && command -v wine >/dev/null 2>&1 \
        && command -v Xvfb >/dev/null 2>&1; then
        GUI_LOG="$OUT/tier_edit_gui.log"
        if ZIG="$ZIG" OUT="$OUT/z9edit_gui" timeout 600 sh "$GUI_EDIT_TIER" \
            >"$GUI_LOG" 2>&1; then
            echo "EVIDENCE - tier_edit_gui.sh green (SLOW GUI evidence)"
        else
            skip_case "tier_edit_gui.sh did not pass; SLOW evidence only (see $GUI_LOG)"
            tail -8 "$GUI_LOG" 2>/dev/null | indent
        fi
    else
        skip_case "tier_edit_gui.sh not run (SLOW GUI evidence; set M9_GUI_EVIDENCE=1)"
    fi
fi

echo
echo "== tier_m9_px summary: $PASSES passed, $FAILS failed, $SKIPS evidence skips =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M9 FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "TIER_M9 PASS $PASSES passed / $FAILS failed"
exit 0
