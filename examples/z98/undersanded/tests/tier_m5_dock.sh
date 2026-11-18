#!/bin/sh
# tier_m5_dock.sh — UNDERSANDED M5 dock/economy acceptance tier
# (spec §10, §11, §16, §17, §21.5, §36 M5, §38 P22).
#
# FAST, native only (no Wine gate):
#   * build each M5 driver with -fsafe -W -osl + build_target.sh linux
#   * run economy_test, dock_test, tools_test, grudge_test, and the real-E0
#     economy_walk_test; every driver must exit 0, print its exact PASS line,
#     and print no FAIL line
#   * assert key case names by name (non-vacuous) and the walk's exact totals
#     (materials spent 111, Steel Fins 2, 49 dock phases)
#   * check tests/fixtures/economy_full.md exists and is the full projection,
#     not a stub
#   * nest tier_m4_loop.sh (M1->M4 regression) and require its PASS summary;
#     the nested tier also byte-matches the committed dock golden
#
# Env: ZIG  compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT  scratch dir (default /tmp/undersanded_m5_tier)
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# failure and prints `TIER_M5 PASS <n> passed / <m> failed`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m5_tier}"
TESTS="examples/z98/undersanded/tests"
FIXTURES="$SCRIPT_DIR/fixtures"
ECONOMY_FIXTURE="$FIXTURES/economy_full.md"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/seed151_build"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 0: economy fixture exists, is non-trivial, and carries the key totals
# ---------------------------------------------------------------------------
echo "== FAST: economy_full.md fixture =="
if [ ! -f "$ECONOMY_FIXTURE" ]; then
    fail_case "tests/fixtures/economy_full.md missing"
else
    pass_case "tests/fixtures/economy_full.md exists"
    FIX_BYTES="$(wc -c <"$ECONOMY_FIXTURE" | tr -d ' ')"
    if [ "$FIX_BYTES" -ge 1024 ]; then
        pass_case "economy_full.md is non-trivial ($FIX_BYTES bytes >= 1024)"
    else
        fail_case "economy_full.md too small ($FIX_BYTES bytes < 1024)"
    fi
    for marker in '111' '41 parts' '2,100' 'Deep sources per band'; do
        if grep -qF "$marker" "$ECONOMY_FIXTURE"; then
            pass_case "economy_full.md carries marker: $marker"
        else
            fail_case "economy_full.md missing marker: $marker"
        fi
    done
fi

# ---------------------------------------------------------------------------
# FAST 1: M5 unit drivers + real-E0 economy walk
# ---------------------------------------------------------------------------
echo "== FAST: M5 unit drivers =="
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

for t in economy_test dock_test tools_test grudge_test economy_walk_test; do
    run_driver "$t"
done

ECONOMY_LOG="$OUT/economy_test/run.log"
for c in yield_grid_7_materials_e0_e5 \
    gate_matrix_t2_t3_and_short_material \
    all_axis_tier_costs_exist_and_fit \
    material_totals_match_s17_111_steel_fins_2 \
    cosmetic_prices_total_2100; do
    require_case "$ECONOMY_LOG" "$c"
done

DOCK_LOG="$OUT/dock_test/run.log"
for c in refine_consumes_one_type upgrade_tier_order_totals \
    upgrade_keystone_from_hold start_fight_resets_pending_stun; do
    require_case "$DOCK_LOG" "$c"
done

TOOLS_LOG="$OUT/tools_test/run.log"
for c in plate_negates_armor_60_to_100 \
    coral_shield_electric_eel_discharge_zero \
    pressure_hook_blocks_flee electric_gland_stun_skips_one_action \
    equip_exp_tool_fallback_equips_charge \
    rigged_active_at_fight_start_no_charge \
    break_persists_and_clears_on_depart \
    peek_leaves_state_byte_identical speed_precision_loadout_applied; do
    require_case "$TOOLS_LOG" "$c"
done

GRUDGE_LOG="$OUT/grudge_test/run.log"
for c in grudge_res_raises_res_and_max grudge_persists_across_depart \
    run_reset_clears_mask grudge_armor_30_plate_100 \
    game_start_fight_applies_grudge; do
    require_case "$GRUDGE_LOG" "$c"
done

WALK_LOG="$OUT/economy_walk_test/run.log"
for c in real_e0_walk_spends_111_steel_fins_2 \
    walk_expertise_gates_enforced walk_s17_parts_e3_41_targets_111 \
    walk_cosmetics_total_2100; do
    require_case "$WALK_LOG" "$c"
done

echo "== FAST: real-E0 walk exact totals =="
if [ -f "$WALK_LOG" ]; then
    for exact in 'walk_total_materials_spent=111' 'walk_refines=34' \
        'walk_upgrades=15' 'walk_field_phases=49'; do
        if grep -qx "$exact" "$WALK_LOG"; then
            pass_case "economy_walk: $exact"
        else
            fail_case "economy_walk: $exact missing"
        fi
    done
    if grep -qx 'walk m=2 target=6 granted=4 produced=8 spent=6 left=2 exp=4' \
        "$WALK_LOG"; then
        pass_case "economy_walk: Steel Plate reaches E4 without extra batch"
    else
        fail_case "economy_walk: Steel Plate per-material line missing"
    fi
else
    fail_case "economy_walk run log missing (driver build failed)"
fi

# ---------------------------------------------------------------------------
# FAST 2: nested M1->M4 regression gate
# ---------------------------------------------------------------------------
echo "== FAST: M4 regression (tier_m4_loop.sh) =="
M4LOG="$OUT/tier_m4_loop.log"
if ZIG="$ZIG" OUT="$OUT/m4" sh "$TESTS/tier_m4_loop.sh" >"$M4LOG" 2>&1; then
    pass_case "tier_m4_loop.sh green (M1->M4 + dock goldens)"
else
    fail_case "tier_m4_loop.sh failed (see $M4LOG)"
fi
tail -8 "$M4LOG" | sed 's/^/       /'
if grep -q '^TIER_M4 PASS ' "$M4LOG" && ! grep -q '^TIER_M4 FAIL ' "$M4LOG"; then
    pass_case "tier_m4_loop summary PASS"
else
    fail_case "tier_m4_loop summary missing/FAIL"
fi
if grep -qF 'ok   - --dump-grid --screen dock byte-identical to golden' "$M4LOG"; then
    pass_case "nested M4 dock golden byte-identical"
else
    fail_case "nested M4 dock golden missing/failed"
fi
if grep -q '^FAIL - ' "$M4LOG"; then
    fail_case "tier_m4_loop reported a FAIL line"
else
    pass_case "tier_m4_loop reports no FAIL - lines"
fi

echo
echo "== tier_m5_dock summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M5 FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "TIER_M5 PASS $PASSES passed / $FAILS failed"
exit 0
