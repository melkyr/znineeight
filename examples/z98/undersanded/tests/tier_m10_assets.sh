#!/bin/sh
# tier_m10_assets.sh — UNDERSANDED M10 assets-pipeline acceptance gate
# (spec §30, §35, §38 M10, §40; P19, P29).
#
# FAST, native only (no Wine gate):
#   * run zsp_test (palette + decoder), validate_assets_test (validator) and
#     the new assets_golden_test with -fsafe -W -osl + build_target.sh linux;
#     assert exact PASS lines and named cases
#   * parse the committed assets.man as shell text: exactly 26 A / 12 V / 1 F
#     rows, the exact A-name and V-ledger order, no other rows, then assert the
#     binding budgets (indexed, indexed+LUTs, each background, demo RLE disk)
#     against both manifest figures and the on-disk `.zsp` sizes
#   * build undtool_native.zig and require
#     `--validate-assets assets/assets.man assets/out` rc 0; a mutated manifest
#     copy must be rejected (non-vacuity)
#   * decode eel00, boss00 and bg_a with the runtime decoder and pin dimensions,
#     key, header ramp, pixel/LUT FNV checksums and three sample pixels; a
#     mutated `.zsp` copy must be rejected (non-vacuity)
#   * require the art golden to be the Task 5 re-pin `0x4395f2f9` (the nested
#     M9 tier proves the rendered frame still matches it) and pin the M10
#     art_test cases (26A/12V decode, one resident background, malformed-V
#     fallback) from the nested M9 log
#   * P19: no committed Python or SVG-converter file under the example and no
#     Python invocation in this tier
#   * nest tier_m9_px.sh as the regression gate (z9edit/terminal/M9 goldens and
#     the existing M8 -> M1 chain) and require its PASS
#
# Env: ZIG      compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT      scratch dir (default /tmp/undersanded_m10_assets_tier)
#      M9_TIER  nested M9 tier path override
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# failure and prints `TIER_M10 PASS <n> passed / <m> failed`.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m10_assets_tier}"
TESTS="examples/z98/undersanded/tests"
MANIFEST="$UNDDIR/assets/assets.man"
ASSET_OUT="$UNDDIR/assets/out"
FIXTURES="$UNDDIR/tests/fixtures"
ART_GOLDEN="$FIXTURES/art_fight.golden"
M9_TIER="${M9_TIER:-$SCRIPT_DIR/tier_m9_px.sh}"

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
if [ ! -f "$MANIFEST" ] || [ ! -d "$ASSET_OUT" ] \
    || [ ! -f "$ART_GOLDEN" ] || [ ! -f "$M9_TIER" ]; then
    echo "FAIL: M10 asset input missing ($MANIFEST, $ASSET_OUT, $ART_GOLDEN, $M9_TIER)"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 1: native palette/decoder/validator/golden drivers
# ---------------------------------------------------------------------------
echo "== FAST: M10 native drivers =="
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

require_line() {
    log="$1"
    line="$2"
    label="$3"
    if [ -f "$log" ] && grep -qxF "$line" "$log"; then
        pass_case "$label"
    else
        fail_case "$label"
    fi
}

for t in zsp_test validate_assets_test assets_golden_test; do
    run_driver "$t"
done

ZSP_LOG="$OUT/zsp_test/run.log"
for c in palette_anchors_0_5_10_15 palette_intermediate_rounding \
    palette_key_255_ramp15 decode_golden_pixels_lut recolor_lut_exact \
    recolor_lut_ramp15_base254 canonical_encode_greedy_255; do
    require_case "$ZSP_LOG" "$c"
done

VAL_LOG="$OUT/validate_assets_test/run.log"
for c in setup_synthetic_assets asset_accepts_known_good \
    asset_rejects_bad_magic asset_rejects_off_ramp_pixel \
    asset_rejects_noncanonical_rle manifest_accepts_full_ledger \
    manifest_rejects_budget_overrun; do
    require_case "$VAL_LOG" "$c"
done

GOLD_LOG="$OUT/assets_golden_test/run.log"
for c in golden_decode_eel00 golden_decode_boss00 golden_decode_bg_a; do
    require_case "$GOLD_LOG" "$c"
done

# ---------------------------------------------------------------------------
# FAST 2: assets.man ledger + budgets (pure shell parse)
# ---------------------------------------------------------------------------
echo "== FAST: assets.man ledger + budgets =="
is_num() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}
is_kind() {
    case "$1" in
        creature|bg|boat|overlay) return 0 ;;
        *) return 1 ;;
    esac
}

A_ROWS=0
V_ROWS=0
F_ROWS=0
OTHER_ROWS=0
INDEXED=0
A_ENC_TOTAL=0
BG_MAX=0
BG_MAX_NAME=""
A_NAMES=""
V_LEDGER=""
F_LEDGER=""

while IFS=' ' read -r tag f1 f2 f3 f4 f5 f6 extra; do
    case "$tag" in
        A)
            A_ROWS=$((A_ROWS + 1))
            if [ -n "${extra:-}" ] || ! is_kind "${f2:-}" \
                || ! is_num "${f3:-}" || ! is_num "${f4:-}" \
                || ! is_num "${f5:-}" || [ -z "${f6:-}" ]; then
                OTHER_ROWS=$((OTHER_ROWS + 1))
                continue
            fi
            INDEXED=$((INDEXED + f3 * f4))
            A_ENC_TOTAL=$((A_ENC_TOTAL + f5))
            if [ "$f2" = "bg" ] && [ "$f5" -gt "$BG_MAX" ]; then
                BG_MAX=$f5
                BG_MAX_NAME=$f1
            fi
            A_NAMES="${A_NAMES}${f1}
"
            ;;
        V)
            V_ROWS=$((V_ROWS + 1))
            if [ -n "${extra:-}" ] || ! is_num "${f3:-}" || ! is_num "${f4:-}" \
                || [ -z "${f1:-}" ] || [ -z "${f2:-}" ]; then
                OTHER_ROWS=$((OTHER_ROWS + 1))
                continue
            fi
            V_LEDGER="${V_LEDGER}${f1} ${f2} ${f3} ${f4}
"
            ;;
        F)
            F_ROWS=$((F_ROWS + 1))
            if [ -n "${extra:-}" ] || [ "$f1" != "font8x16" ] \
                || [ "$f2" != "95" ] || [ "$f3" != "16" ]; then
                OTHER_ROWS=$((OTHER_ROWS + 1))
                continue
            fi
            F_LEDGER="${F_LEDGER}${f1} ${f2} ${f3}
"
            ;;
        *)
            OTHER_ROWS=$((OTHER_ROWS + 1))
            ;;
    esac
done <"$MANIFEST"

EXPECTED_A_NAMES="eel00
tuna00
crab00
jelly00
barn00
anem00
ray00
squid00
angler00
wrasse00
boss00
bg_a
bg_b
bg_c
bg_d
bg_dock
boat00
fig_merm
fig_angl
fig_krak
flag_pen
flag_ref
flag_trn
dec_barn
dec_sqid
dec_boss
"
EXPECTED_V_LEDGER="id2 eel00 6 1
id3 eel00 6 5
id5 tuna00 7 14
id6 tuna00 7 10
id11 crab00 8 11
id12 jelly00 9 5
id18 anem00 11 5
id19 tuna00 7 1
boss00:sliver boss00 10 2
boss00:hoard boss00 10 4
boss00:drown boss00 10 13
boss00:blur boss00 10 5
"
EXPECTED_F_LEDGER="font8x16 95 16
"

report_eq() {
    label="$1"
    got="$2"
    want="$3"
    if [ "$got" = "$want" ]; then
        pass_case "$label = $want"
    else
        fail_case "$label expected $want, got $got"
    fi
}
report_num() {
    label="$1"
    got="$2"
    want="$3"
    if [ "$got" -eq "$want" ] 2>/dev/null; then
        pass_case "$label = $want"
    else
        fail_case "$label expected $want, got $got"
    fi
}
report_cap() {
    label="$1"
    got="$2"
    cap="$3"
    if [ "$got" -le "$cap" ] 2>/dev/null; then
        pass_case "$label $got <= $cap B"
    else
        fail_case "$label $got > $cap B cap"
    fi
}

report_num "A rows" "$A_ROWS" 26
report_num "V rows" "$V_ROWS" 12
report_num "F rows" "$F_ROWS" 1
report_num "other/blank manifest rows" "$OTHER_ROWS" 0
report_eq "A name ledger/order" "$A_NAMES" "$EXPECTED_A_NAMES"
report_eq "V ledger/order" "$V_LEDGER" "$EXPECTED_V_LEDGER"
report_eq "F ledger" "$F_LEDGER" "$EXPECTED_F_LEDGER"

LUT_BYTES=$((512 * (A_ROWS + V_ROWS)))
INDEXED_PLUS_LUT=$((INDEXED + LUT_BYTES))
INDEXED_MAX=$((1350 * 1024))
ARENA_MAX=$((2 * 1024 * 1024))
BG_MAX_CAP=$((120 * 1024))
RLE_MAX=$((400 * 1024))

report_num "indexed bytes (sum A w*h)" "$INDEXED" 1128240
report_num "LUT bytes (512*(A+V))" "$LUT_BYTES" 19456
report_num "indexed + LUT bytes" "$INDEXED_PLUS_LUT" 1147696
report_num "manifest A encoded total" "$A_ENC_TOTAL" 62956
report_num "largest background encoded" "$BG_MAX" 6044
report_eq "largest background name" "$BG_MAX_NAME" "bg_d"
report_cap "indexed" "$INDEXED" "$INDEXED_MAX"
report_cap "indexed + LUTs" "$INDEXED_PLUS_LUT" "$ARENA_MAX"
report_cap "each background encoded" "$BG_MAX" "$BG_MAX_CAP"
report_cap "demo RLE disk (manifest)" "$A_ENC_TOTAL" "$RLE_MAX"

FILES=0
DISK_TOTAL=0
DISK_BG_MAX=0
DISK_BG_MAX_NAME=""
for f in "$ASSET_OUT"/*.zsp; do
    [ -f "$f" ] || continue
    FILES=$((FILES + 1))
    sz="$(wc -c <"$f")"
    DISK_TOTAL=$((DISK_TOTAL + sz))
    name="${f##*/}"
    name="${name%.zsp}"
    case "$name" in
        bg_a|bg_b|bg_c|bg_d|bg_dock)
            if [ "$sz" -gt "$DISK_BG_MAX" ]; then
                DISK_BG_MAX=$sz
                DISK_BG_MAX_NAME=$name
            fi
            ;;
    esac
done
report_num "committed .zsp files" "$FILES" 26
report_num "on-disk RLE total" "$DISK_TOTAL" 62956
report_num "on-disk largest background" "$DISK_BG_MAX" 6044
report_eq "on-disk largest background name" "$DISK_BG_MAX_NAME" "bg_d"
report_cap "on-disk RLE total" "$DISK_TOTAL" "$RLE_MAX"
report_cap "on-disk each background" "$DISK_BG_MAX" "$BG_MAX_CAP"

# ---------------------------------------------------------------------------
# FAST 3: native undtool --validate-assets + mutated-manifest non-vacuity
# ---------------------------------------------------------------------------
echo "== FAST: undtool --validate-assets =="
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

if [ "$NIX_OK" -eq 1 ]; then
    timeout 120 "$NIX" --validate-assets "$MANIFEST" "$ASSET_OUT" \
        >"$OUT/validate_assets.log" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ] && ! grep -q 'undtool:' "$OUT/validate_assets.log"; then
        pass_case "undtool --validate-assets real manifest rc 0"
    else
        fail_case "undtool --validate-assets real manifest failed (rc=$rc)"
        indent <"$OUT/validate_assets.log"
    fi

    MUT_MAN="$OUT/assets.mutated.man"
    : >"$MUT_MAN"
    while IFS= read -r line; do
        case "$line" in
            "A eel00 creature 96 96 1586 0,6")
                printf '%s\n' "A eel00 creature 96 96 1586 0,7" >>"$MUT_MAN"
                ;;
            *)
                printf '%s\n' "$line" >>"$MUT_MAN"
                ;;
        esac
    done <"$MANIFEST"
    if cmp -s "$MUT_MAN" "$MANIFEST"; then
        fail_case "non-vacuity: mutated manifest copy did not change"
    else
        pass_case "non-vacuity: mutated manifest copy differs from committed ledger"
    fi
    timeout 120 "$NIX" --validate-assets "$MUT_MAN" "$ASSET_OUT" \
        >"$OUT/validate_assets_mutated.log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ] \
        && grep -q 'invalid: ledger mismatch' "$OUT/validate_assets_mutated.log"; then
        pass_case "non-vacuity: validator rejects mutated manifest (rc=$rc)"
    else
        fail_case "non-vacuity: validator accepted mutated manifest (rc=$rc)"
        indent <"$OUT/validate_assets_mutated.log"
    fi
else
    fail_case "undtool --validate-assets real manifest rc 0 (undtool.nix did not build)"
    fail_case "non-vacuity: validator rejects mutated manifest (undtool.nix did not build)"
fi

# ---------------------------------------------------------------------------
# FAST 4: decoded sprite goldens + art-golden re-pin + non-vacuity
# ---------------------------------------------------------------------------
echo "== FAST: decoded sprite goldens =="
require_line "$GOLD_LOG" \
    "golden eel00 96x96 key=255 ramp=6 pix_fnv=0xf623b7c9 lut_fnv=0xd098bcc9 p0=255 pc=255 pz=255" \
    "eel00 pinned pixel/LUT/checksum evidence"
require_line "$GOLD_LOG" \
    "golden boss00 96x96 key=255 ramp=10 pix_fnv=0x8e4ac719 lut_fnv=0xd098bcc9 p0=255 pc=160 pz=255" \
    "boss00 pinned pixel/LUT/checksum evidence"
require_line "$GOLD_LOG" \
    "golden bg_a 640x300 key=255 ramp=1 pix_fnv=0x1722e7f4 lut_fnv=0xd098bcc9 p0=21 pc=21 pz=239" \
    "bg_a pinned pixel/LUT/checksum evidence"

ART_PIN="$(head -n 1 "$ART_GOLDEN")"
if [ "$ART_PIN" = "0x4395f2f9" ]; then
    pass_case "art golden is the Task 5 re-pin 0x4395f2f9"
else
    fail_case "art golden is not 0x4395f2f9 (got $ART_PIN)"
fi

MUT_OUT="$OUT/mutated_out"
mkdir -p "$MUT_OUT"
cp "$ASSET_OUT/eel00.zsp" "$MUT_OUT/eel00.zsp"
cp "$ASSET_OUT/boss00.zsp" "$MUT_OUT/boss00.zsp"
cp "$ASSET_OUT/bg_a.zsp" "$MUT_OUT/bg_a.zsp"
printf '\000' | dd of="$MUT_OUT/eel00.zsp" bs=1 seek=529 conv=notrunc \
    >/dev/null 2>&1
if cmp -s "$ASSET_OUT/eel00.zsp" "$MUT_OUT/eel00.zsp"; then
    fail_case "non-vacuity: mutated eel00 copy did not change"
else
    pass_case "non-vacuity: mutated eel00 copy differs from committed asset"
fi
M10_ASSETS_OUT="$MUT_OUT" timeout 180 \
    "$OUT/assets_golden_test/assets_golden_test" \
    >"$OUT/assets_golden_mutated.log" 2>&1
rc=$?
if [ "$rc" -ne 0 ] \
    && grep -qx 'FAIL - golden_decode_eel00' "$OUT/assets_golden_mutated.log" \
    && ! grep -q 'FAIL - golden_decode_boss00' "$OUT/assets_golden_mutated.log" \
    && ! grep -q 'FAIL - golden_decode_bg_a' "$OUT/assets_golden_mutated.log"; then
    pass_case "non-vacuity: golden decoder rejects mutated eel00 (rc=$rc)"
else
    fail_case "non-vacuity: golden decoder accepted mutated eel00 (rc=$rc)"
    indent <"$OUT/assets_golden_mutated.log"
fi

# ---------------------------------------------------------------------------
# FAST 5: P19 tooling compliance + no scripting-language invocation in tier
# ---------------------------------------------------------------------------
echo "== FAST: P19 no committed converter/Python =="
PY_FILES="$(find "$UNDDIR" -type f -name '*.py' -print)"
if [ -z "$PY_FILES" ]; then
    pass_case "no committed Python file under examples/z98/undersanded"
else
    fail_case "committed Python file(s) under examples/z98/undersanded"
    printf '%s\n' "$PY_FILES" | indent
fi
PYC_FILES="$(find "$UNDDIR" -type f -name '*.pyc' -print)"
if [ -z "$PYC_FILES" ]; then
    pass_case "no committed Python bytecode under examples/z98/undersanded"
else
    fail_case "committed Python bytecode under examples/z98/undersanded"
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
# FAST 6: nested M9 regression (z9edit/terminal/M9 + M8 -> M1 chain)
# ---------------------------------------------------------------------------
echo "== FAST: M9 regression (tier_m9_px.sh) =="
M9LOG="$OUT/tier_m9.log"
if ZIG="$ZIG" OUT="$OUT/m9" FIXTURES="$FIXTURES" sh "$M9_TIER" \
    >"$M9LOG" 2>&1; then
    pass_case "tier_m9_px.sh green (z9edit/terminal/M9 + M8->M1)"
else
    fail_case "tier_m9_px.sh failed (see $M9LOG)"
fi
tail -8 "$M9LOG" | indent
if grep -q '^TIER_M9 PASS ' "$M9LOG" && ! grep -q '^TIER_M9 FAIL ' "$M9LOG"; then
    pass_case "tier_m9_px summary PASS"
else
    fail_case "tier_m9_px summary missing/FAIL"
fi
if grep -q '^FAIL - ' "$M9LOG"; then
    fail_case "tier_m9_px reported a FAIL line"
else
    pass_case "tier_m9_px reports no failing-case lines"
fi

# Pin the M10 art_test cases the tier relies on, using the nested M9 log (the
# M9 tier itself is unchanged).
M10_ART_LOG="$OUT/m9/art_test/run.log"
for c in assets_manifest_decode_26a_12v background_one_resident_slot \
    assets_missing_fallback_deterministic assets_malformed_v_manifest_falls_back; do
    require_case "$M10_ART_LOG" "$c"
done

echo
echo "== tier_m10_assets summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M10 FAIL $PASSES passed / $FAILS failed"
    exit 1
fi
echo "TIER_M10 PASS $PASSES passed / $FAILS failed"
exit 0
