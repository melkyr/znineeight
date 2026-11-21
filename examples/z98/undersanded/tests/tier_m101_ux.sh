#!/bin/sh
# tier_m101_ux.sh — UNDERSANDED M10.1 UX acceptance gate
# (spec §7.1, §9.3, §9.7, §18, §27, §28, §36, §38 P30).
#
# FAST, native only (no Wine gate):
#   * build/run the M10.1 UX drivers (ux_test, nav_test, screens_test,
#     help_test, expedition_test, save_ux_test, journal_test) with
#     -fsafe -W -osl + build_target.sh linux; assert exact PASS lines, rc 0,
#     no `FAIL - ` line, and the named M10.1 cases
#   * build undtool_native.zig and byte-compare every committed UX golden:
#     dock/map/node/subdue/settle (settle keys 1/2), lore/help/journal
#     (page map/pages 1-9), menu and fight; conditions match M7-M9 (data.z98
#     beside the tool for lore/help only)
#   * require `--dump-grid --screen subdue|settle` rc 0 and an unknown screen
#     rc 2; a mutated COPY of the settle golden must fail the same cmp while
#     the committed fixture stays byte-identical (non-vacuity)
#   * build the real product with build.sh and verify the under.exe path
#     structurally: GUI PE32, import gate, staged assets/data/sample, and the
#     boot/UX copy compiled into the binary (non-GUI smoke; Wine is not a gate)
#   * P19: no committed scripting-runtime or SVG/converter file under the
#     example and no scripting-runtime invocation in this tier
#   * quality_smells.sh green; README carries the M10.1 settle/status/help copy
#   * nest tier_m10_assets.sh as the regression gate and require TIER_M10 PASS
#
# Env: ZIG      compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT      scratch dir (default /tmp/undersanded_m101_ux_tier)
#      M10_TIER nested M10 tier path override
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# failure and prints `TIER_M10.1 PASS <n> passed / <m> failed`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m101_ux_tier}"
TESTS="examples/z98/undersanded/tests"
FIXTURES="$UNDDIR/tests/fixtures"
DATA="$UNDDIR/data.z98"
README="$UNDDIR/README.md"
BUILD_SH="$UNDDIR/build.sh"
IMPORT_GATE="$ROOT/scripts/win32_cross/check_win9x_imports.sh"
M10_TIER="${M10_TIER:-$SCRIPT_DIR/tier_m10_assets.sh}"
UX_SCREENS="dock map node subdue settle lore menu help journal fight"

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
if [ ! -f "$DATA" ] || [ ! -f "$README" ] || [ ! -f "$BUILD_SH" ] \
    || [ ! -f "$M10_TIER" ]; then
    echo "FAIL: M10.1 input missing ($DATA, $README, $BUILD_SH, $M10_TIER)"
    exit 1
fi
for s in $UX_SCREENS; do
    if [ ! -f "$FIXTURES/dump_grid_$s.golden" ]; then
        echo "FAIL: M10.1 UX golden missing: $FIXTURES/dump_grid_$s.golden"
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 1: M10.1 UX drivers (-fsafe -W clean, PASS, rc 0, no FAIL line)
# ---------------------------------------------------------------------------
echo "== FAST: M10.1 UX drivers =="
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

for t in ux_test nav_test screens_test help_test expedition_test \
    save_ux_test journal_test; do
    run_driver "$t"
done

UX_LOG="$OUT/ux_test/run.log"
for c in init_state_zeroes_every_field field_msg_cleared_on_next_key \
    nav_result_line_prefers_field_msg field_msg_does_not_change_phase_or_rng \
    subdue_intro_before_settle settle_ignores_r_and_s settle_1_releases_2_sells \
    subdue_intro_no_rng_no_phase event_depart_status event_kill_status \
    event_boss_locked_status status_clears_next_key release_sell_result_line \
    wary_log_at_fight_start grudge_log_at_fight_start; do
    require_case "$UX_LOG" "$c"
done

NAV_LOG="$OUT/nav_test/run.log"
for c in dock_refine_result_names_amount \
    dock_refine_zero_yield_explanation dock_upgrade_result_names_axis_tier \
    dock_craft_result_names_tool dock_buy_result_and_locked_condition \
    dock_select_tool_result rare_batch_different_digit_cancels; do
    require_case "$NAV_LOG" "$c"
done

SCREENS_LOG="$OUT/screens_test/run.log"
for c in subdue_intro_copy settle_copy_names_creature_and_effects \
    dock_golden_exact map_golden_exact node_golden_exact subdue_golden_exact \
    settle_golden_exact node_rare_lockout_pool map_heavy_cost_cycle \
    render_no_rng_no_phase; do
    require_case "$SCREENS_LOG" "$c"
done

HELP_LOG="$OUT/help_test/run.log"
for c in help_page_map help_pages_present manual_copy_s7_1 \
    help_screen_render_deterministic footer_help_every_screen \
    journal_hint_dock_field tool_effect_copy_craft_and_tools \
    axis_effect_copy_upgrade cosmetic_lock_copy_buy; do
    require_case "$HELP_LOG" "$c"
done

EXP_LOG="$OUT/expedition_test/run.log"
for c in field_action_clears_stale_secured settlement_choice_keeps_secured \
    secured_awards_exactly_once wariness_plus_15_then_cleared \
    rest_heal_phase_clamp_condition; do
    require_case "$EXP_LOG" "$c"
done

SAVE_LOG="$OUT/save_ux_test/run.log"
for c in nav_intercept_save_and_quit_copy boot_fresh_confirm_cancel_erase \
    lore_wrap_no_clip boot_routing_and_keys boot_continue_loads_slot \
    boot_bad_version_fresh; do
    require_case "$SAVE_LOG" "$c"
done

JOURNAL_LOG="$OUT/journal_test/run.log"
for c in help_page_map content_text_keys speed_reveal_survives_save \
    journal_trigger_matrix; do
    require_case "$JOURNAL_LOG" "$c"
done

# ---------------------------------------------------------------------------
# FAST 2: native undtool + every M10.1 UX golden byte-compare
# ---------------------------------------------------------------------------
echo "== FAST: native undtool + M10.1 UX goldens =="
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
        pass_case "--dump-grid --screen $s byte-identical to M10.1 golden"
    else
        fail_case "--dump-grid --screen $s differs from M10.1 golden (rc=$rc)"
        diff -u "$GOLDEN" "$DUMP" 2>/dev/null | indent
    fi
}

if [ "$NIX_OK" -eq 1 ]; then
    # Authored conditions: lore/help read data.z98 beside the tool; the fixed
    # dock/map/node/subdue/settle/menu/journal/fight frames use the compiled
    # fallback, exactly as the M7-M9 gates did.
    cp "$DATA" "$NATIVE/data.z98"
    dump_one lore
    dump_one help
    rm -f "$NATIVE/data.z98"
    if [ ! -f "$NATIVE/data.z98" ]; then
        pass_case "data.z98 removed beside the tool for the fixed-screen goldens"
    else
        fail_case "could not remove data.z98 beside the tool"
    fi
    for s in dock map node subdue settle menu journal fight; do
        dump_one "$s"
    done

    # Settle rerun determinism (new M10.1 state).
    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$OUT/settle2.txt" --screen settle ) \
        >"$OUT/settle2.err" 2>&1
    if cmp -s "$OUT/dump_grid_settle.txt" "$OUT/settle2.txt"; then
        pass_case "--dump-grid --screen settle rerun is byte-identical"
    else
        fail_case "--dump-grid --screen settle rerun differs"
    fi

    # Real tool path: both new screens rc 0, an unknown screen rc 2.
    timeout 120 "$NIX" --dump-grid "$OUT/real_subdue.txt" --screen subdue \
        >"$OUT/real_subdue.log" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass_case "undtool.nix --dump-grid subdue rc 0"
    else
        fail_case "undtool.nix --dump-grid subdue rc $rc (want 0)"
        indent <"$OUT/real_subdue.log"
    fi
    timeout 120 "$NIX" --dump-grid "$OUT/real_settle.txt" --screen settle \
        >"$OUT/real_settle.log" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass_case "undtool.nix --dump-grid settle rc 0"
    else
        fail_case "undtool.nix --dump-grid settle rc $rc (want 0)"
        indent <"$OUT/real_settle.log"
    fi
    timeout 120 "$NIX" --dump-grid "$OUT/unknown.txt" --screen not_a_screen \
        >"$OUT/unknown.log" 2>&1
    rc=$?
    if [ "$rc" -eq 2 ] && grep -q 'unknown --screen id' "$OUT/unknown.log"; then
        pass_case "undtool.nix unknown --screen exits 2 with a diagnostic"
    else
        fail_case "undtool.nix unknown --screen did not exit 2 (rc=$rc)"
        indent <"$OUT/unknown.log"
    fi

    # Non-vacuity: mutate a COPY of the settle golden and prove the same cmp
    # rejects it. Never touch the committed fixture.
    MUT_GOLDEN="$OUT/dump_grid_settle.mutated.golden"
    cp "$FIXTURES/dump_grid_settle.golden" "$MUT_GOLDEN"
    printf 'X' >>"$MUT_GOLDEN"
    if cmp -s "$MUT_GOLDEN" "$FIXTURES/dump_grid_settle.golden"; then
        fail_case "non-vacuity: mutation did not change the settle golden copy"
    else
        pass_case "non-vacuity: mutated settle golden copy differs from fixture"
    fi
    if cmp -s "$OUT/dump_grid_settle.txt" "$MUT_GOLDEN"; then
        fail_case "non-vacuity: same cmp accepted the mutated settle golden"
    else
        pass_case "non-vacuity: same cmp rejects the mutated settle golden"
    fi
    rm -f "$MUT_GOLDEN"
    if cmp -s "$OUT/dump_grid_settle.txt" "$FIXTURES/dump_grid_settle.golden"; then
        pass_case "committed settle golden unchanged after non-vacuity mutation"
    else
        fail_case "committed settle golden was disturbed by non-vacuity mutation"
    fi
else
    for s in $UX_SCREENS; do
        fail_case "--dump-grid --screen $s byte-identical to M10.1 golden (undtool.nix did not build)"
    done
    fail_case "--dump-grid --screen settle rerun is byte-identical (undtool.nix did not build)"
    fail_case "undtool.nix --dump-grid subdue rc 0 (undtool.nix did not build)"
    fail_case "undtool.nix --dump-grid settle rc 0 (undtool.nix did not build)"
    fail_case "undtool.nix unknown --screen exits 2 (undtool.nix did not build)"
    fail_case "non-vacuity: mutated settle golden rejected (undtool.nix did not build)"
fi

# ---------------------------------------------------------------------------
# FAST 3: real product under.exe path, structurally (no Wine gate)
# ---------------------------------------------------------------------------
echo "== FAST: under.exe product path (structural) =="
UNDERB="$OUT/under_build"
if ZIG="$ZIG" OUT="$UNDERB" sh "$BUILD_SH" >"$OUT/build.log" 2>&1; then
    pass_case "build.sh green (under.exe + undtool.exe + staged content)"
else
    fail_case "build.sh failed (see $OUT/build.log)"
    tail -20 "$OUT/build.log" | indent
fi

UNDER="$UNDERB/under.exe"
if [ -f "$UNDER" ]; then
    pass_case "under.exe built"
else
    fail_case "under.exe missing (build failed)"
fi
if [ -f "$UNDERB/assets/assets.man" ] && [ -f "$UNDERB/assets/out/bg_a.zsp" ]; then
    pass_case "assets staged beside under.exe (assets.man + .zsp)"
else
    fail_case "assets not staged beside under.exe"
fi
if [ -f "$UNDERB/data.z98" ] && [ -f "$UNDERB/sample.txt" ]; then
    pass_case "data.z98 + sample.txt staged beside under.exe"
else
    fail_case "data.z98/sample.txt not staged beside under.exe"
fi

if [ -f "$UNDER" ]; then
    if file "$UNDER" | grep -q 'PE32 executable (GUI).*Intel 80386'; then
        pass_case "under.exe is a PE32 GUI i386 image"
    else
        fail_case "under.exe is not a PE32 GUI i386 image"
        file "$UNDER" | indent
    fi
    if [ -f "$IMPORT_GATE" ] \
        && sh "$IMPORT_GATE" "$UNDER" 9x >"$OUT/under_imports.log" 2>&1; then
        pass_case "under.exe passes the Win9x import gate"
    else
        fail_case "under.exe failed the Win9x import gate (see $OUT/under_imports.log)"
        tail -12 "$OUT/under_imports.log" 2>/dev/null | indent
    fi

    # Non-GUI boot/UX smoke: the real under.exe image carries the shared boot
    # and M10.1 copy. This is structural, so Wine is never a gate.
    for marker in 'UNDERSANDED  LORE' 'UNDERSANDED  MAIN MENU' \
        'Erase this save?' 'UNDERSANDED  SETTLE' 'SUBDUED' '[C]ontinue' \
        '[1] Release' '[2] Sell' '[?] Help' '[J]ournal' 'Departed to' \
        'Rare chance:'; do
        if grep -aqF "$marker" "$UNDER"; then
            pass_case "under.exe carries boot/UX marker: $marker"
        else
            fail_case "under.exe missing boot/UX marker: $marker"
        fi
    done
    if grep -qF 'manual.9=' "$UNDERB/data.z98" 2>/dev/null; then
        pass_case "staged data.z98 includes manual.9 (Journal & Speed)"
    else
        fail_case "staged data.z98 is missing manual.9"
    fi
else
    fail_case "under.exe PE32 GUI check (build failed)"
    fail_case "under.exe Win9x import gate (build failed)"
    fail_case "under.exe boot/UX markers (build failed)"
    fail_case "staged data.z98 manual.9 (build failed)"
fi

# ---------------------------------------------------------------------------
# FAST 4: README M10.1 key/status/help copy
# ---------------------------------------------------------------------------
echo "== FAST: README M10.1 copy =="
for marker in '[C]ontinue' '[1] Release' '[2] Sell' 'status line' \
    '[?] Help' '[J]ournal'; do
    if grep -qF "$marker" "$README"; then
        pass_case "README carries M10.1 copy: $marker"
    else
        fail_case "README missing M10.1 copy: $marker"
    fi
done
if grep -qF '[R]elease' "$README"; then
    fail_case "README still documents the retired [R]elease key"
else
    pass_case "README no longer documents the retired [R]elease key"
fi
if grep -qF '[S]ell' "$README"; then
    fail_case "README still documents the retired [S]ell key"
else
    pass_case "README no longer documents the retired [S]ell key"
fi

# ---------------------------------------------------------------------------
# FAST 5: P19 no committed scripting runtime/converter + no invocation here
# ---------------------------------------------------------------------------
echo "== FAST: P19 no scripting runtime/converter =="
PY_FILES="$(find "$UNDDIR" -type f -name '*.py' -print)"
if [ -z "$PY_FILES" ]; then
    pass_case "no committed scripting-runtime source under examples/z98/undersanded"
else
    fail_case "committed scripting-runtime source under examples/z98/undersanded"
    printf '%s\n' "$PY_FILES" | indent
fi
PYC_FILES="$(find "$UNDDIR" -type f -name '*.pyc' -print)"
if [ -z "$PYC_FILES" ]; then
    pass_case "no committed scripting-runtime bytecode under examples/z98/undersanded"
else
    fail_case "committed scripting-runtime bytecode under examples/z98/undersanded"
    printf '%s\n' "$PYC_FILES" | indent
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
# FAST 6: mechanical owner/registry quality smells
# ---------------------------------------------------------------------------
echo "== FAST: quality smells =="
SMELLS_LOG="$OUT/quality_smells.log"
if sh "$TESTS/quality_smells.sh" >"$SMELLS_LOG" 2>&1; then
    pass_case "quality_smells.sh green"
else
    fail_case "quality_smells.sh failed (see $SMELLS_LOG)"
fi
tail -8 "$SMELLS_LOG" | indent
if grep -q '^QUALITY_SMELLS PASS ' "$SMELLS_LOG" \
    && ! grep -q '^QUALITY_SMELLS FAIL ' "$SMELLS_LOG"; then
    pass_case "quality_smells summary PASS"
else
    fail_case "quality_smells summary missing/FAIL"
fi

# ---------------------------------------------------------------------------
# FAST 7: nested M10 assets/pixel regression gate
# ---------------------------------------------------------------------------
echo "== FAST: M10 regression (tier_m10_assets.sh) =="
M10LOG="$OUT/tier_m10.log"
if ZIG="$ZIG" OUT="$OUT/m10" FIXTURES="$FIXTURES" sh "$M10_TIER" \
    >"$M10LOG" 2>&1; then
    pass_case "tier_m10_assets.sh green (M10 assets + M9 -> M1)"
else
    fail_case "tier_m10_assets.sh failed (see $M10LOG)"
fi
tail -8 "$M10LOG" | indent
if grep -q '^TIER_M10 PASS ' "$M10LOG" && ! grep -q '^TIER_M10 FAIL ' "$M10LOG"; then
    pass_case "tier_m10_assets summary PASS"
else
    fail_case "tier_m10_assets summary missing/FAIL"
fi
if grep -q '^FAIL - ' "$M10LOG"; then
    fail_case "tier_m10_assets reported a FAIL line"
else
    pass_case "tier_m10_assets reports no failing-case lines"
fi

echo
echo "== tier_m101_ux summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M10.1 FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "TIER_M10.1 PASS $PASSES passed / $FAILS failed"
exit 0
