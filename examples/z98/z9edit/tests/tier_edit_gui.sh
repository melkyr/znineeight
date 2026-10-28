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
CONSOLE_EXE="$OUT/z9edit_console.exe"
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
CONSOLE_BUILD_LOG="$OUT/build_console.log"
EXTRA_LIBS="-luser32 -lgdi32 -lddraw" \
EXTRA_CSRC="$ROOT/sf/src/include/zig_gfx_wndproc.c" \
DUMP_TARGET="-osw" \
    bash "$CROSS" "$ZIG" "$ENTRY" "$OUT/work_console" "$CONSOLE_EXE" >"$CONSOLE_BUILD_LOG" 2>&1
CONSOLE_RC=$?
EXTRA_LIBS="-luser32 -lgdi32 -lddraw" \
EXTRA_CSRC="$ROOT/sf/src/include/zig_gfx_wndproc.c" \
DUMP_TARGET="-osw" \
EXTRA_LDFLAGS="-Wl,--subsystem,windows" \
    bash "$CROSS" "$ZIG" "$ENTRY" "$OUT/work_gui" "$EXE" >"$BUILD_LOG" 2>&1
BUILD_RC=$?
tail -3 "$BUILD_LOG" | sed 's/^/       /'
if [ "$BUILD_RC" -eq 0 ] && [ -f "$EXE" ]; then
    pass_case "no-CRT Win9x GUI-subsystem build produced z9edit.exe"
else
    fail_case "GUI no-CRT build failed (rc=$BUILD_RC; see $BUILD_LOG)"
    echo
    echo "== tier_edit_gui summary: $PASSES passed, $FAILS failed =="
    echo "TIER_EDIT_GUI FAIL"
    exit 1
fi
if [ "$CONSOLE_RC" -eq 0 ] && [ -f "$CONSOLE_EXE" ]; then
    pass_case "no-CRT console/test variant produced z9edit_console.exe"
else
    fail_case "console no-CRT build failed (rc=$CONSOLE_RC; see $CONSOLE_BUILD_LOG)"
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
GUI_SUBSYS="$(i686-w64-mingw32-objdump -p "$EXE" 2>/dev/null | grep '^Subsystem' | head -1)"
CON_SUBSYS="$(i686-w64-mingw32-objdump -p "$CONSOLE_EXE" 2>/dev/null | grep '^Subsystem' | head -1)"
if echo "$GUI_SUBSYS" | grep -q 'Windows GUI'; then
    pass_case "shipping exe is GUI subsystem ($GUI_SUBSYS)"
else
    fail_case "shipping exe is not GUI subsystem (${GUI_SUBSYS:-<none>})"
fi
if echo "$CON_SUBSYS" | grep -q 'Windows CUI'; then
    pass_case "console/test exe is CUI subsystem ($CON_SUBSYS)"
else
    fail_case "console/test exe is not CUI subsystem (${CON_SUBSYS:-<none>})"
fi

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
        ( cd "$RUN1" && timeout 120 wine "$CONSOLE_EXE" --smoke edit_smoke.z98 out.tmp ) \
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

        # Run 1b: save over an existing target (Windows remove+rename path).
        ( cd "$RUN1" && timeout 120 wine "$CONSOLE_EXE" --smoke edit_smoke.z98 out.tmp ) \
            >"$RUN1/app_overwrite.log" 2>&1
        OW_RC=$?
        if [ "$OW_RC" -eq 0 ] && cmp -s "$RUN1/out.tmp" "$EXPECTED"; then
            pass_case "overwrite-existing save exited 0 and matched expected"
        else
            fail_case "overwrite-existing save failed (rc=$OW_RC; see $RUN1/app_overwrite.log)"
        fi

        # Run 2: deterministic repeat + runtime RSS.
        RUN2="$OUT/run2"
        mkdir -p "$RUN2"
        cp "$FIXTURE" "$RUN2/edit_smoke.z98"
        RUNTIME_RSS="n/a"
        if command -v /usr/bin/time >/dev/null 2>&1; then
            ( cd "$RUN2" && /usr/bin/time -v -o "$OUT/runtime_time.log" \
                timeout 120 wine "$CONSOLE_EXE" --smoke edit_smoke.z98 out.tmp ) \
                >"$RUN2/app.log" 2>&1
            APP2_RC=$?
            RUNTIME_RSS=$(sed -n 's/.*Maximum resident set size (kbytes): //p' "$OUT/runtime_time.log" | tail -1)
            [ -n "$RUNTIME_RSS" ] || RUNTIME_RSS="n/a"
        else
            ( cd "$RUN2" && timeout 120 wine "$CONSOLE_EXE" --smoke edit_smoke.z98 out.tmp ) \
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

        # Run 3: a failed save must not kill the session (I-1). The temp path is
        # a directory, so the temp write fails deterministically; the editor
        # must stay alive through the scripted Ctrl+Q and exit 0 without
        # creating the target.
        FAILRUN="$OUT/fail_save"
        mkdir -p "$FAILRUN/out.tmp.z9tmp"
        cp "$FIXTURE" "$FAILRUN/edit_smoke.z98"
        ( cd "$FAILRUN" && timeout 120 wine "$CONSOLE_EXE" --smoke edit_smoke.z98 out.tmp ) \
            >"$OUT/failsave.log" 2>&1
        FAIL_RC=$?
        if [ "$FAIL_RC" -eq 0 ]; then
            pass_case "save-failure run exited 0 (session survived)"
        else
            fail_case "save-failure run exited $FAIL_RC (session died)"
        fi
        if [ ! -f "$FAILRUN/out.tmp" ]; then
            pass_case "failed temp write did not create the target"
        else
            fail_case "failed temp write unexpectedly created the target"
        fi

        # Backup-restore failure: existing target, and .z9bak is a directory so
        # moving the original aside fails. The original must survive and the
        # temp must be cleaned (no delete-then-rename data loss).
        BAKRUN="$OUT/bakfail"
        mkdir -p "$BAKRUN/out.tmp.z9bak"
        printf 'ORIGINAL\n' >"$BAKRUN/out.tmp"
        cp "$FIXTURE" "$BAKRUN/edit_smoke.z98"
        ( cd "$BAKRUN" && timeout 120 wine "$CONSOLE_EXE" --smoke edit_smoke.z98 out.tmp ) \
            >"$OUT/bakfail.log" 2>&1
        BAK_RC=$?
        if [ "$BAK_RC" -eq 0 ] && grep -qx 'ORIGINAL' "$BAKRUN/out.tmp" \
            && [ ! -f "$BAKRUN/out.tmp.z9tmp" ]; then
            pass_case "failed Windows replace preserved the original target"
        else
            fail_case "failed Windows replace lost/changed the original (rc=$BAK_RC)"
        fi

        # A save over an existing directory must fail and leave it untouched.
        DIRRUN="$OUT/dirsave"
        mkdir -p "$DIRRUN/out.tmp"
        printf 'KEEP\n' >"$DIRRUN/out.tmp/keep.txt"
        cp "$FIXTURE" "$DIRRUN/edit_smoke.z98"
        ( cd "$DIRRUN" && timeout 120 wine "$CONSOLE_EXE" --smoke edit_smoke.z98 out.tmp ) \
            >"$OUT/dirsave.log" 2>&1
        DIR_RC=$?
        if [ "$DIR_RC" -eq 0 ] && [ -d "$DIRRUN/out.tmp" ] \
            && [ -f "$DIRRUN/out.tmp/keep.txt" ] \
            && [ ! -f "$DIRRUN/out.tmp.z9tmp" ]; then
            pass_case "save over an existing directory refused; directory survives"
        else
            fail_case "save over a directory changed/lost it (rc=$DIR_RC)"
        fi

        # A stale .z9bak must be cleared, not block an overwrite save.
        STALE="$OUT/stalebak"
        mkdir -p "$STALE"
        printf 'OLD\n' >"$STALE/out.tmp"
        printf 'STALE\n' >"$STALE/out.tmp.z9bak"
        cp "$FIXTURE" "$STALE/edit_smoke.z98"
        ( cd "$STALE" && timeout 120 wine "$CONSOLE_EXE" --smoke edit_smoke.z98 out.tmp ) \
            >"$OUT/stalebak.log" 2>&1
        STALE_RC=$?
        if [ "$STALE_RC" -eq 0 ] && cmp -s "$STALE/out.tmp" "$EXPECTED" \
            && [ ! -f "$STALE/out.tmp.z9bak" ]; then
            pass_case "stale .z9bak cleared; overwrite save succeeds"
        else
            fail_case "stale .z9bak blocked or changed the save (rc=$STALE_RC)"
        fi

        # Wheel direction (headless memory Gfx, no window).
        WHEEL_LOG="$OUT/wheeltest.log"
        if timeout 60 wine "$CONSOLE_EXE" --wheel-test >"$WHEEL_LOG" 2>&1 \
            && grep -q 'WHEELTEST OK' "$WHEEL_LOG"; then
            pass_case "wheel direction positive=up / negative=down (WHEELTEST OK)"
        else
            fail_case "wheel-direction test failed (see $WHEEL_LOG)"
        fi

        # CF_TEXT clipboard: external Win32 consumer must see CRLF.
        CLIP_LOG="$OUT/cliptest.log"
        if timeout 60 wine "$CONSOLE_EXE" --clip-test >"$CLIP_LOG" 2>&1 \
            && grep -q 'CLIPTEST OK' "$CLIP_LOG"; then
            pass_case "clipboard CF_TEXT is CRLF (CLIPTEST OK)"
        else
            fail_case "clipboard CRLF test failed (see $CLIP_LOG)"
        fi

        # Pump-level VK_DELETE mapping (real WM_KEYDOWN through PostMessage).
        KEY_LOG="$OUT/keytest.log"
        if timeout 60 wine "$CONSOLE_EXE" --keytest >"$KEY_LOG" 2>&1 \
            && grep -q 'KEYTEST OK' "$KEY_LOG"; then
            pass_case "VK_DELETE pumps code=0x2E ch=127 (KEYTEST OK)"
        else
            fail_case "pump-level Delete test failed (see $KEY_LOG)"
        fi

        # Real runInteractive path: load/open/loop, minimize, restore, close.
        LIVE_LOG="$OUT/livesmoke.log"
        ( cd "$RUN1" && timeout 120 wine "$CONSOLE_EXE" --live-smoke edit_smoke.z98 ) \
            >"$LIVE_LOG" 2>&1
        LIVE_RC=$?
        LIVE_EVIDENCE=1
        for pat in 'LIVE minimize' 'LIVE restore' 'LIVE close' 'LIVE OK'; do
            grep -q "$pat" "$LIVE_LOG" 2>/dev/null || LIVE_EVIDENCE=0
        done
        if [ "$LIVE_RC" -eq 0 ] && [ "$LIVE_EVIDENCE" -eq 1 ]; then
            pass_case "live real-pump smoke survived minimize/restore/close (exit 0)"
        else
            fail_case "live real-pump smoke failed (rc=$LIVE_RC; see $LIVE_LOG)"
        fi

        # Real read error (a directory) must exit before opening/saving.
        mkdir -p "$OUT/badload"
        ( cd "$OUT" && timeout 20 wine "$CONSOLE_EXE" badload ) >"$OUT/badload.log" 2>&1
        BAD_RC=$?
        if [ "$BAD_RC" -ne 0 ] && [ "$BAD_RC" -ne 124 ] \
            && grep -q 'cannot read' "$OUT/badload.log"; then
            pass_case "real read error exits without an empty-overwrite session"
        else
            fail_case "read-error path did not fail safely (rc=$BAD_RC; see $OUT/badload.log)"
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
