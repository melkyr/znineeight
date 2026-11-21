#!/bin/sh
# tier_m11_boss.sh — UNDERSANDED M11 boss + score DEMO GATE
# (spec §15, §19, §30, §34, §38 P31).
#
# FAST, native only (no Wine/X11):
#   * build/run the M11 drivers (boss_test, score_test, boat_test, art_test,
#     m11_demo_test and the regression drivers expedition/nav/screens/help)
#     with -fsafe -W -osl + build_target.sh linux; assert exact PASS lines,
#     rc 0, no `FAIL - ` line, and the named M11 cases
#   * build undtool_native.zig and byte-compare the score, credits and boat
#     dump screens with their committed goldens; a mutated copy must fail the
#     same cmp (non-vacuity)
#   * five saved boat builds use the real persist.saveWrite/saveRead path in
#     separate files under $OUT/saves and assert Armor/Sliver/Hoard/Drown/Blur
#     Phase-2 identities survive the round trip
#   * the full demo-loop trace (fresh GameState -> D-route depart -> boss
#     defeat -> credits -> score -> dock with normal return travel, both Kill
#     and Overkill) is byte-identical to fixtures/demo_loop.golden
#   * Field Record once, variants bit survival, LastRun rows, gate/telegraph
#     and both defeat-outcome bookkeeping are pinned by name
#   * P19: no committed scripting-runtime/converter file under the example and
#     no scripting-runtime invocation in this tier
#   * nest tier_m101_ux.sh (which nests TIER_M10 -> ... -> M1) and require its
#     PASS plus the nested TIER_M10 PASS
#
# Env: ZIG       compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT       scratch dir (default /tmp/undersanded_m11_boss_tier)
#      M101_TIER nested M10.1 tier path override
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# failure and prints `TIER_M11 PASS <n> passed / <m> failed`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m11_boss_tier}"
TESTS="examples/z98/undersanded/tests"
FIXTURES="$UNDDIR/tests/fixtures"
DEMO_GOLDEN="$FIXTURES/demo_loop.golden"
M101_TIER="${M101_TIER:-$SCRIPT_DIR/tier_m101_ux.sh}"
DUMPS="score credits boat"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
indent() { while IFS= read -r line; do printf '       %s\n' "$line"; done; }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/seed151_build"
    exit 1
fi
if [ ! -f "$DEMO_GOLDEN" ] || [ ! -f "$M101_TIER" ]; then
    echo "FAIL: M11 input missing ($DEMO_GOLDEN, $M101_TIER)"
    exit 1
fi
for s in $DUMPS; do
    if [ ! -f "$FIXTURES/dump_grid_$s.golden" ]; then
        echo "FAIL: M11 dump golden missing: $FIXTURES/dump_grid_$s.golden"
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT/saves"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 1: M11 drivers (-fsafe -W clean, PASS, rc 0, no FAIL line)
# ---------------------------------------------------------------------------
echo "== FAST: M11 drivers =="
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
    if [ "$t" = "m11_demo_test" ]; then
        M11_SAVE_DIR="$OUT/saves" timeout 240 "$td/$t" >"$td/run.log" 2>&1
    else
        timeout 240 "$td/$t" >"$td/run.log" 2>&1
    fi
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

for t in boss_test score_test boat_test art_test m11_demo_test \
    expedition_test nav_test screens_test help_test; do
    run_driver "$t"
done

BOSS_LOG="$OUT/boss_test/run.log"
for c in variant_selection variant_matrix_all_boats phase_boundaries_200_100 \
    speed_attack_bands volley_cadence_plate armor_variant sliver_variant \
    hoard_variant drown_variant blur_variant restrain_rejected \
    subdue_rejected kill_bookkeeping overkill_bookkeeping; do
    require_case "$BOSS_LOG" "$c"
done

SCORE_LOG="$OUT/score_test/run.log"
for c in score_copy_exact credits_copy_exact score_golden_exact \
    credits_golden_exact score_help_and_allow_lists field_record_freeze_once \
    variants_bit_survives_ascent last_run_overwrites kill_defeat_route \
    overkill_defeat_route field_record_second_defeat_identical \
    boss_loss_records_last_run nonboss_score_counters \
    sell_updates_money_earned; do
    require_case "$SCORE_LOG" "$c"
done

BOAT_LOG="$OUT/boat_test/run.log"
for c in assets_load boat_overlay_boss_accessors boat_paint_lut_pinned \
    boat_paint_clip_bbox cosmetic_highest_owned_selection \
    cosmetic_highest_owned_render overlay_anchors_and_blit_order \
    score_art_draws_boat dump_grid_boat_golden \
    boat_art_checksum_pre_present; do
    require_case "$BOAT_LOG" "$c"
done

ART_LOG="$OUT/art_test/run.log"
for c in assets_manifest_decode_26a_12v background_one_resident_slot \
    assets_missing_fallback_deterministic assets_malformed_v_manifest_falls_back \
    score_credits_art_deterministic golden_art_fight_640x480; do
    require_case "$ART_LOG" "$c"
done

DEMO_LOG="$OUT/m11_demo_test/run.log"
for c in saved_boat_armor_identity saved_boat_sliver_identity \
    saved_boat_hoard_identity saved_boat_drown_identity \
    saved_boat_blur_identity demo_loop_kill demo_loop_overkill; do
    require_case "$DEMO_LOG" "$c"
done

EXP_LOG="$OUT/expedition_test/run.log"
for c in heavy_plus_one_each_way_cost_ge_3 boss_hunt_selects_start_boss \
    boss_hunt_defensive_gate boss_one_fight_cap_and_respawn \
    normal_hunt_not_boss; do
    require_case "$EXP_LOG" "$c"
done

NAV_LOG="$OUT/nav_test/run.log"
for c in policy_subdue_release_surface_dock locked_boss_stays_map \
    hull_zero_ascent_returns_dock dock_menu_keys_and_esc; do
    require_case "$NAV_LOG" "$c"
done

SCREENS_LOG="$OUT/screens_test/run.log"
for c in map_screen_ladder_locked_boss map_boss_gate_six_distinct_nonboss \
    node_screen_key_lines node_boss_telegraph map_heavy_cost_cycle \
    render_no_rng_no_phase; do
    require_case "$SCREENS_LOG" "$c"
done

HELP_LOG="$OUT/help_test/run.log"
for c in help_page_map footer_help_every_screen help_no_rng_no_phase_every_screen \
    cosmetic_lock_copy_buy; do
    require_case "$HELP_LOG" "$c"
done

# ---------------------------------------------------------------------------
# FAST 2: full demo-loop trace golden (fresh -> boss defeat -> credits ->
# score -> dock; both Kill and Overkill; normal return travel)
# ---------------------------------------------------------------------------
echo "== FAST: M11 demo-loop golden =="
if [ -f "$DEMO_LOG" ] && cmp -s "$DEMO_LOG" "$DEMO_GOLDEN"; then
    pass_case "demo loop trace byte-identical to demo_loop.golden"
else
    fail_case "demo loop trace differs from demo_loop.golden"
    diff -u "$DEMO_GOLDEN" "$DEMO_LOG" 2>/dev/null | indent
fi
if [ -f "$DEMO_LOG" ] && grep -qx 'demo kill outbound=7 return=6 actions=19 hull_spent=191 outcome=Kill identity=The Armor variants=1 boss_kills=1 field=1 score=1/0' "$DEMO_LOG"; then
    pass_case "Kill loop pins Kill bookkeeping and return travel"
else
    fail_case "Kill loop row missing/changed"
fi
if [ -f "$DEMO_LOG" ] && grep -qx 'demo overkill outbound=7 return=6 actions=19 hull_spent=191 outcome=Overkill identity=The Armor variants=1 boss_kills=1 field=1 score=0/1' "$DEMO_LOG"; then
    pass_case "Overkill loop pins Overkill bookkeeping and return travel"
else
    fail_case "Overkill loop row missing/changed"
fi

# ---------------------------------------------------------------------------
# FAST 3: native undtool + score/credits/boat dump goldens
# ---------------------------------------------------------------------------
echo "== FAST: native undtool + M11 dump goldens =="
NATIVE="$OUT/native"
mkdir -p "$NATIVE"
NATIVE="$(cd "$NATIVE" && pwd)"
NIX="$NATIVE/undtool.nix"
NIX_OK=0
if "$ZIG" -fsafe -W -osl --output-dir "$NATIVE" \
    examples/z98/undersanded/undtool_native.zig >"$OUT/undtool_compile.log" 2>&1; then
    pass_case "undtool_native.zig -fsafe -W compile clean"
    if sh "$NATIVE/build_target.sh" linux "$NIX" >"$OUT/undtool_link.log" 2>&1; then
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

dump_one() {
    s="$1"
    GOLDEN="$FIXTURES/dump_grid_$s.golden"
    DUMP="$OUT/dump_grid_$s.txt"
    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$DUMP" --screen "$s" ) \
        >"$OUT/dump_grid_$s.err" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ] && cmp -s "$DUMP" "$GOLDEN"; then
        pass_case "--dump-grid --screen $s byte-identical to M11 golden"
    else
        fail_case "--dump-grid --screen $s differs from M11 golden (rc=$rc)"
        diff -u "$GOLDEN" "$DUMP" 2>/dev/null | indent
    fi
}

if [ "$NIX_OK" -eq 1 ]; then
    for s in $DUMPS; do
        dump_one "$s"
    done
    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$OUT/score2.txt" --screen score ) \
        >"$OUT/score2.err" 2>&1
    if cmp -s "$OUT/dump_grid_score.txt" "$OUT/score2.txt"; then
        pass_case "--dump-grid --screen score rerun is byte-identical"
    else
        fail_case "--dump-grid --screen score rerun differs"
    fi
else
    for s in $DUMPS; do
        fail_case "--dump-grid --screen $s byte-identical to M11 golden (undtool.nix did not build)"
    done
    fail_case "--dump-grid --screen score rerun is byte-identical (undtool.nix did not build)"
fi

# Non-vacuity: mutate a COPY of the demo golden and prove the same cmp rejects
# it. Never touch the committed fixture.
MUT_GOLDEN="$OUT/demo_loop.mutated.golden"
cp "$DEMO_GOLDEN" "$MUT_GOLDEN"
printf 'X\n' >>"$MUT_GOLDEN"
if cmp -s "$MUT_GOLDEN" "$DEMO_GOLDEN"; then
    fail_case "non-vacuity: mutation did not change the demo golden copy"
else
    pass_case "non-vacuity: mutated demo golden copy differs from fixture"
fi
if [ -f "$DEMO_LOG" ] && cmp -s "$DEMO_LOG" "$MUT_GOLDEN"; then
    fail_case "non-vacuity: same cmp accepted the mutated demo golden"
else
    pass_case "non-vacuity: same cmp rejects the mutated demo golden"
fi
if cmp -s "$DEMO_LOG" "$DEMO_GOLDEN"; then
    pass_case "committed demo golden unchanged after non-vacuity mutation"
else
    fail_case "committed demo golden was disturbed by non-vacuity mutation"
fi
rm -f "$MUT_GOLDEN"

# ---------------------------------------------------------------------------
# FAST 4: P19 no committed scripting runtime/converter + no invocation here
# ---------------------------------------------------------------------------
echo "== FAST: P19 no scripting runtime/converter =="
PY_FILES="$(find "$UNDDIR" -type f -name '*.py' -print)"
if [ -z "$PY_FILES" ]; then
    pass_case "no committed scripting-runtime source under examples/z98/undersanded"
else
    fail_case "committed scripting-runtime source under examples/z98/undersanded"
    printf '%s\n' "$PY_FILES" | indent
fi
CONV_FILES="$(find "$UNDDIR" -type f \
    \( -name '*convert*' -o -name '*raster*' -o -name '*svg2*' \) -print)"
if [ -z "$CONV_FILES" ]; then
    pass_case "no committed SVG/converter tooling under examples/z98/undersanded"
else
    fail_case "committed SVG/converter tooling under examples/z98/undersanded"
    printf '%s\n' "$CONV_FILES" | indent
fi
PY_CMD="py""thon"
if grep -q "$PY_CMD" "$0"; then
    fail_case "tier invokes/mentions the scripting runtime"
else
    pass_case "tier has no scripting-runtime invocation"
fi

# ---------------------------------------------------------------------------
# FAST 5: nested M10.1 -> M10 -> ... -> M1 regression gate
# ---------------------------------------------------------------------------
echo "== FAST: M10.1 regression (tier_m101_ux.sh) =="
M101LOG="$OUT/tier_m101.log"
if ZIG="$ZIG" OUT="$OUT/m101" FIXTURES="$FIXTURES" sh "$M101_TIER" \
    >"$M101LOG" 2>&1; then
    pass_case "tier_m101_ux.sh green (M10.1 + M10 -> M1)"
else
    fail_case "tier_m101_ux.sh failed (see $M101LOG)"
fi
tail -8 "$M101LOG" | indent
if grep -q '^TIER_M10\.1 PASS ' "$M101LOG" && ! grep -q '^TIER_M10\.1 FAIL ' "$M101LOG"; then
    pass_case "tier_m101_ux summary PASS"
else
    fail_case "tier_m101_ux summary missing/FAIL"
fi
M10LOG="$OUT/m101/tier_m10.log"
if [ -f "$M10LOG" ] && grep -q '^TIER_M10 PASS ' "$M10LOG" \
    && ! grep -q '^TIER_M10 FAIL ' "$M10LOG"; then
    pass_case "nested tier_m10_assets summary PASS"
else
    fail_case "nested tier_m10_assets summary missing/FAIL"
fi
if grep -q '^FAIL - ' "$M101LOG"; then
    fail_case "tier_m101_ux reported a FAIL line"
else
    pass_case "tier_m101_ux reports no failing-case lines"
fi
if [ -f "$M10LOG" ] && grep -q '^FAIL - ' "$M10LOG"; then
    fail_case "nested tier_m10_assets reported a FAIL line"
else
    pass_case "nested tier_m10_assets reports no failing-case lines"
fi

echo
echo "== tier_m11_boss summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M11 FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "TIER_M11 PASS $PASSES passed / $FAILS failed"
exit 0
