#!/bin/sh
# tier_m7_save.sh — UNDERSANDED M7 save-system acceptance tier
# (spec §20, §32, §33, §36 M7, §38 P25).
#
# FAST, native only (no Wine gate):
#   * build/run persist_test, save_ux_test, nav_test, screens_test with
#     -fsafe -W -osl + build_target.sh linux; assert exact PASS lines and key
#     case names, including the persist rollback-injection cases
#   * build undtool_native.zig; byte-match the committed lore + menu
#     --dump-grid goldens with data.z98 beside the tool, then remove it
#   * build tests/boot_walk.zig and drive the REAL nav.boot path with stdin keys:
#     fresh install -> page 1 -> dock + save0.dat, no menu; second boot -> menu
#     -> Continue -> dock; version=1 fixture -> save-error screen -> Q exits
#   * create the roundtrip golden from the boot-walk save and prove
#     `--save-roundtrip` exits 0, leaves the original byte-identical, removes
#     its temp file, installs no content, and exits 2 on bad input
#   * nest tier_m6_data.sh (which nests M5 -> M4 -> ...) and require its PASS
#
# Env: ZIG       compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT       scratch dir (default /tmp/undersanded_m7_tier)
#      FIXTURES  fixture dir override (default tests/fixtures; used to prove
#                non-vacuity with a mutated /tmp copy)
#      M6_TIER   nested M6 tier path override (to prove failure propagation)
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# failure and prints `TIER_M7 PASS <n> passed / <m> failed`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m7_tier}"
TESTS="examples/z98/undersanded/tests"
FIXTURES="${FIXTURES:-$SCRIPT_DIR/fixtures}"
M6_TIER="${M6_TIER:-$TESTS/tier_m6_data.sh}"
DATA="$ROOT/examples/z98/undersanded/data.z98"
LORE_GOLDEN="$FIXTURES/dump_grid_lore.golden"
MENU_GOLDEN="$FIXTURES/dump_grid_menu.golden"
V1_FIXTURE="$FIXTURES/save_v1_bad.sav"
V2_FIXTURE="$FIXTURES/save_v2_valid.sav"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/seed151_build"
    exit 1
fi
if [ ! -f "$DATA" ] || [ ! -f "$LORE_GOLDEN" ] || [ ! -f "$MENU_GOLDEN" ] \
    || [ ! -f "$V1_FIXTURE" ] || [ ! -f "$V2_FIXTURE" ]; then
    echo "FAIL: M7 fixture missing ($DATA, $LORE_GOLDEN, $MENU_GOLDEN, $V1_FIXTURE, $V2_FIXTURE)"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 1: M7 unit drivers (-fsafe -W clean, PASS, exit 0, no FAIL line)
# ---------------------------------------------------------------------------
echo "== FAST: M7 unit drivers =="
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

for t in persist_test save_ux_test nav_test screens_test; do
    run_driver "$t"
done

PERSIST_LOG="$OUT/persist_test/run.log"
for c in round_trip_byte_compare crc_tamper_bad_hash version_one_bad_version \
    data_version_one_bad_data_version unknown_cooldown_id_bad_id \
    failed_load_leaves_target_untouched ready_672_worst_case_line \
    pending_settlement_not_saved happy_path_saves_save0_and_bak \
    second_save_with_preexisting_bak step5_failure_rolls_back_save0 \
    step3_verify_failure_aborts_untouched startup_recovery_restores_and_logs \
    startup_recovery_deletes_stale_tmp startup_recovery_precedes_fresh_install \
    backup_slot_writes_save1_manually fixture_v2_canonical_resave \
    crafted_crc_valid_rejected options_unknown_keys_skipped \
    trailing_content_after_crc_rejected over_max_line_rejected \
    failed_load_all_classes_untouched recovery_no_trailing_separator \
    log_error_no_trailing_separator backup_slot_no_trailing_separator; do
    require_case "$PERSIST_LOG" "$c"
done
if [ -f "$PERSIST_LOG" ] \
    && grep -qx 'ok - step5_failure_rolls_back_save0' "$PERSIST_LOG" \
    && grep -qx 'ok - step3_verify_failure_aborts_untouched' "$PERSIST_LOG"; then
    pass_case "persist rollback injection ran (step5 + step3)"
else
    fail_case "persist rollback injection did not run"
fi

SAVE_UX_LOG="$OUT/save_ux_test/run.log"
for c in canSave_matrix quit_prompt_text options_cfg_save_slot \
    save_error_screen_version_one first_run_golden manual_fallback_line \
    node_save_load_round_trip lore_render_deterministic menu_screen \
    dock_save_esc_success dock_save_blocked_reason quit_decisions \
    slot_one_manual_backup boot_routing_and_keys boot_fresh_first_run_no_menu \
    boot_continue_loads_slot boot_new_game_confirm boot_bad_version_fresh \
    boot_backup_slot; do
    require_case "$SAVE_UX_LOG" "$c"
done

NAV_LOG="$OUT/nav_test/run.log"
for c in dock_map_z2_node_phases policy_subdue_release_surface_dock \
    dock_rest_60_to_100_one_phase locked_boss_stays_map \
    hull_zero_ascent_returns_dock dock_menu_keys_and_esc \
    rare_batch_two_press_confirm rare_batch_other_key_cancels; do
    require_case "$NAV_LOG" "$c"
done

SCREENS_LOG="$OUT/screens_test/run.log"
for c in dock_screen_key_lines dock_save_blocked_line dock_submenu_screens \
    map_screen_ladder_locked_boss map_boss_gate_six_distinct_nonboss \
    node_screen_key_lines dock_golden_exact map_golden_exact node_golden_exact \
    release_keeps_parts_bonus_wary_renews sell_keeps_parts_money_renews \
    resolve_guards_outcome_and_active release_and_sell_both_renew_subdue; do
    require_case "$SCREENS_LOG" "$c"
done

# ---------------------------------------------------------------------------
# FAST 2: native undtool + lore/menu dump goldens
# ---------------------------------------------------------------------------
echo "== FAST: native undtool + lore/menu goldens =="
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
    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$OUT/lore1.txt" --screen lore ) \
        >"$OUT/lore.err" 2>&1
    LORE_RC=$?
    if [ "$LORE_RC" -eq 0 ] && cmp -s "$OUT/lore1.txt" "$LORE_GOLDEN"; then
        pass_case "--dump-grid --screen lore byte-identical to golden"
    else
        fail_case "--dump-grid --screen lore differs from golden (rc=$LORE_RC)"
        diff -u "$LORE_GOLDEN" "$OUT/lore1.txt" 2>/dev/null | sed 's/^/       /'
    fi

    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$OUT/menu1.txt" --screen menu ) \
        >"$OUT/menu.err" 2>&1
    MENU_RC=$?
    if [ "$MENU_RC" -eq 0 ] && cmp -s "$OUT/menu1.txt" "$MENU_GOLDEN"; then
        pass_case "--dump-grid --screen menu byte-identical to golden"
    else
        fail_case "--dump-grid --screen menu differs from golden (rc=$MENU_RC)"
        diff -u "$MENU_GOLDEN" "$OUT/menu1.txt" 2>/dev/null | sed 's/^/       /'
    fi

    ( cd "$NATIVE" && timeout 120 ./undtool.nix --dump-grid "$OUT/menu2.txt" --screen menu ) \
        >"$OUT/menu2.err" 2>&1
    if cmp -s "$OUT/menu1.txt" "$OUT/menu2.txt"; then
        pass_case "--dump-grid --screen menu rerun is byte-identical"
    else
        fail_case "--dump-grid --screen menu rerun differs"
    fi

    rm -f "$NATIVE/data.z98"
    if [ ! -f "$NATIVE/data.z98" ]; then
        pass_case "data.z98 removed beside the tool for the roundtrip gate"
    else
        fail_case "could not remove data.z98 beside the tool"
    fi
else
    for label in "--dump-grid --screen lore byte-identical to golden" \
        "--dump-grid --screen menu byte-identical to golden" \
        "--dump-grid --screen menu rerun is byte-identical" \
        "data.z98 removed beside the tool for the roundtrip gate"; do
        fail_case "$label (undtool.nix did not build)"
    done
fi

# ---------------------------------------------------------------------------
# FAST 3: real nav.boot routing driven by stdin keys
# ---------------------------------------------------------------------------
echo "== FAST: boot routing via nav.boot (boot_walk) =="
BW="$OUT/boot_walk"
mkdir -p "$BW"
BW_OK=0
if "$ZIG" -fsafe -W -osl --output-dir "$BW" "$TESTS/boot_walk.zig" \
    >"$BW/zig.log" 2>&1; then
    pass_case "boot_walk.zig -fsafe -W compile clean"
    if sh "$BW/build_target.sh" linux "$BW/boot_walk" >"$BW/build.log" 2>&1; then
        pass_case "boot_walk built natively (build_target.sh linux)"
        BW_OK=1
    else
        fail_case "boot_walk native link failed (see $BW/build.log)"
        tail -20 "$BW/build.log" | sed 's/^/       /'
    fi
else
    fail_case "boot_walk.zig compile failed (see $BW/zig.log)"
    tail -20 "$BW/zig.log" | sed 's/^/       /'
fi

FRESH="$OUT/boot/fresh"
mkdir -p "$FRESH"
if [ "$BW_OK" -eq 1 ]; then
    printf '\n' | timeout 120 "$BW/boot_walk" "$FRESH" "$UNDDIR" \
        >"$OUT/boot_fresh.log" 2>&1
    FRESH_RC=$?
    if [ "$FRESH_RC" -eq 0 ]; then
        pass_case "boot_walk fresh install exits 0"
    else
        fail_case "boot_walk fresh install failed (rc=$FRESH_RC; see $OUT/boot_fresh.log)"
    fi
    if grep -qF 'UNDERSANDED  LORE' "$OUT/boot_fresh.log"; then
        pass_case "fresh install shows page 1 (lore screen)"
    else
        fail_case "fresh install did not show page 1"
    fi
    if grep -qF 'UNDERSANDED  MAIN MENU' "$OUT/boot_fresh.log"; then
        fail_case "fresh install showed the start menu"
    else
        pass_case "fresh install shows no start menu"
    fi
    if grep -qxF 'boot ret=1 screen=10 money=0 field_record_written=0 boss_variants_seen=0 expedition_active=0 save0=1' \
        "$OUT/boot_fresh.log"; then
        pass_case "fresh install reaches dock, initializes §20, creates save0.dat"
    else
        fail_case "fresh install state/save0 line missing or wrong"
        grep '^boot ' "$OUT/boot_fresh.log" | sed 's/^/       /'
    fi

    printf 'c' | timeout 120 "$BW/boot_walk" "$FRESH" "$UNDDIR" \
        >"$OUT/boot_second.log" 2>&1
    SECOND_RC=$?
    if [ "$SECOND_RC" -eq 0 ] \
        && grep -qF 'UNDERSANDED  MAIN MENU' "$OUT/boot_second.log"; then
        pass_case "second boot shows the start menu"
    else
        fail_case "second boot did not show the start menu (rc=$SECOND_RC)"
    fi
    if grep -qF 'UNDERSANDED  LORE' "$OUT/boot_second.log"; then
        fail_case "second boot repeated page 1"
    else
        pass_case "second boot does not repeat page 1"
    fi
    if grep -qxF 'boot ret=1 screen=10 money=0 field_record_written=0 boss_variants_seen=0 expedition_active=0 save0=1' \
        "$OUT/boot_second.log"; then
        pass_case "Continue reaches the dock from the second boot"
    else
        fail_case "Continue did not reach the dock"
        grep '^boot ' "$OUT/boot_second.log" | sed 's/^/       /'
    fi

    V1DIR="$OUT/boot/v1"
    mkdir -p "$V1DIR"
    cp "$V1_FIXTURE" "$V1DIR/save0.dat"
    printf 'cq' | timeout 120 "$BW/boot_walk" "$V1DIR" "$UNDDIR" \
        >"$OUT/boot_v1.log" 2>&1
    V1_RC=$?
    if [ "$V1_RC" -eq 0 ]; then
        pass_case "v1 save boot walk exits 0 after Q"
    else
        fail_case "v1 save boot walk failed (rc=$V1_RC)"
    fi
    if grep -qF 'UNDERSANDED  SAVE ERROR' "$OUT/boot_v1.log" \
        && grep -qF 'Save is from a different version.' "$OUT/boot_v1.log"; then
        pass_case "version=1 save reaches the save-error screen with §33 copy"
    else
        fail_case "version=1 save did not reach the save-error copy"
        sed 's/^/       /' "$OUT/boot_v1.log"
    fi
    if grep -qF '[F]resh  [B]ackup slot  [Q]uit' "$OUT/boot_v1.log"; then
        pass_case "save-error screen offers [F]resh [B]ackup slot [Q]uit"
    else
        fail_case "save-error keys missing"
    fi
    if grep -qxF 'boot ret=0 screen=21 money=0 field_record_written=0 boss_variants_seen=0 expedition_active=0 save0=1' \
        "$OUT/boot_v1.log"; then
        pass_case "Q exits the save-error screen"
    else
        fail_case "Q did not exit the save-error screen"
        grep '^boot ' "$OUT/boot_v1.log" | sed 's/^/       /'
    fi

    # A poisoned fight.state must not leak into the first boot frame: nav.boot
    # installs a fresh GameState before drawing.
    POISON_FRESH="$OUT/boot/poison_fresh"
    mkdir -p "$POISON_FRESH"
    printf '\n' | timeout 120 "$BW/boot_walk" "$POISON_FRESH" "$UNDDIR" poison \
        >"$OUT/boot_poison_fresh.log" 2>&1
    PF_RC=$?
    if [ "$PF_RC" -eq 0 ] \
        && grep -qF 'UNDERSANDED  LORE' "$OUT/boot_poison_fresh.log" \
        && ! grep -qF 'UNDERSANDED  FIGHT' "$OUT/boot_poison_fresh.log"; then
        pass_case "poisoned fight state: lore renders without a fight frame"
    else
        fail_case "poisoned fight state leaked a fight frame on fresh boot (rc=$PF_RC)"
        sed 's/^/       /' "$OUT/boot_poison_fresh.log"
    fi

    printf 'q' | timeout 120 "$BW/boot_walk" "$FRESH" "$UNDDIR" poison \
        >"$OUT/boot_poison_menu.log" 2>&1
    PM_RC=$?
    if [ "$PM_RC" -eq 0 ] \
        && grep -qF 'UNDERSANDED  MAIN MENU' "$OUT/boot_poison_menu.log" \
        && ! grep -qF 'UNDERSANDED  FIGHT' "$OUT/boot_poison_menu.log"; then
        pass_case "poisoned fight state: menu renders without a fight frame"
    else
        fail_case "poisoned fight state leaked a fight frame on menu boot (rc=$PM_RC)"
        sed 's/^/       /' "$OUT/boot_poison_menu.log"
    fi

    # B adopts the other slot only when it loads.
    BOTHER="$OUT/boot/backup_other"
    mkdir -p "$BOTHER"
    cp "$V1_FIXTURE" "$BOTHER/save0.dat"
    cp "$FRESH/save0.dat" "$BOTHER/save1.dat"
    printf 'cb' | timeout 120 "$BW/boot_walk" "$BOTHER" "$UNDDIR" \
        >"$OUT/boot_backup_other.log" 2>&1
    BO_RC=$?
    if [ "$BO_RC" -eq 0 ] \
        && grep -qF 'UNDERSANDED  SAVE ERROR' "$OUT/boot_backup_other.log" \
        && grep -qxF 'boot ret=1 screen=10 money=0 field_record_written=0 boss_variants_seen=0 expedition_active=0 save0=1' \
            "$OUT/boot_backup_other.log"; then
        pass_case "backup slot B loads the valid other slot"
    else
        fail_case "backup slot B did not load the valid other slot (rc=$BO_RC)"
        grep '^boot ' "$OUT/boot_backup_other.log" | sed 's/^/       /'
    fi
    if cmp -s "$BOTHER/save0.dat" "$V1_FIXTURE"; then
        pass_case "successful B leaves the failed active slot untouched"
    else
        fail_case "successful B mutated the failed active slot"
    fi

    # B fails on both -> F must erase/re-create the original active slot, not
    # the other slot that B merely tried.
    BF="$OUT/boot/backup_fail_fresh"
    mkdir -p "$BF"
    cp "$V1_FIXTURE" "$BF/save0.dat"
    cp "$V1_FIXTURE" "$BF/save1.dat"
    printf 'cbf\n' | timeout 120 "$BW/boot_walk" "$BF" "$UNDDIR" \
        >"$OUT/boot_backup_fail.log" 2>&1
    BF_RC=$?
    if [ "$BF_RC" -eq 0 ] \
        && grep -qF 'UNDERSANDED  SAVE ERROR' "$OUT/boot_backup_fail.log" \
        && ! cmp -s "$BF/save0.dat" "$V1_FIXTURE" \
        && grep -qx 'version=2' "$BF/save0.dat"; then
        pass_case "failed B keeps the failed slot for F to erase/re-write"
    else
        fail_case "failed B confused F's target slot (rc=$BF_RC)"
        grep '^boot ' "$OUT/boot_backup_fail.log" | sed 's/^/       /'
    fi
    if cmp -s "$BF/save1.dat" "$V1_FIXTURE"; then
        pass_case "failed B leaves the other slot untouched"
    else
        fail_case "failed B wrote or erased the other slot"
    fi

    # Real startup recovery through nav.boot with production-shaped paths
    # (no trailing separator): save.bak present, save0.dat missing, stale tmp.
    REC="$OUT/boot/recovery"
    mkdir -p "$REC"
    cp "$FRESH/save0.dat" "$REC/save.bak"
    printf 'stale temp\n' >"$REC/save.tmp"
    rm -f "$REC/save0.dat"
    printf 'q' | timeout 120 "$BW/boot_walk" "$REC" "$UNDDIR" \
        >"$OUT/boot_recovery.log" 2>&1
    REC_RC=$?
    if [ "$REC_RC" -eq 0 ] && [ -f "$REC/save0.dat" ]; then
        pass_case "startup recovery via nav.boot restores save.bak"
    else
        fail_case "startup recovery via nav.boot did not restore save0.dat (rc=$REC_RC)"
    fi
    if [ ! -f "$REC/save.tmp" ]; then
        pass_case "startup recovery via nav.boot deletes stale save.tmp"
    else
        fail_case "startup recovery left stale save.tmp"
    fi
    if [ -f "$REC/errors.log" ] && grep -qF 'recovery' "$REC/errors.log"; then
        pass_case "startup recovery via nav.boot writes errors.log"
    else
        fail_case "startup recovery did not write errors.log"
    fi
    if grep -qF 'UNDERSANDED  MAIN MENU' "$OUT/boot_recovery.log"; then
        pass_case "recovery boot shows the start menu"
    else
        fail_case "recovery boot did not show the start menu"
    fi
else
    for label in "boot_walk fresh install exits 0" \
        "fresh install shows page 1 (lore screen)" \
        "fresh install shows no start menu" \
        "fresh install reaches dock, initializes §20, creates save0.dat" \
        "second boot shows the start menu" \
        "second boot does not repeat page 1" \
        "Continue reaches the dock from the second boot" \
        "v1 save boot walk exits 0 after Q" \
        "version=1 save reaches the save-error screen with §33 copy" \
        "save-error screen offers [F]resh [B]ackup slot [Q]uit" \
        "Q exits the save-error screen" \
        "poisoned fight state: lore renders without a fight frame" \
        "poisoned fight state: menu renders without a fight frame" \
        "backup slot B loads the valid other slot" \
        "successful B leaves the failed active slot untouched" \
        "failed B keeps the failed slot for F to erase/re-write" \
        "failed B leaves the other slot untouched" \
        "startup recovery via nav.boot restores save.bak" \
        "startup recovery via nav.boot deletes stale save.tmp" \
        "startup recovery via nav.boot writes errors.log" \
        "recovery boot shows the start menu"; do
        fail_case "$label (boot_walk did not build)"
    done
fi

# ---------------------------------------------------------------------------
# FAST 4: --save-roundtrip on the boot-walk save (tier-created golden)
# ---------------------------------------------------------------------------
echo "== FAST: --save-roundtrip golden =="
RTG="$OUT/roundtrip.golden"
if [ -f "$FRESH/save0.dat" ]; then
    cp "$FRESH/save0.dat" "$RTG"
    cp "$RTG" "$OUT/roundtrip.before"
else
    : >"$RTG"
    : >"$OUT/roundtrip.before"
fi

if [ "$NIX_OK" -eq 1 ]; then
    if [ ! -f "$NATIVE/data.z98" ]; then
        pass_case "--save-roundtrip no-content baseline: data.z98 absent before"
    else
        fail_case "--save-roundtrip no-content baseline: data.z98 present before"
    fi

    RTV2="$OUT/roundtrip_fixture.dat"
    cp "$V2_FIXTURE" "$RTV2"
    timeout 120 "$NIX" --save-roundtrip "$RTV2" \
        >"$OUT/rt_fixture.out" 2>"$OUT/rt_fixture.err"
    FIX_RT_RC=$?
    if [ "$FIX_RT_RC" -eq 0 ] && cmp -s "$RTV2" "$V2_FIXTURE"; then
        pass_case "--save-roundtrip committed v2 fixture exits 0, byte-identical"
    else
        fail_case "--save-roundtrip committed v2 fixture (rc=$FIX_RT_RC)"
        sed 's/^/       /' "$OUT/rt_fixture.err"
    fi

    timeout 120 "$NIX" --save-roundtrip "$RTG" \
        >"$OUT/rt.log" 2>"$OUT/rt.err"
    RT_RC=$?
    if [ "$RT_RC" -eq 0 ]; then
        pass_case "--save-roundtrip boot-walk save exits 0 (byte-identical)"
    else
        fail_case "--save-roundtrip boot-walk save exit 0 (rc=$RT_RC; see $OUT/rt.err)"
        sed 's/^/       /' "$OUT/rt.err"
    fi
    if cmp -s "$RTG" "$OUT/roundtrip.before"; then
        pass_case "--save-roundtrip leaves the original byte-identical"
    else
        fail_case "--save-roundtrip mutated the original save"
    fi
    if [ ! -f "$RTG.rt" ]; then
        pass_case "--save-roundtrip removes its temp file"
    else
        fail_case "--save-roundtrip left the temp file behind"
    fi
    if [ ! -f "$NATIVE/data.z98" ]; then
        pass_case "--save-roundtrip installs no content (data.z98 absent before and after)"
    else
        fail_case "--save-roundtrip created data.z98 beside the tool"
    fi

    # Same CRC value but a non-canonical 0X hash spelling: the save still loads,
    # while the canonical re-save differs byte-for-byte -> exit 1.
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            hash=0x*) line="hash=0X${line#hash=0x}" ;;
        esac
        printf '%s\n' "$line"
    done <"$RTG" >"$OUT/roundtrip_alt.dat"
    cp "$OUT/roundtrip_alt.dat" "$OUT/roundtrip_alt.before"
    timeout 120 "$NIX" --save-roundtrip "$OUT/roundtrip_alt.dat" \
        >"$OUT/rt_alt.out" 2>"$OUT/rt_alt.err"
    ALT_RC=$?
    if [ "$ALT_RC" -eq 1 ]; then
        pass_case "--save-roundtrip exits 1 when the re-save differs"
    else
        fail_case "--save-roundtrip differing save exit 1 (rc=$ALT_RC)"
        sed 's/^/       /' "$OUT/rt_alt.err"
    fi
    if cmp -s "$OUT/roundtrip_alt.dat" "$OUT/roundtrip_alt.before"; then
        pass_case "--save-roundtrip leaves a differing input untouched"
    else
        fail_case "--save-roundtrip mutated a differing input"
    fi

    timeout 120 "$NIX" --save-roundtrip \
        >"$OUT/rt_noarg.out" 2>"$OUT/rt_noarg.err" </dev/null
    NOARG_RC=$?
    if [ "$NOARG_RC" -eq 2 ] \
        && grep -qF -- '--save-roundtrip needs a file path' "$OUT/rt_noarg.err"; then
        pass_case "--save-roundtrip missing arg exits 2 and names the path"
    else
        fail_case "--save-roundtrip missing arg exit 2 (rc=$NOARG_RC)"
    fi

    timeout 120 "$NIX" --save-roundtrip "$OUT/does_not_exist.dat" \
        >"$OUT/rt_missing.out" 2>"$OUT/rt_missing.err"
    MISSING_RC=$?
    if [ "$MISSING_RC" -eq 2 ]; then
        pass_case "--save-roundtrip missing file exits 2"
    else
        fail_case "--save-roundtrip missing file exit 2 (rc=$MISSING_RC)"
    fi
    if [ ! -f "$NATIVE/data.z98" ]; then
        pass_case "--save-roundtrip exit 2 still installs no content"
    else
        fail_case "--save-roundtrip exit 2 installed data.z98"
    fi

    RESDIR="$OUT/reserved"
    mkdir -p "$RESDIR"
    cp "$V2_FIXTURE" "$RESDIR/save.tmp"
    cp "$V2_FIXTURE" "$RESDIR/save.bak"
    timeout 120 "$NIX" --save-roundtrip "$RESDIR/save.tmp" \
        >"$OUT/rt_res_tmp.out" 2>"$OUT/rt_res_tmp.err"
    RES_TMP_RC=$?
    if [ "$RES_TMP_RC" -eq 2 ] && cmp -s "$RESDIR/save.tmp" "$V2_FIXTURE"; then
        pass_case "--save-roundtrip rejects input basename save.tmp"
    else
        fail_case "--save-roundtrip save.tmp input (rc=$RES_TMP_RC)"
    fi
    timeout 120 "$NIX" --save-roundtrip "$RESDIR/save.bak" \
        >"$OUT/rt_res_bak.out" 2>"$OUT/rt_res_bak.err"
    RES_BAK_RC=$?
    if [ "$RES_BAK_RC" -eq 2 ] && cmp -s "$RESDIR/save.bak" "$V2_FIXTURE"; then
        pass_case "--save-roundtrip rejects input basename save.bak"
    else
        fail_case "--save-roundtrip save.bak input (rc=$RES_BAK_RC)"
    fi

    SIB="$OUT/sibling"
    mkdir -p "$SIB"
    cp "$V2_FIXTURE" "$SIB/save0.dat"
    printf 'keep sibling save.tmp\n' >"$SIB/save.tmp"
    cp "$SIB/save.tmp" "$OUT/sibling_save_tmp.before"
    timeout 120 "$NIX" --save-roundtrip "$SIB/save0.dat" \
        >"$OUT/rt_sibling.out" 2>"$OUT/rt_sibling.err"
    SIB_RC=$?
    if [ "$SIB_RC" -eq 0 ] \
        && cmp -s "$SIB/save.tmp" "$OUT/sibling_save_tmp.before"; then
        pass_case "--save-roundtrip preserves a pre-existing sibling save.tmp"
    else
        fail_case "--save-roundtrip disturbed a pre-existing sibling save.tmp (rc=$SIB_RC)"
    fi

    cp "$V1_FIXTURE" "$OUT/roundtrip_bad.dat"
    timeout 120 "$NIX" --save-roundtrip "$OUT/roundtrip_bad.dat" \
        >"$OUT/rt_bad.out" 2>"$OUT/rt_bad.err"
    BAD_RC=$?
    if [ "$BAD_RC" -eq 2 ]; then
        pass_case "--save-roundtrip unreadable content exits 2"
    else
        fail_case "--save-roundtrip unreadable content exit 2 (rc=$BAD_RC)"
    fi
    if cmp -s "$OUT/roundtrip_bad.dat" "$V1_FIXTURE"; then
        pass_case "--save-roundtrip leaves an unreadable input untouched"
    else
        fail_case "--save-roundtrip mutated an unreadable input"
    fi
else
    for label in "--save-roundtrip no-content baseline: data.z98 absent before" \
        "--save-roundtrip committed v2 fixture exits 0, byte-identical" \
        "--save-roundtrip boot-walk save exits 0 (byte-identical)" \
        "--save-roundtrip leaves the original byte-identical" \
        "--save-roundtrip removes its temp file" \
        "--save-roundtrip installs no content (data.z98 absent before and after)" \
        "--save-roundtrip exits 1 when the re-save differs" \
        "--save-roundtrip leaves a differing input untouched" \
        "--save-roundtrip missing arg exits 2 and names the path" \
        "--save-roundtrip missing file exits 2" \
        "--save-roundtrip exit 2 still installs no content" \
        "--save-roundtrip rejects input basename save.tmp" \
        "--save-roundtrip rejects input basename save.bak" \
        "--save-roundtrip preserves a pre-existing sibling save.tmp" \
        "--save-roundtrip unreadable content exits 2" \
        "--save-roundtrip leaves an unreadable input untouched"; do
        fail_case "$label (undtool.nix did not build)"
    done
fi

# ---------------------------------------------------------------------------
# FAST 5: nested M6 (which nests M5 -> M4 -> ...) regression gate
# ---------------------------------------------------------------------------
echo "== FAST: M6 regression (tier_m6_data.sh) =="
M6LOG="$OUT/tier_m6_data.log"
if ZIG="$ZIG" OUT="$OUT/m6" sh "$M6_TIER" >"$M6LOG" 2>&1; then
    pass_case "tier_m6_data.sh green (M1->M6 + loader/content)"
else
    fail_case "tier_m6_data.sh failed (see $M6LOG)"
fi
tail -8 "$M6LOG" | sed 's/^/       /'
if grep -q '^TIER_M6 PASS ' "$M6LOG" && ! grep -q '^TIER_M6 FAIL ' "$M6LOG"; then
    pass_case "tier_m6_data summary PASS"
else
    fail_case "tier_m6_data summary missing/FAIL"
fi
if grep -q '^FAIL - ' "$M6LOG"; then
    fail_case "tier_m6_data reported a FAIL line"
else
    pass_case "tier_m6_data reports no FAIL - lines"
fi

echo
echo "== tier_m7_save summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M7 FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "TIER_M7 PASS $PASSES passed / $FAILS failed"
exit 0
