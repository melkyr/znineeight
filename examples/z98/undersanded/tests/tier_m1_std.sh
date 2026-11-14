#!/bin/sh
# tier_m1_std.sh — UNDERSANDED M1 acceptance tier (spec §26/§32/§33).
#
# FAST (the gate):
#   * build both no-CRT Win9x exes with `build.sh` (-fsafe -W warning-clean)
#   * `check_win9x_imports.sh <exe> 9x` on under.exe AND undtool.exe
#   * native game-side driver: tests/paths_test.zig via `zig1 -osl`, native
#     Linux build_target.sh, run (PASS + exit 0; crc32/8.3/paths/writability/
#     fallback + std_parse.parseInt/itoa reuse)
#   * std fixtures: stdlib_str_splitonce_xmod + stdlib_crypto_crc32_xmod
#   * z9edit tier_edit.sh green, lexer goldens byte-identical (md5 pinned)
#   * no committed .py tooling under examples/z98/undersanded/
#
# SLOW (Wine/operator evidence, never a silent skip):
#   * undtool.exe in a writable temp workdir: exit 0, probe_out.txt == sample
#   * undtool.exe from a chmod 0555 workdir: exit 0, exe dir gains no file, the
#     C:\WINDOWS\TEMP\UNDERSAN\ fallback is used and its output is recorded
#   * under.exe under Xvfb + Wine: an UNDERSANDED-titled window opens, exit 0
#   Missing wine/Xvfb prints explicit operator-hardware lines. An executed
#   evidence check that fails prints EVIDENCE-FAIL and makes the tier nonzero.
#
# Env: ZIG  compiler (default /tmp/zig1-m1/zig1_5_clean)
#      OUT  scratch dir (default /tmp/undersanded_m1_tier)
#
# Run from anywhere (paths resolved from this script). Exits non-zero on any
# executed gate/evidence failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNDDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$UNDDIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/zig1-m1/zig1_5_clean}"
OUT="${OUT:-/tmp/undersanded_m1_tier}"
BUILD_OUT="$OUT/build"
CHECK="$ROOT/scripts/win32_cross/check_win9x_imports.sh"
SAMPLE="$SCRIPT_DIR/fixtures/sample.txt"
FIX_SPLIT="repro/mi_matrix/stdlib_str_splitonce_xmod"
FIX_CRC="repro/mi_matrix/stdlib_crypto_crc32_xmod"
EXPECTED_LEXER_MD5="dcc81009e9a36c86e4d90e104c439871"

PASSES=0
FAILS=0
SKIPS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }
evidence_pass() { echo "EVIDENCE - $1"; PASSES=$((PASSES + 1)); }
evidence_fail() { echo "EVIDENCE-FAIL - $1"; FAILS=$((FAILS + 1)); }
skip_evidence() { echo "operator-hardware: EVIDENCE not run: $1"; SKIPS=$((SKIPS + 1)); }

XVFB_PID=""
WINE_PID=""
RO_DIRS=""
cleanup() {
    if [ -n "$WINE_PID" ]; then kill "$WINE_PID" 2>/dev/null || true; fi
    wineserver -k >/dev/null 2>&1 || true
    if [ -n "$XVFB_PID" ]; then kill "$XVFB_PID" 2>/dev/null || true; fi
    for d in $RO_DIRS; do
        [ -d "$d" ] && chmod 0755 "$d" 2>/dev/null || true
    done
}
trap cleanup EXIT INT TERM

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/zig1-m1"
    exit 1
fi
if [ ! -f "$SAMPLE" ]; then
    echo "FAIL: fixture missing: $SAMPLE"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT" || exit 1

# ---------------------------------------------------------------------------
# FAST 1: both exes build -fsafe -W clean
# ---------------------------------------------------------------------------
echo "== FAST: build both exes (-fsafe -W) =="
if ZIG="$ZIG" OUT="$BUILD_OUT" sh examples/z98/undersanded/build.sh >"$OUT/build.log" 2>&1; then
    pass_case "build.sh built under.exe + undtool.exe (-fsafe -W clean)"
else
    fail_case "build.sh failed (see $OUT/build.log)"
    tail -20 "$OUT/build.log" | sed 's/^/       /'
fi
for n in gui cui; do
    WLOG="$BUILD_OUT/warn_$n.log"
    if [ -s "$WLOG" ] && grep -Fq 'warning[' "$WLOG"; then
        fail_case "$n -fsafe -W log contains a warning"
        grep -Fn 'warning[' "$WLOG" | sed 's/^/       /'
    else
        pass_case "$n -fsafe -W log has no warning[ markers"
    fi
done
for exe in under.exe undtool.exe; do
    if [ -f "$BUILD_OUT/$exe" ]; then
        pass_case "built $exe"
    else
        fail_case "missing $BUILD_OUT/$exe"
    fi
done

# ---------------------------------------------------------------------------
# FAST 2: closed-world 9x import gate on BOTH exes
# ---------------------------------------------------------------------------
echo "== FAST: Win9x import gate on both exes =="
for exe in under.exe undtool.exe; do
    ILOG="$OUT/imports_$exe.log"
    if [ ! -f "$BUILD_OUT/$exe" ]; then
        fail_case "import gate skipped for $exe (binary missing)"
    elif bash "$CHECK" "$BUILD_OUT/$exe" 9x >"$ILOG" 2>&1; then
        pass_case "check_win9x_imports.sh 9x PASS ($exe)"
    else
        fail_case "check_win9x_imports.sh 9x FAILED ($exe; see $ILOG)"
    fi
    [ -f "$ILOG" ] && tail -3 "$ILOG" | sed 's/^/       /'
done

# ---------------------------------------------------------------------------
# FAST 3: native game-side driver (paths_test.zig)
# ---------------------------------------------------------------------------
echo "== FAST: native game-side driver (paths_test.zig) =="
PT="$OUT/paths_test"
mkdir -p "$PT"
PT_OK=0
if "$ZIG" -osl --output-dir "$PT" examples/z98/undersanded/tests/paths_test.zig \
    >"$PT/zig.log" 2>&1; then
    pass_case "paths_test.zig emitted with zig1 -osl"
    if sh "$PT/build_target.sh" linux "$PT/paths_test" >"$PT/build.log" 2>&1; then
        pass_case "paths_test built natively (build_target.sh linux)"
        PT_OK=1
    else
        fail_case "paths_test native link failed (see $PT/build.log)"
        tail -20 "$PT/build.log" | sed 's/^/       /'
    fi
else
    fail_case "paths_test.zig compile failed (see $PT/zig.log)"
    tail -20 "$PT/zig.log" | sed 's/^/       /'
fi
if [ "$PT_OK" -eq 1 ]; then
    timeout 120 "$PT/paths_test" >"$PT/run.log" 2>&1
    PT_RC=$?
    sed 's/^/       /' "$PT/run.log"
    if [ "$PT_RC" -eq 0 ] && grep -qx 'paths_test PASS' "$PT/run.log" \
        && ! grep -q '^FAIL - ' "$PT/run.log"; then
        pass_case "paths_test exits 0 and prints 'paths_test PASS'"
    else
        fail_case "paths_test did not pass (rc=$PT_RC; see $PT/run.log)"
    fi
    for c in crc32_known_vectors path_join83 probe_writable data_dir_fallback \
        std_parse_parseInt_reuse std_parse_itoa_reuse; do
        if grep -qx "ok - $c" "$PT/run.log"; then
            pass_case "paths_test: $c"
        else
            fail_case "paths_test: $c missing/failed"
        fi
    done
else
    fail_case "paths_test run skipped (driver build failed)"
fi

# ---------------------------------------------------------------------------
# FAST 4: std fixtures (splitOnce + crc32)
# ---------------------------------------------------------------------------
echo "== FAST: std fixtures (splitOnce + crc32) =="
FIXLOG="$OUT/fixtures.log"
if bash scripts/stdlib/run_fixtures.sh "$ZIG" "$FIX_SPLIT" "$FIX_CRC" \
    >"$FIXLOG" 2>&1; then
    pass_case "run_fixtures.sh PASS (splitOnce + crc32)"
else
    fail_case "run_fixtures.sh failed (see $FIXLOG)"
    tail -20 "$FIXLOG" | sed 's/^/       /'
fi
for d in "$FIX_SPLIT" "$FIX_CRC"; do
    if grep -qx "PASS $d" "$FIXLOG"; then
        pass_case "fixture PASS: $d"
    else
        fail_case "fixture FAIL/missing: $d"
    fi
done
if grep -q 'run_fixtures: 2 PASS / 0 FAIL' "$FIXLOG"; then
    pass_case "fixture summary: 2 PASS / 0 FAIL"
else
    fail_case "fixture summary is not 2 PASS / 0 FAIL"
fi

# ---------------------------------------------------------------------------
# FAST 5: z9edit tier + unchanged lexer goldens
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
        pass_case "z9edit lexer md5 matches M1 baseline ($MD1)"
    else
        fail_case "z9edit lexer md5 changed (got $MD1, want $EXPECTED_LEXER_MD5)"
    fi
else
    fail_case "z9edit lexer md5 line missing from tier output"
fi

# ---------------------------------------------------------------------------
# FAST 6: no committed Python tooling under the example
# ---------------------------------------------------------------------------
echo "== FAST: no committed .py tooling =="
PY_FILES="$(git -C "$ROOT" ls-files examples/z98/undersanded | grep '\.py$' || true)"
if [ -z "$PY_FILES" ]; then
    pass_case "no committed .py tooling under examples/z98/undersanded/"
else
    fail_case "committed .py tooling found under examples/z98/undersanded/"
    printf '%s\n' "$PY_FILES" | sed 's/^/       /'
fi

# ---------------------------------------------------------------------------
# SLOW evidence: Wine CUI writable + read-only fallback
# ---------------------------------------------------------------------------
echo "== SLOW evidence: Wine CUI (writable + read-only fallback) =="
MISSING_WINE=""
for tool in wine wineserver timeout; do
    command -v "$tool" >/dev/null 2>&1 || MISSING_WINE="$MISSING_WINE $tool"
done
if [ -n "$MISSING_WINE" ]; then
    skip_evidence "Wine CUI checks (missing:$MISSING_WINE)"
    echo "operator-hardware: run undtool.exe beside sample.txt on Win98 (exit 0 + probe_out.txt == sample.txt)"
    echo "operator-hardware: rerun from a read-only directory and confirm the C:\\WINDOWS\\TEMP\\UNDERSAN\\ fallback"
elif [ ! -f "$BUILD_OUT/undtool.exe" ]; then
    skip_evidence "Wine CUI checks (undtool.exe missing; build failed)"
else
    export WINEPREFIX="$OUT/wineprefix_cui"
    export WINEARCH=win32
    export WINEDEBUG="${WINEDEBUG:--all}"

    # (a) writable exe dir: exit 0 + probe_out.txt bytes match sample.txt.
    CUI="$OUT/cui_writable"
    mkdir -p "$CUI"
    cp "$BUILD_OUT/undtool.exe" "$BUILD_OUT/sample.txt" "$CUI/"
    ( cd "$CUI" && timeout 120 wine ./undtool.exe </dev/null ) >"$CUI/run.log" 2>&1
    CUI_RC=$?
    sed 's/^/       /' "$CUI/run.log"
    if [ "$CUI_RC" -eq 0 ]; then
        evidence_pass "undtool.exe writable run exited 0"
    else
        evidence_fail "undtool.exe writable run exited $CUI_RC (see $CUI/run.log)"
    fi
    if [ -f "$CUI/probe_out.txt" ] && cmp -s "$CUI/probe_out.txt" "$SAMPLE"; then
        CUI_MD="$(md5sum "$CUI/probe_out.txt" | cut -d' ' -f1)"
        evidence_pass "undtool probe_out.txt matches sample.txt (md5 $CUI_MD)"
    else
        evidence_fail "undtool probe_out.txt missing or differs from sample.txt"
    fi

    # (b) read-only exe dir: no file appears there; the fallback is used.
    RO="$OUT/cui_readonly"
    mkdir -p "$RO"
    cp "$BUILD_OUT/undtool.exe" "$BUILD_OUT/sample.txt" "$RO/"
    RO_BEFORE="$(find "$RO" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d '[:space:]')"
    chmod 0555 "$RO"
    RO_DIRS="$RO"
    ( cd "$RO" && timeout 120 wine ./undtool.exe </dev/null ) >"$OUT/cui_readonly.log" 2>&1
    RO_RC=$?
    sed 's/^/       /' "$OUT/cui_readonly.log"
    RO_AFTER="$(find "$RO" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d '[:space:]')"
    if [ "$RO_RC" -eq 0 ]; then
        evidence_pass "undtool.exe read-only-dir run exited 0"
    else
        evidence_fail "undtool.exe read-only-dir run exited $RO_RC (see $OUT/cui_readonly.log)"
    fi
    if grep -q '(read-only)$' "$OUT/cui_readonly.log"; then
        evidence_pass "undtool.exe detected the exe dir as read-only"
    else
        evidence_fail "undtool.exe did not report the exe dir as read-only"
    fi
    if grep -Fqx 'writable_dir=C:\WINDOWS\TEMP\UNDERSAN\' "$OUT/cui_readonly.log"; then
        evidence_pass "read-only run selected fallback C:\\WINDOWS\\TEMP\\UNDERSAN\\"
    else
        evidence_fail "read-only run did not select the C:\\WINDOWS\\TEMP\\UNDERSAN\\ fallback"
    fi
    if [ "$RO_AFTER" = "$RO_BEFORE" ] && [ ! -e "$RO/probe_out.txt" ]; then
        evidence_pass "read-only exe dir gained no file (still $RO_AFTER files)"
    else
        evidence_fail "read-only exe dir changed ($RO_BEFORE -> $RO_AFTER files)"
    fi
    FOUND="$(find "$WINEPREFIX/drive_c" -type f -iname 'probe_out.txt' 2>/dev/null | head -1)"
    if [ -n "$FOUND" ] && cmp -s "$FOUND" "$SAMPLE" \
        && printf '%s\n' "$FOUND" | grep -qi 'drive_c/windows/temp/UNDERSAN/probe_out.txt'; then
        evidence_pass "fallback probe_out.txt landed at $FOUND (bytes match sample)"
    else
        evidence_fail "fallback probe_out.txt not found under the Wine prefix (recorded: ${FOUND:-<none>})"
    fi
    chmod 0755 "$RO"
    RO_DIRS=""
fi

# ---------------------------------------------------------------------------
# SLOW evidence: under.exe window opens under Xvfb + Wine, exit 0
# ---------------------------------------------------------------------------
echo "== SLOW evidence: under.exe window under Xvfb + Wine =="
MISSING_X=""
for tool in Xvfb xdpyinfo xwininfo import identify; do
    command -v "$tool" >/dev/null 2>&1 || MISSING_X="$MISSING_X $tool"
done
if [ -n "$MISSING_WINE" ]; then
    skip_evidence "under.exe window check (missing:$MISSING_WINE)"
elif [ -n "$MISSING_X" ]; then
    skip_evidence "under.exe window check (missing:$MISSING_X)"
    echo "operator-hardware: run under.exe on Win98 and confirm the UNDERSANDED window opens and it exits 0"
elif [ ! -f "$BUILD_OUT/under.exe" ]; then
    skip_evidence "under.exe window check (under.exe missing; build failed)"
else
    wineserver -k >/dev/null 2>&1 || true
    export WINEPREFIX="$OUT/wineprefix_gui"
    export WINEARCH=win32
    export WINEDEBUG="${WINEDEBUG:--all}"
    GUI="$OUT/gui_window"
    mkdir -p "$GUI"
    DISPLAY_NUM=":79"
    export DISPLAY="$DISPLAY_NUM"
    Xvfb "$DISPLAY_NUM" -screen 0 1024x768x24 -nolisten tcp \
        >"$GUI/xvfb.log" 2>&1 &
    XVFB_PID=$!
    i=0
    while [ "$i" -lt 50 ]; do
        if xdpyinfo >/dev/null 2>&1; then break; fi
        sleep 0.1
        i=$((i + 1))
    done
    if ! xdpyinfo >/dev/null 2>&1; then
        evidence_fail "Xvfb did not come up on $DISPLAY_NUM"
    else
        timeout 180 wineboot -i >"$GUI/wineboot.log" 2>&1 || true
        cp "$BUILD_OUT/under.exe" "$BUILD_OUT/sample.txt" "$GUI/"
        ( cd "$GUI" && timeout 120 wine ./under.exe ) >"$GUI/app.log" 2>&1 &
        WINE_PID=$!
        WINDOW_SEEN=0
        i=0
        while [ "$i" -lt 400 ]; do
            if xwininfo -root -tree 2>/dev/null | grep -q 'UNDERSANDED'; then
                WINDOW_SEEN=1
                break
            fi
            sleep 0.05
            i=$((i + 1))
        done
        timeout 30 import -window root "$GUI/shot.png" >"$GUI/import.log" 2>&1 || true
        wait "$WINE_PID" 2>/dev/null
        GUI_RC=$?
        WINE_PID=""
        if [ "$WINDOW_SEEN" -eq 1 ]; then
            evidence_pass "under.exe opened a window titled UNDERSANDED (Xvfb $DISPLAY_NUM)"
        else
            evidence_fail "under.exe window titled UNDERSANDED not seen (see $GUI/app.log)"
        fi
        if [ "$GUI_RC" -eq 0 ]; then
            evidence_pass "under.exe windowed run exited 0"
        else
            evidence_fail "under.exe windowed run exited $GUI_RC (see $GUI/app.log)"
        fi
        if [ -s "$GUI/shot.png" ]; then
            GUISTATS="$(identify -format '%[fx:mean] %[fx:standard_deviation] %k' \
                "$GUI/shot.png" 2>/dev/null)"
            evidence_pass "screenshot recorded: $GUI/shot.png (mean/stddev/colors: $GUISTATS)"
        else
            echo "operator-hardware: screenshot not captured (window proof is the xwininfo tree)"
        fi
        if [ -f "$GUI/probe_out.txt" ] && cmp -s "$GUI/probe_out.txt" "$SAMPLE"; then
            GUI_MD="$(md5sum "$GUI/probe_out.txt" | cut -d' ' -f1)"
            evidence_pass "windowed under.exe wrote probe_out.txt matching sample (md5 $GUI_MD)"
        else
            evidence_fail "windowed under.exe probe_out.txt missing or differs from sample"
        fi
        sed 's/^/       /' "$GUI/app.log" | tail -8
    fi
    kill "$XVFB_PID" 2>/dev/null || true
    wait "$XVFB_PID" 2>/dev/null || true
    XVFB_PID=""
    wineserver -k >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# SLOW evidence: gfx_demo live event selftest under Xvfb + Wine
# ---------------------------------------------------------------------------
echo "== SLOW evidence: gfx_demo event selftest under Xvfb + Wine =="
MISSING_GFX_X=""
for tool in Xvfb xdpyinfo; do
    command -v "$tool" >/dev/null 2>&1 || MISSING_GFX_X="$MISSING_GFX_X $tool"
done
if [ -n "$MISSING_WINE" ]; then
    skip_evidence "gfx_demo event selftest (missing:$MISSING_WINE)"
    echo "operator-hardware: run gfx_demo.exe --event-selftest on Win98 and confirm EVENT_SELFTEST OK"
elif [ -n "$MISSING_GFX_X" ]; then
    skip_evidence "gfx_demo event selftest (missing:$MISSING_GFX_X)"
    echo "operator-hardware: run gfx_demo.exe --event-selftest on Win98 and confirm EVENT_SELFTEST OK"
else
    wineserver -k >/dev/null 2>&1 || true
    GFX_EV="$OUT/gfx_ev"
    mkdir -p "$GFX_EV"
    if ROOT="$ROOT" EXTRA_LIBS="-luser32 -lgdi32" \
        bash scripts/win32_cross/cross_nocrt.sh "$ZIG" examples/z98/gfx_demo/main.zig \
        "$GFX_EV/work" "$GFX_EV/gfx_demo.exe" >"$GFX_EV/build.log" 2>&1; then
        evidence_pass "gfx_demo.exe built (no-CRT, EXTRA_LIBS=-luser32 -lgdi32)"
    else
        evidence_fail "gfx_demo.exe build failed (see $GFX_EV/build.log)"
        tail -20 "$GFX_EV/build.log" | sed 's/^/       /'
    fi
    if [ -f "$GFX_EV/gfx_demo.exe" ]; then
        export WINEPREFIX="$OUT/wineprefix_gfx_ev"
        export WINEARCH=win32
        export WINEDEBUG="${WINEDEBUG:--all}"
        DISPLAY_NUM=":80"
        export DISPLAY="$DISPLAY_NUM"
        Xvfb "$DISPLAY_NUM" -screen 0 1024x768x24 -nolisten tcp \
            >"$GFX_EV/xvfb.log" 2>&1 &
        XVFB_PID=$!
        i=0
        while [ "$i" -lt 50 ]; do
            if xdpyinfo >/dev/null 2>&1; then break; fi
            sleep 0.1
            i=$((i + 1))
        done
        if ! xdpyinfo >/dev/null 2>&1; then
            evidence_fail "Xvfb did not come up on $DISPLAY_NUM (gfx_demo event selftest)"
        else
            timeout 180 wineboot -i >"$GFX_EV/wineboot.log" 2>&1 || true
            ( cd "$GFX_EV" && timeout 120 wine ./gfx_demo.exe --event-selftest ) \
                >"$GFX_EV/event_selftest.log" 2>&1
            EV_RC=$?
            sed 's/^/       /' "$GFX_EV/event_selftest.log"
            if [ "$EV_RC" -eq 0 ] && grep -qx 'EVENT_SELFTEST OK' "$GFX_EV/event_selftest.log"; then
                evidence_pass "gfx_demo --event-selftest printed EVENT_SELFTEST OK (exit 0)"
            else
                evidence_fail "gfx_demo --event-selftest failed (rc=$EV_RC; see $GFX_EV/event_selftest.log)"
            fi
        fi
        kill "$XVFB_PID" 2>/dev/null || true
        wait "$XVFB_PID" 2>/dev/null || true
        XVFB_PID=""
        wineserver -k >/dev/null 2>&1 || true
    fi
fi

echo "operator-hardware: Wine/Xvfb evidence is not Win98 hardware proof; real Win98 run is operator-owned"

echo
echo "== tier_m1_std summary: $PASSES passed, $FAILS failed, $SKIPS evidence skips =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_M1 FAIL"
    exit 1
fi
echo "TIER_M1 PASS"
exit 0
