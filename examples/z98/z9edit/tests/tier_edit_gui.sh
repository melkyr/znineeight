#!/bin/sh
# tier_edit_gui.sh — Phase 2 P4-M3 gate for the z9edit GUI shell.
#
# POSIX sh. Run from anywhere (paths resolved from this script).
#
# (a) Build examples/z98/z9edit/main.zig no-CRT for Win9x through
#     scripts/win32_cross/cross_nocrt.sh (DUMP_TARGET=-osw so std_time/std_os
#     take the win32 branches; EXTRA_LIBS/EXTRA_CSRC for DDraw/GDI/User +
#     the stdcall WndProc trampoline). PE32 i386, imports DDRAW/GDI32/USER32,
#     never MSVCRT, and passes the closed-world 9x import gate.
# (b) Compile max RSS of main.zig (--dump-c89) < 16 MB.
# (c) Xvfb + Wine: `z9edit.exe --smoke edit_smoke.z98 out.tmp` twice, exit 0,
#     out.tmp byte-identical to tests/fixtures/edit_smoke.expected both times.
#     The first run also proves the real window: READY sentinel -> screenshot.
#     If Xvfb/wine/import are genuinely absent it prints explicit
#     operator-hardware lines (never a silent skip). Runtime Wine RSS recorded,
#     not gated (includes Wine overhead); real Win98 numbers are operator-owned.
#
# Env: ZIG        compiler (default /tmp/p4_t1_build/zig1_5_clean)
#      OUT        scratch dir (default /tmp/z9edit_gui_tier)
#      WINEPREFIX isolated prefix (default $OUT/wineprefix_x)
#      Z9_NO_XVFB=1  skip the Wine/Xvfb tier with an explicit line
#
# Exits non-zero on any executed gate failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ENTRY="examples/z98/z9edit/main.zig"
ZIG="${ZIG:-/tmp/p4_t1_build/zig1_5_clean}"
OUT="${OUT:-/tmp/z9edit_gui_tier}"
CROSS="$ROOT/scripts/win32_cross/cross_nocrt.sh"
CHECK="$ROOT/scripts/win32_cross/check_win9x_imports.sh"
EXE="$OUT/z9edit.exe"
FIXTURE="$SCRIPT_DIR/fixtures/edit_smoke.z98"
EXPECTED="$SCRIPT_DIR/fixtures/edit_smoke.expected"
WINE_PREFIX="${WINEPREFIX:-$OUT/wineprefix_x}"
export WINEPREFIX="$WINE_PREFIX"
export WINEARCH=win32
export WINEDEBUG="${WINEDEBUG:--all}"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

XVFB_PID=""
WINE_PID=""
cleanup() {
    if [ -n "$WINE_PID" ]; then kill "$WINE_PID" 2>/dev/null || true; fi
    wineserver -k >/dev/null 2>&1 || true
    if [ -n "$XVFB_PID" ]; then kill "$XVFB_PID" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p4_t1_build"
    exit 1
fi
for tool in i686-w64-mingw32-gcc i686-w64-mingw32-objdump file md5sum; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required host tool not found: $tool"
        exit 1
    fi
done
if [ ! -f "$FIXTURE" ]; then
    echo "FAIL: fixture missing: $FIXTURE"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

cd "$ROOT" || exit 1

# ---- (a) no-CRT build + import gate ---------------------------------------
echo "== (a) no-CRT build + import gate =="
BUILD_LOG="$OUT/build.log"
EXTRA_LIBS="-luser32 -lgdi32 -lddraw" \
EXTRA_CSRC="$ROOT/sf/src/include/zig_gfx_wndproc.c" \
DUMP_TARGET="-osw" \
    bash "$CROSS" "$ZIG" "$ENTRY" "$OUT/work" "$EXE" >"$BUILD_LOG" 2>&1
BUILD_RC=$?
tail -3 "$BUILD_LOG" | sed 's/^/       /'
if [ "$BUILD_RC" -eq 0 ] && [ -f "$EXE" ]; then
    pass_case "no-CRT Win9x build produced z9edit.exe"
else
    fail_case "no-CRT build failed (rc=$BUILD_RC; see $BUILD_LOG)"
    echo
    echo "== tier_edit_gui summary: $PASSES passed, $FAILS failed =="
    echo "TIER_EDIT_GUI FAIL"
    exit 1
fi

FILEOUT="$(file "$EXE" 2>/dev/null)"
case "$FILEOUT" in
    *PE32*Intel\ 80386*) pass_case "file: $FILEOUT" ;;
    *) fail_case "not a PE32 i386 executable: ${FILEOUT:-<none>}" ;;
esac

if bash "$CHECK" "$EXE" 9x >"$OUT/imports.log" 2>&1; then
    pass_case "check_win9x_imports.sh 9x PASS"
else
    fail_case "check_win9x_imports.sh 9x FAILED (see $OUT/imports.log)"
fi
sed 's/^/       /' "$OUT/imports.log"

DLLS="$(i686-w64-mingw32-objdump -p "$EXE" 2>/dev/null \
    | sed -n 's/.*DLL Name: //p' | tr -d '\r' | tr '[:lower:]' '[:upper:]' | sort -u)"
echo "$DLLS" | sed 's/^/       DLL /'
MISSING_DLL=""
for d in DDRAW.DLL GDI32.DLL USER32.DLL; do
    echo "$DLLS" | grep -qx "$d" || MISSING_DLL="$MISSING_DLL $d"
done
if [ -z "$MISSING_DLL" ]; then
    pass_case "DLL imports include DDRAW.DLL + GDI32.DLL + USER32.DLL"
else
    fail_case "missing DLL import(s):$MISSING_DLL"
fi
if echo "$DLLS" | grep -qx 'MSVCRT.DLL'; then
    fail_case "MSVCRT.DLL imported on the no-CRT profile"
else
    pass_case "no MSVCRT.DLL import"
fi

# ---- (b) compile max RSS (< 16 MB) ---------------------------------------
echo "== (b) compile max RSS (z9edit/main.zig, -osw --dump-c89) =="
COMPILE_RSS="n/a"
if command -v /usr/bin/time >/dev/null 2>&1; then
    mkdir -p "$OUT/rss_dump"
    /usr/bin/time -v -o "$OUT/zig_time.log" \
        "$ZIG" -osw --dump-c89 --output-dir "$OUT/rss_dump" "$ENTRY" \
        >"$OUT/zig_dump.log" 2>&1
    RSS_RC=$?
    COMPILE_RSS=$(sed -n 's/.*Maximum resident set size (kbytes): //p' "$OUT/zig_time.log" | tail -1)
    [ -n "$COMPILE_RSS" ] || COMPILE_RSS="n/a"
    if [ "$RSS_RC" -ne 0 ]; then
        fail_case "Z98 --dump-c89 RSS probe failed (rc=$RSS_RC; see $OUT/zig_dump.log)"
    fi
else
    echo "operator-hardware: Z98 compile RSS not measured (/usr/bin/time absent)"
fi
if [ "$COMPILE_RSS" = "n/a" ]; then
    echo "compile max RSS: not measured"
elif [ "$COMPILE_RSS" -lt 16384 ]; then
    pass_case "Z98 compile max RSS < 16 MB (${COMPILE_RSS} kB)"
else
    fail_case "Z98 compile max RSS >= 16 MB (${COMPILE_RSS} kB)"
fi

# ---- (c) Xvfb + Wine: window smoke + 2x save-byte golden -----------------
echo "== (c) Xvfb + Wine: window smoke + 2x save-byte golden =="
MISSING_X=""
for tool in Xvfb xdpyinfo wineboot import identify timeout; do
    command -v "$tool" >/dev/null 2>&1 || MISSING_X="$MISSING_X $tool"
done
command -v wine >/dev/null 2>&1 || MISSING_X="$MISSING_X wine"
if [ ! -f "$EXPECTED" ]; then
    fail_case "expected fixture missing: $EXPECTED"
fi
if [ "${Z9_NO_XVFB:-0}" = "1" ]; then
    echo "operator-hardware: z9edit window + --smoke tier skipped by Z9_NO_XVFB=1"
    echo "operator-hardware: run z9edit.exe --smoke edit_smoke.z98 out.tmp under Wine/Xvfb or Win98"
elif [ -n "$MISSING_X" ]; then
    echo "operator-hardware: z9edit window + --smoke tier not run (missing:$MISSING_X)"
    echo "operator-hardware: run z9edit.exe --smoke edit_smoke.z98 out.tmp on Win98 with X-equivalent display"
else
    wineserver -k >/dev/null 2>&1 || true
    SHOT_DIR="$OUT/shot"
    mkdir -p "$SHOT_DIR"
    DISPLAY_NUM=":77"
    export DISPLAY="$DISPLAY_NUM"
    Xvfb "$DISPLAY_NUM" -screen 0 1024x768x24 -nolisten tcp \
        >"$SHOT_DIR/xvfb.log" 2>&1 &
    XVFB_PID=$!
    i=0
    while [ "$i" -lt 50 ]; do
        if xdpyinfo >/dev/null 2>&1; then break; fi
        sleep 0.1
        i=$((i + 1))
    done
    if ! xdpyinfo >/dev/null 2>&1; then
        fail_case "Xvfb did not come up on $DISPLAY_NUM"
    else
        pass_case "Xvfb up on $DISPLAY_NUM"
        timeout 180 wineboot -i >"$SHOT_DIR/wineboot.log" 2>&1 || true

        # Run 1: real window + READY + screenshot + save bytes.
        RUN1="$OUT/run1"
        mkdir -p "$RUN1"
        cp "$FIXTURE" "$RUN1/edit_smoke.z98"
        ( cd "$RUN1" && timeout 120 wine "$EXE" --smoke edit_smoke.z98 out.tmp ) \
            >"$RUN1/app.log" 2>&1 &
        WINE_PID=$!
        READY_SEEN=0
        i=0
        while [ "$i" -lt 200 ]; do
            if grep -q '^READY$' "$RUN1/app.log" 2>/dev/null; then
                READY_SEEN=1
                break
            fi
            sleep 0.1
            i=$((i + 1))
        done
        if [ "$READY_SEEN" -eq 1 ]; then
            pass_case "READY sentinel seen (windowed run 1)"
        else
            fail_case "READY sentinel not seen (see $RUN1/app.log)"
        fi
        sleep 0.5
        if timeout 30 import -window root "$SHOT_DIR/shot.png" >"$SHOT_DIR/import.log" 2>&1 \
            && [ -s "$SHOT_DIR/shot.png" ]; then
            STATS="$(identify -format '%[fx:mean] %[fx:standard_deviation] %k' \
                "$SHOT_DIR/shot.png" 2>/dev/null)"
            pass_case "screenshot saved: $SHOT_DIR/shot.png (mean/stddev/colors: $STATS)"
        else
            fail_case "screenshot capture failed (see $SHOT_DIR/import.log)"
        fi
        wait "$WINE_PID" 2>/dev/null
        APP_RC=$?
        WINE_PID=""
        if [ "$APP_RC" -eq 0 ]; then
            pass_case "windowed --smoke run 1 exited 0"
        else
            fail_case "windowed --smoke run 1 exited $APP_RC (see $RUN1/app.log)"
        fi
        HR_MISSING=""
        for pat in \
            'DirectDrawCreate hr=0x00000000' \
            'QueryInterface(IID_IDirectDraw7) hr=0x00000000' \
            'CreateSurface(primary) hr=0x00000000' \
            'CreateSurface(offscreen) hr=0x00000000' \
            'Blt(primary<-offscreen) hr=0x00000000'; do
            grep -Fq "$pat" "$RUN1/app.log" || HR_MISSING="$HR_MISSING [$pat]"
        done
        if [ -z "$HR_MISSING" ]; then
            pass_case "DDraw HRESULT evidence (create/QI/surfaces/Blt all 0x0)"
        else
            fail_case "missing DDraw HRESULT line(s):$HR_MISSING"
        fi
        if [ -f "$RUN1/out.tmp" ]; then
            MD1="$(md5sum "$RUN1/out.tmp" | cut -d' ' -f1)"
            if cmp -s "$RUN1/out.tmp" "$EXPECTED"; then
                pass_case "run 1 save bytes match edit_smoke.expected (md5 $MD1)"
            else
                fail_case "run 1 save bytes differ from expected (md5 $MD1)"
            fi
        else
            fail_case "run 1 did not write out.tmp"
            MD1=""
        fi

        # Run 2: deterministic repeat + runtime RSS.
        RUN2="$OUT/run2"
        mkdir -p "$RUN2"
        cp "$FIXTURE" "$RUN2/edit_smoke.z98"
        RUNTIME_RSS="n/a"
        if command -v /usr/bin/time >/dev/null 2>&1; then
            ( cd "$RUN2" && /usr/bin/time -v -o "$OUT/runtime_time.log" \
                timeout 120 wine "$EXE" --smoke edit_smoke.z98 out.tmp ) \
                >"$RUN2/app.log" 2>&1
            APP2_RC=$?
            RUNTIME_RSS=$(sed -n 's/.*Maximum resident set size (kbytes): //p' "$OUT/runtime_time.log" | tail -1)
            [ -n "$RUNTIME_RSS" ] || RUNTIME_RSS="n/a"
        else
            ( cd "$RUN2" && timeout 120 wine "$EXE" --smoke edit_smoke.z98 out.tmp ) \
                >"$RUN2/app.log" 2>&1
            APP2_RC=$?
        fi
        if [ "$APP2_RC" -eq 0 ]; then
            pass_case "windowed --smoke run 2 exited 0"
        else
            fail_case "windowed --smoke run 2 exited $APP2_RC (see $RUN2/app.log)"
        fi
        if [ -f "$RUN2/out.tmp" ]; then
            MD2="$(md5sum "$RUN2/out.tmp" | cut -d' ' -f1)"
            if cmp -s "$RUN2/out.tmp" "$EXPECTED"; then
                pass_case "run 2 save bytes match edit_smoke.expected (md5 $MD2)"
            else
                fail_case "run 2 save bytes differ from expected (md5 $MD2)"
            fi
            if [ -n "$MD1" ] && [ "$MD1" = "$MD2" ]; then
                pass_case "save bytes byte-identical 2x ($MD1)"
            else
                fail_case "save bytes not byte-identical 2x ($MD1 / $MD2)"
            fi
        else
            fail_case "run 2 did not write out.tmp"
        fi
        if [ "$RUNTIME_RSS" = "n/a" ]; then
            echo "operator-hardware: runtime RSS not measured (/usr/bin/time absent)"
        else
            pass_case "runtime RSS recorded (Wine-hosted, includes Wine): ${RUNTIME_RSS} kB"
        fi
        sed 's/^/       /' "$RUN1/app.log" | tail -8

        wineserver -k >/dev/null 2>&1 || true
        kill "$XVFB_PID" 2>/dev/null || true
        wait "$XVFB_PID" 2>/dev/null || true
        XVFB_PID=""
    fi
fi
echo "operator-hardware: interactive edit/select/undo/save on real Win98 not measured (Wine smoke is not hardware proof)"

echo
echo "== tier_edit_gui summary: $PASSES passed, $FAILS failed =="
echo "compile max RSS: ${COMPILE_RSS} KiB"
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_EDIT_GUI FAIL"
    exit 1
fi
echo "TIER_EDIT_GUI PASS"
exit 0
