#!/bin/sh
# tier_m4_loop.sh — UNDERSANDED M4 expedition-loop acceptance tier
# (spec §5–§7, §11–§12, §36 M4).
#
# FAST, native only (Wine is SLOW evidence, never the gate):
#   * build the native gate runner undtool.nix (-fsafe -W -osl +
#     build_target.sh linux) from undtool_native.zig
#   * nested M3 regression gate tier_m3_sim.sh (M1/M2/M3 drivers + z9edit)
#   * run the M4 unit drivers (core, behavior, fight, ui, world, encounter,
#     expedition, screens, nav): -fsafe -W clean, PASS, exit 0
#   * run loop_test: deterministic full-loop trace byte-compared to
#     tests/fixtures/loop_golden.txt (committed, never regenerated here)
#   * --dump-grid --screen <fight|dock|map|node> byte-compared to the four
#     committed goldens; map golden must carry the zone-ladder hint
#   * --play native evidence: scripted `tq` key stream reaches the dock screen;
#     --play --fight and --play --sim exit 2
#
# SLOW (Wine evidence, never the gate): if wine and a pre-built undtool.exe are
# both present, run `--play` under a fresh WINEPREFIX; otherwise print an
# explicit operator-hardware skip line. An executed evidence failure makes the
# tier nonzero (never a silent skip).
#
# Env: ZIG  compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT  scratch dir (default /tmp/undersanded_m4_tier)
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# failure and prints `TIER_M4 PASS <n> passed / <m> failed`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m4_tier}"
TESTS="examples/z98/undersanded/tests"
FIXTURES="$SCRIPT_DIR/fixtures"

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
evidence_pass() { echo "EVIDENCE - $1"; PASSES=$((PASSES + 1)); }
evidence_fail() { echo "EVIDENCE-FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_evidence() { echo "operator-hardware: EVIDENCE not run: $1"; SKIPS=$((SKIPS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/seed151_build"
    exit 1
fi
if [ ! -f "$FIXTURES/loop_golden.txt" ] \
    || [ ! -f "$FIXTURES/dump_grid_fight.golden" ] \
    || [ ! -f "$FIXTURES/dump_grid_dock.golden" ] \
    || [ ! -f "$FIXTURES/dump_grid_map.golden" ] \
    || [ ! -f "$FIXTURES/dump_grid_node.golden" ]; then
    echo "FAIL: M4 fixture missing under $FIXTURES"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 1: native gate runner undtool.nix (-fsafe -W clean)
# ---------------------------------------------------------------------------
echo "== FAST: native undtool.nix =="
NATIVE="$OUT/native"
mkdir -p "$NATIVE"
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

# ---------------------------------------------------------------------------
# FAST 2: nested M1/M2/M3 regression gate
# ---------------------------------------------------------------------------
echo "== FAST: M3 regression (tier_m3_sim.sh) =="
M3LOG="$OUT/tier_m3_sim.log"
if ZIG="$ZIG" OUT="$OUT/m3" sh "$TESTS/tier_m3_sim.sh" >"$M3LOG" 2>&1; then
    pass_case "tier_m3_sim.sh green (M1/M2/M3 + z9edit)"
else
    fail_case "tier_m3_sim.sh failed (see $M3LOG)"
fi
tail -8 "$M3LOG" | sed 's/^/       /'
if grep -q '^TIER_M3 PASS ' "$M3LOG"; then
    pass_case "tier_m3_sim summary PASS"
else
    fail_case "tier_m3_sim summary missing/FAIL"
fi

# ---------------------------------------------------------------------------
# FAST 3: M4 unit drivers, -fsafe -W clean, PASS, exit 0
# ---------------------------------------------------------------------------
echo "== FAST: M4 unit drivers =="
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

for t in core_test behavior_test fight_test ui_test world_test \
    encounter_test expedition_test screens_test nav_test; do
    run_driver "$t"
done

UI_LOG="$OUT/ui_test/run.log"
if [ -f "$UI_LOG" ] && grep -qx 'ok - render_secured_msg_row_4b' "$UI_LOG"; then
    pass_case "ui_test: render_secured_msg_row_4b"
else
    fail_case "ui_test: render_secured_msg_row_4b missing/failed"
fi

NAV_LOG="$OUT/nav_test/run.log"
if [ -f "$NAV_LOG" ] && grep -qx 'ok - policy_subdue_release_surface_dock' "$NAV_LOG"; then
    pass_case "nav_test: policy_subdue_release_surface_dock"
else
    fail_case "nav_test: policy_subdue_release_surface_dock missing/failed"
fi

# ---------------------------------------------------------------------------
# FAST 4: scripted full-loop golden byte-match (committed fixture)
# ---------------------------------------------------------------------------
echo "== FAST: loop_test golden byte-match =="
run_driver loop_test
LOOP_LOG="$OUT/loop_test/run.log"
if [ -f "$LOOP_LOG" ]; then
    if cmp -s "$LOOP_LOG" "$FIXTURES/loop_golden.txt"; then
        pass_case "loop_test output byte-identical to loop_golden.txt"
    else
        fail_case "loop_test output differs from loop_golden.txt"
        diff -u "$FIXTURES/loop_golden.txt" "$LOOP_LOG" 2>/dev/null | sed 's/^/       /'
    fi
    if grep -qx 'loop_test PASS' "$LOOP_LOG"; then
        pass_case "loop_test PASS line present"
    else
        fail_case "loop_test PASS line missing"
    fi
    if grep -qx 'ok - full_subdue_release_kill_surface' "$LOOP_LOG"; then
        pass_case "loop_test: full_subdue_release_kill_surface"
    else
        fail_case "loop_test: full_subdue_release_kill_surface missing/failed"
    fi
else
    fail_case "loop_test run log missing (driver build failed)"
fi

# ---------------------------------------------------------------------------
# FAST 5: --dump-grid golden byte-match (four committed fixtures)
# ---------------------------------------------------------------------------
echo "== FAST: --dump-grid golden byte-match =="
for screen in fight dock map node; do
    if [ "$NIX_OK" -eq 1 ]; then
        if timeout 120 "$NIX" --dump-grid "$OUT/grid_$screen.txt" \
            --screen "$screen" >"$OUT/dump_grid_$screen.log" 2>&1; then
            if cmp -s "$OUT/grid_$screen.txt" "$FIXTURES/dump_grid_$screen.golden"; then
                pass_case "--dump-grid --screen $screen byte-identical to golden"
            else
                fail_case "--dump-grid --screen $screen differs from golden"
                diff -u "$FIXTURES/dump_grid_$screen.golden" \
                    "$OUT/grid_$screen.txt" 2>/dev/null | sed 's/^/       /'
            fi
        else
            fail_case "--dump-grid --screen $screen failed (see $OUT/dump_grid_$screen.log)"
        fi
    else
        fail_case "--dump-grid --screen $screen skipped (undtool.nix did not build)"
    fi
done
if [ -f "$OUT/grid_map.txt" ] \
    && grep -qF '[1-8] Z1-Z8  [9] Boss  [Esc] Back' "$OUT/grid_map.txt"; then
    pass_case "map golden carries the zone-ladder hint"
else
    fail_case "map golden hint missing"
fi

# ---------------------------------------------------------------------------
# FAST 6: --play native evidence (scripted key stream + exclusivity exit 2)
# ---------------------------------------------------------------------------
echo "== FAST: --play native evidence =="
if [ "$NIX_OK" -eq 1 ]; then
    printf 'tq' >"$OUT/play_keys.txt"
    timeout 120 "$NIX" --play <"$OUT/play_keys.txt" >"$OUT/play.log" 2>&1
    PLAY_RC=$?
    if [ "$PLAY_RC" -eq 0 ] \
        && grep -q 'UNDERSANDED  DOCK' "$OUT/play.log"; then
        pass_case "--play scripted tq reaches UNDERSANDED  DOCK (exit 0)"
    else
        fail_case "--play scripted tq failed (rc=$PLAY_RC; see $OUT/play.log)"
        sed 's/^/       /' "$OUT/play.log"
    fi
else
    fail_case "--play skipped (undtool.nix did not build)"
fi

expect_play_exit2() {
    label="$1"
    shift
    timeout 120 "$NIX" "$@" >"$OUT/play_neg.log" 2>&1 </dev/null
    rc=$?
    if [ "$rc" -eq 2 ]; then
        pass_case "undtool.nix exit 2: $label"
    else
        fail_case "undtool.nix exit 2: $label (rc=$rc)"
        sed 's/^/       /' "$OUT/play_neg.log"
    fi
}
if [ "$NIX_OK" -eq 1 ]; then
    expect_play_exit2 "--play --fight" --play --fight
    expect_play_exit2 "--play --sim" --play --sim 1
else
    fail_case "--play exit-2 paths skipped (undtool.nix did not build)"
fi

# ---------------------------------------------------------------------------
# SLOW: Wine evidence only (never the gate); never a silent skip.
# ---------------------------------------------------------------------------
echo "== SLOW: Wine evidence (never the gate) =="
UNDTOOL_EXE="${UNDTOOL_EXE:-}"
if [ -z "$UNDTOOL_EXE" ]; then
    for cand in "$UNDDIR/out/undtool.exe" "$UNDDIR/out/native/undtool.exe"; do
        if [ -f "$cand" ]; then
            UNDTOOL_EXE="$cand"
            break
        fi
    done
fi
if [ -z "$UNDTOOL_EXE" ]; then
    UNDTOOL_EXE="$(find "$UNDDIR" -maxdepth 4 -type f -name undtool.exe 2>/dev/null | head -n 1)"
fi
if ! command -v wine >/dev/null 2>&1; then
    skip_evidence "wine absent (native tier is the gate)"
elif [ -z "$UNDTOOL_EXE" ] || [ ! -f "$UNDTOOL_EXE" ]; then
    skip_evidence "undtool.exe not found under $UNDDIR (build it for Wine evidence)"
else
    WLOG="$OUT/wine_play.log"
    WINEPREFIX="$HOME/.wine_undersanded_m4_tier_$$"
    export WINEPREFIX
    rm -rf "$WINEPREFIX"
    if printf 'q' | timeout 180 wine "$UNDTOOL_EXE" --play >"$WLOG" 2>&1; then
        if grep -q 'UNDERSANDED  DOCK' "$WLOG"; then
            evidence_pass "wine undtool.exe --play reaches the dock screen"
        else
            evidence_fail "wine undtool.exe --play ran but dock screen missing"
        fi
    else
        evidence_fail "wine undtool.exe --play failed (see $WLOG)"
    fi
    rm -rf "$WINEPREFIX"
fi

echo
echo "== tier_m4_loop summary: $PASSES passed, $FAILS failed, $SKIPS evidence skips =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M4 FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "TIER_M4 PASS $PASSES passed / $FAILS failed"
exit 0
