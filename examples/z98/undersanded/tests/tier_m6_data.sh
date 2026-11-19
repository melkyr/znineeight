#!/bin/sh
# tier_m6_data.sh — UNDERSANDED M6 data tables + loader acceptance tier
# (spec §25.10/§32/§33/§35; controller P24).
#
# FAST, native only (no Wine gate):
#   * build each M6 driver with -fsafe -W -osl + build_target.sh linux
#   * run data_test, data_load_test, validate_test, bind_test,
#     data_content_test, and content_test; every driver must exit 0, print its
#     exact PASS line, and print no FAIL line
#   * assert existing driver case names by name (non-vacuous)
#   * build undtool_native.zig, byte-compare `--dump-defs data.z98` with the
#     committed tests/fixtures/defs_golden.txt, rerun for determinism, prove a
#     missing arg exits 2, and prove two different input files dump differently
#     (dump uses the argument, never the installed/fallback tables)
#   * load the shipped data.z98 through data_content_test and assert 19 defs,
#     7 rules, 7 tools, 15 upgrades, 12 cosmetics, Z1-Z3 encounter sums 100,
#     Z4-Z8 phases empty, the 12-zone ladder with zone 8 boss=1, and manual.1
#   * 56-creature boundary (accept) / 57 (reject) from /tmp fixtures generated
#     in shell from the real shipped creature rows (no 57-row file committed)
#   * nest tier_m5_dock.sh (which nests M4->M3) and require its PASS summary
#
# Env: ZIG  compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT  scratch dir (default /tmp/undersanded_m6_tier)
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# failure and prints `TIER_M6 PASS <n> passed / <m> failed`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m6_tier}"
TESTS="examples/z98/undersanded/tests"
FIXTURES="$SCRIPT_DIR/fixtures"
DATA="$ROOT/examples/z98/undersanded/data.z98"
GOLDEN="$FIXTURES/defs_golden.txt"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/seed151_build"
    exit 1
fi
if [ ! -f "$DATA" ] || [ ! -f "$GOLDEN" ] || [ ! -f "$FIXTURES/data_good.z98" ]; then
    echo "FAIL: M6 fixture missing ($DATA, $GOLDEN, $FIXTURES/data_good.z98)"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 1: M6 unit drivers (-fsafe -W clean, PASS, exit 0, no FAIL line)
# ---------------------------------------------------------------------------
echo "== FAST: M6 unit drivers =="
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

for t in data_test data_load_test validate_test bind_test data_content_test content_test; do
    run_driver "$t"
done

DATA_LOG="$OUT/data_test/run.log"
for c in parse_i32_edges classify_header row_kv_capacity line_cap_4096; do
    require_case "$DATA_LOG" "$c"
done

CONTENT_TEST_LOG="$OUT/content_test/run.log"
for c in creature_names_nonempty_unique_24 creature_masks_match_s14_2 \
    creature_drops_match_s14_4 boss_row_pins_s14_2_fields \
    tables_size_within_budget creature_scalars_match_s14_2 \
    tools_match_s10 upgrades_match_s11 cosmetics_match_s11 \
    encounters_match_s13 zones_and_zone_d_match_s12; do
    require_case "$CONTENT_TEST_LOG" "$c"
done

LOAD_LOG="$OUT/data_load_test/run.log"
for c in load_data_matches_fallback text_paragraphs_and_hash_prose \
    text_crlf_strips_cr rule_badref_records_line dump_defs_golden_byte_exact \
    reject_unknown_section_line reject_unknown_key_line \
    bad_field_leaves_tables_untouched override_visible_only_after_install; do
    require_case "$LOAD_LOG" "$c"
done

VALIDATE_LOG="$OUT/validate_test/run.log"
for c in fallback_validates_clean data_good_validates_clean \
    data_z98_validates_clean over_capacity_57_creatures \
    def_count_over_capacity_synthetic encounter_weight_sum \
    manual1_missing_when_text manual1_missing_section_when_loaded \
    manual1_empty_when_text text_bytes_over_cap \
    creature_name_nonprintable phase_mask_high_bits \
    rule_partition_gap upgrade_grid_missing_row; do
    require_case "$VALIDATE_LOG" "$c"
done

BIND_LOG="$OUT/bind_test/run.log"
for c in shipped_load_validate_install temp_override_visible_then_uninstall \
    boot_failure_single_emission startup_missing_copy_exit_nonzero \
    startup_damaged_copy_line_3; do
    require_case "$BIND_LOG" "$c"
done

# ---------------------------------------------------------------------------
# FAST 2: shipped data.z98 content (driver cases, item 3)
# ---------------------------------------------------------------------------
echo "== FAST: shipped data.z98 content =="
CONTENT_LOG="$OUT/data_content_test/run.log"
for c in shipped_data_loads shipped_data_validates_clean defs_19 rules_7 \
    tools_7 upgrades_15 cosmetics_12 \
    encounters_z1_day_sum_100 encounters_z1_night_sum_100 \
    encounters_z2_day_sum_100 encounters_z2_night_sum_100 \
    encounters_z3_day_sum_100 encounters_z3_night_sum_100 \
    encounters_z4_z8_phases_empty zones_12_cost_ladder zone8_boss_only \
    boss_row_fields manual_1_present_nonempty; do
    require_case "$CONTENT_LOG" "$c"
done

# ---------------------------------------------------------------------------
# FAST 3: native undtool and --dump-defs golden
# ---------------------------------------------------------------------------
echo "== FAST: native undtool + --dump-defs golden =="
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

if [ "$NIX_OK" -eq 1 ]; then
    timeout 120 "$NIX" --dump-defs "$DATA" >"$OUT/defs1.txt" 2>"$OUT/defs1.err"
    DEFS_RC=$?
    if [ "$DEFS_RC" -eq 0 ] && [ -s "$OUT/defs1.txt" ]; then
        pass_case "--dump-defs data.z98 exits 0 with output"
    else
        fail_case "--dump-defs data.z98 failed (rc=$DEFS_RC; see $OUT/defs1.err)"
        sed 's/^/       /' "$OUT/defs1.err"
    fi
    if cmp -s "$OUT/defs1.txt" "$GOLDEN"; then
        pass_case "--dump-defs data.z98 byte-identical to defs_golden.txt"
    else
        fail_case "--dump-defs data.z98 differs from defs_golden.txt"
        diff -u "$GOLDEN" "$OUT/defs1.txt" 2>/dev/null | sed 's/^/       /'
    fi

    timeout 120 "$NIX" --dump-defs "$DATA" >"$OUT/defs2.txt" 2>"$OUT/defs2.err"
    DEFS2_RC=$?
    if [ "$DEFS2_RC" -eq 0 ] && cmp -s "$OUT/defs1.txt" "$OUT/defs2.txt"; then
        pass_case "--dump-defs rerun is byte-identical"
    else
        fail_case "--dump-defs rerun differs (rc=$DEFS2_RC)"
    fi

    timeout 120 "$NIX" --dump-defs >"$OUT/defs_missing.out" 2>"$OUT/defs_missing.err" </dev/null
    MISSING_RC=$?
    if [ "$MISSING_RC" -eq 2 ]; then
        pass_case "--dump-defs missing arg exits 2"
    else
        fail_case "--dump-defs missing arg exit 2 (rc=$MISSING_RC)"
    fi
    if grep -qF -- '--dump-defs needs a file path' "$OUT/defs_missing.err"; then
        pass_case "--dump-defs missing arg names the path requirement"
    else
        fail_case "--dump-defs missing arg diagnostic missing"
    fi

    timeout 120 "$NIX" --dump-defs "$FIXTURES/data_good.z98" \
        >"$OUT/defs_good.txt" 2>"$OUT/defs_good.err"
    GOOD_RC=$?
    if [ "$GOOD_RC" -eq 0 ] && [ -s "$OUT/defs_good.txt" ]; then
        pass_case "--dump-defs data_good.z98 exits 0 with output"
    else
        fail_case "--dump-defs data_good.z98 failed (rc=$GOOD_RC)"
    fi
    if cmp -s "$OUT/defs1.txt" "$OUT/defs_good.txt"; then
        fail_case "--dump-defs two different files produced identical output (installed?)"
    else
        pass_case "--dump-defs two different files differ (never installs)"
    fi

    MUT="$OUT/mutated.z98"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "format=2") printf 'format=1\n' ;;
            *) printf '%s\n' "$line" ;;
        esac
    done <"$DATA" >"$MUT"
    if grep -qx 'format=1' "$MUT"; then
        pass_case "mutated /tmp copy carries format=1"
    else
        fail_case "mutated /tmp copy was not produced"
    fi
    timeout 120 "$NIX" --dump-defs "$MUT" >"$OUT/defs_mutated.out" 2>"$OUT/defs_mutated.err"
    MUT_RC=$?
    if [ "$MUT_RC" -eq 2 ] && [ ! -s "$OUT/defs_mutated.out" ]; then
        pass_case "--dump-defs rejects the mutated /tmp copy (exit 2)"
    else
        fail_case "--dump-defs accepted the mutated /tmp copy (rc=$MUT_RC)"
        sed 's/^/       /' "$OUT/defs_mutated.err"
    fi
else
    for label in "--dump-defs data.z98 exits 0 with output" \
        "--dump-defs data.z98 byte-identical to defs_golden.txt" \
        "--dump-defs rerun is byte-identical" \
        "--dump-defs missing arg exits 2" \
        "--dump-defs missing arg names the path requirement" \
        "--dump-defs data_good.z98 exits 0 with output" \
        "--dump-defs two different files differ (never installs)" \
        "mutated /tmp copy carries format=1" \
        "--dump-defs rejects the mutated /tmp copy (exit 2)"; do
        fail_case "$label (undtool.nix did not build)"
    done
fi

# ---------------------------------------------------------------------------
# FAST 4: 56/57 creature capacity boundary from generated /tmp fixtures
# ---------------------------------------------------------------------------
echo "== FAST: 56/57 creature capacity boundary =="
ROW_SRC="$OUT/real_creature_rows.txt"
section=""
while IFS= read -r line; do
    case "$line" in
        "[creatures]") section="creatures" ;;
        "["*"]") section="" ;;
        id=*)
            if [ "$section" = "creatures" ]; then
                printf '%s\n' "$line"
            fi
            ;;
    esac
done <"$DATA" >"$ROW_SRC"
REAL_ROWS="$(grep -c '^id=' "$ROW_SRC" || true)"
if [ "$REAL_ROWS" -eq 19 ]; then
    pass_case "extracted 19 real creature rows from data.z98"
else
    fail_case "expected 19 real creature rows, got $REAL_ROWS"
fi

CAP56="$OUT/cap56.z98"
CAP57="$OUT/cap57.z98"
{
    printf 'format=2\n[creatures]\n'
    n=0
    while [ "$n" -lt 2 ]; do cat "$ROW_SRC"; n=$((n + 1)); done
    head -n 18 "$ROW_SRC"
} >"$CAP56"
{
    printf 'format=2\n[creatures]\n'
    n=0
    while [ "$n" -lt 3 ]; do cat "$ROW_SRC"; n=$((n + 1)); done
} >"$CAP57"

C56="$(grep -c '^id=' "$CAP56" || true)"
C57="$(grep -c '^id=' "$CAP57" || true)"
if [ "$C56" -eq 56 ]; then
    pass_case "generated /tmp fixture carries exactly 56 creature rows"
else
    fail_case "generated 56 fixture carries $C56 rows"
fi
if [ "$C57" -eq 57 ]; then
    pass_case "generated /tmp fixture carries exactly 57 creature rows"
else
    fail_case "generated 57 fixture carries $C57 rows"
fi

if [ "$NIX_OK" -eq 1 ]; then
    timeout 120 "$NIX" --dump-defs "$CAP56" >"$OUT/cap56_dump.txt" 2>"$OUT/cap56_dump.err"
    CAP56_RC=$?
    CAP56_DEFS="$(grep -c '^id=.*name_len=' "$OUT/cap56_dump.txt" || true)"
    if [ "$CAP56_RC" -eq 0 ] && [ "$CAP56_DEFS" -eq 56 ]; then
        pass_case "56 creatures accepted (dump exits 0, 56 defs)"
    else
        fail_case "56 creatures rejected (rc=$CAP56_RC, defs=$CAP56_DEFS)"
        sed 's/^/       /' "$OUT/cap56_dump.err"
    fi

    timeout 120 "$NIX" --dump-defs "$CAP57" >"$OUT/cap57_dump.txt" 2>"$OUT/cap57_dump.err"
    CAP57_RC=$?
    if [ "$CAP57_RC" -eq 2 ] && [ ! -s "$OUT/cap57_dump.txt" ] \
        && grep -qF 'cannot read or parse data file' "$OUT/cap57_dump.err"; then
        pass_case "57 creatures rejected (exit 2, no dump)"
    else
        fail_case "57 creatures not rejected (rc=$CAP57_RC; see $OUT/cap57_dump.err)"
        sed 's/^/       /' "$OUT/cap57_dump.err"
    fi
else
    fail_case "56 creatures accepted (undtool.nix did not build)"
    fail_case "57 creatures rejected (undtool.nix did not build)"
fi

# ---------------------------------------------------------------------------
# FAST 5: nested M5 (which nests M4 -> M3) regression gate
# ---------------------------------------------------------------------------
echo "== FAST: M5 regression (tier_m5_dock.sh) =="
M5LOG="$OUT/tier_m5_dock.log"
if ZIG="$ZIG" OUT="$OUT/m5" sh "$TESTS/tier_m5_dock.sh" >"$M5LOG" 2>&1; then
    pass_case "tier_m5_dock.sh green (M1->M5 + dock/economy)"
else
    fail_case "tier_m5_dock.sh failed (see $M5LOG)"
fi
tail -8 "$M5LOG" | sed 's/^/       /'
if grep -q '^TIER_M5 PASS ' "$M5LOG" && ! grep -q '^TIER_M5 FAIL ' "$M5LOG"; then
    pass_case "tier_m5_dock summary PASS"
else
    fail_case "tier_m5_dock summary missing/FAIL"
fi
if grep -q '^FAIL - ' "$M5LOG"; then
    fail_case "tier_m5_dock reported a FAIL line"
else
    pass_case "tier_m5_dock reports no FAIL - lines"
fi

echo
echo "== tier_m6_data summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M6 FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "TIER_M6 PASS $PASSES passed / $FAILS failed"
exit 0
