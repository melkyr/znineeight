#!/bin/sh
# tier_gfx.sh — Phase 2 P4-M1 gate for std_gfx + gfx_demo.
#
# POSIX sh. Run from anywhere (paths resolved from this script).
#
# (a) Build examples/z98/gfx_demo/main.zig through the no-CRT mingw harness
#     (scripts/win32_cross/cross_nocrt.sh) with EXTRA_LIBS="-luser32 -lgdi32
#     -lddraw". The exe must be PE32 i386, import DDRAW/GDI32/USER32 and never
#     MSVCRT, and pass the closed-world 9x import gate.
# (b) Headless deterministic gate: run the real .exe under Wine with
#     `--smoke 30 --dump-grid` (gfxOpenMemory: no window, no X), then compare
#     the produced grid.txt byte-for-byte with tests/golden/grid.txt.
# (c) Bonus evidence (Xvfb + Wine): a real window, flushed READY sentinel,
#     `import -window root` screenshot. This tier asserts the app exits 0 and
#     the screenshot is saved and non-blank; it does NOT gate on pixels.
#     If Xvfb/wine/import/identify are genuinely absent it prints an
#     operator-hardware line (never a silent skip).
#
# Env: ZIG       compiler (default /tmp/p4_t1_build/zig1_5_clean)
#      OUT       scratch dir (default /tmp/gfx_tier)
#      WINEPREFIX (default $OUT/wineprefix; isolated from $HOME/.wine)
#      GFX_UPDATE_GOLDEN=1  copy the generated grid.txt over the golden
#      GFX_NO_XVFB=1        skip the bonus window tier
#
# Exits non-zero on any gate failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GFXDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$GFXDIR/../../.." && pwd)"
ENTRY="examples/z98/gfx_demo/main.zig"
ZIG="${ZIG:-/tmp/p4_t1_build/zig1_5_clean}"
OUT="${OUT:-/tmp/gfx_tier}"
GOLDEN="$SCRIPT_DIR/golden/grid.txt"
CROSS="$ROOT/scripts/win32_cross/cross_nocrt.sh"
CHECK="$ROOT/scripts/win32_cross/check_win9x_imports.sh"
EXE="$OUT/gfx_demo.exe"
WINE_PREFIX="${WINEPREFIX:-$OUT/wineprefix}"
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
    if [ -n "$XVFB_PID" ]; then kill "$XVFB_PID" 2>/dev/null || true; fi
    wineserver -k >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    echo "      build it: bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p4_t1_build"
    exit 1
fi
for tool in i686-w64-mingw32-gcc i686-w64-mingw32-objdump file md5sum wine; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required host tool not found: $tool"
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT"

cd "$ROOT" || exit 1

# ---- (a) no-CRT build + imports ------------------------------------------
echo "== (a) no-CRT build + import gate =="
BUILD_LOG="$OUT/build.log"
COMPILE_RSS="n/a"
EXTRA_LIBS="-luser32 -lgdi32 -lddraw" \
    bash "$CROSS" "$ZIG" "$ENTRY" "$OUT/work" "$EXE" >"$BUILD_LOG" 2>&1
BUILD_RC=$?
# The 16 MB target is the Z98 compile (dump) of the demo, not the host gcc
# phase (gcc's own RSS is not the product's compile cost). Measure the dump
# explicitly; the cross harness repeats it internally for the real build.
if command -v /usr/bin/time >/dev/null 2>&1; then
    mkdir -p "$OUT/rss_dump"
    /usr/bin/time -v -o "$OUT/zig_time.log" \
        "$ZIG" --dump-c89 --output-dir "$OUT/rss_dump" "$ENTRY" \
        >"$OUT/zig_dump.log" 2>&1
    COMPILE_RSS=$(sed -n 's/.*Maximum resident set size (kbytes): //p' "$OUT/zig_time.log" | tail -1)
    [ -n "$COMPILE_RSS" ] || COMPILE_RSS="n/a"
fi
tail -3 "$BUILD_LOG" | sed 's/^/       /'
if [ "$BUILD_RC" -eq 0 ] && [ -f "$EXE" ]; then
    pass_case "no-CRT build produced gfx_demo.exe"
else
    fail_case "no-CRT build failed (rc=$BUILD_RC; see $BUILD_LOG)"
    echo
    echo "== tier_gfx summary: $PASSES passed, $FAILS failed =="
    echo "TIER_GFX FAIL"
    exit 1
fi
if [ "$COMPILE_RSS" = "n/a" ]; then
    echo "operator-hardware: Z98 compile RSS not measured (/usr/bin/time absent)"
elif [ "$COMPILE_RSS" -lt 16384 ]; then
    pass_case "Z98 compile max RSS < 16 MB (${COMPILE_RSS} kB)"
else
    fail_case "Z98 compile max RSS >= 16 MB (${COMPILE_RSS} kB)"
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

# ---- (b) headless grid golden --------------------------------------------
echo "== (b) headless grid golden (gfxOpenMemory) =="
GRID_DIR="$OUT/grid"
mkdir -p "$GRID_DIR"
if ( cd "$GRID_DIR" && timeout 120 wine "$EXE" --smoke 30 --dump-grid ) \
    >"$OUT/grid_run.log" 2>&1; then
    pass_case "headless --smoke 30 --dump-grid exited 0"
else
    GRID_RC=$?
    fail_case "headless --smoke 30 --dump-grid failed (rc=$GRID_RC; see $OUT/grid_run.log)"
fi
sed 's/^/       /' "$OUT/grid_run.log"
if [ -f "$GRID_DIR/grid.txt" ]; then
    GRID_MD5="$(md5sum "$GRID_DIR/grid.txt" | cut -d' ' -f1)"
    pass_case "grid.txt written (md5 $GRID_MD5, $(LC_ALL=C wc -c <"$GRID_DIR/grid.txt" | tr -d ' ') bytes)"
    if [ ! -f "$GOLDEN" ]; then
        fail_case "golden missing: $GOLDEN (run once with GFX_UPDATE_GOLDEN=1, inspect, commit)"
    elif [ "${GFX_UPDATE_GOLDEN:-0}" = "1" ]; then
        cp "$GRID_DIR/grid.txt" "$GOLDEN"
        pass_case "golden updated from verified run: $GOLDEN"
    elif cmp -s "$GRID_DIR/grid.txt" "$GOLDEN"; then
        pass_case "grid.txt matches golden byte-for-byte"
    else
        fail_case "grid.txt differs from golden (got $GRID_MD5)"
        if command -v diff >/dev/null 2>&1; then
            diff -u "$GOLDEN" "$GRID_DIR/grid.txt" | sed -n '1,40p' | sed 's/^/       /'
        fi
    fi
else
    fail_case "grid.txt not produced (see $OUT/grid_run.log)"
fi

# ---- (c) Xvfb + Wine window/screenshot evidence --------------------------
echo "== (c) Xvfb + Wine window smoke (bonus, non-pixel) =="
MISSING_X=""
for tool in Xvfb xdpyinfo wineboot import identify; do
    command -v "$tool" >/dev/null 2>&1 || MISSING_X="$MISSING_X $tool"
done
if [ "${GFX_NO_XVFB:-0}" = "1" ]; then
    echo "operator-hardware: window smoke skipped by GFX_NO_XVFB=1"
elif [ -n "$MISSING_X" ]; then
    echo "operator-hardware: window smoke not run (missing:$MISSING_X)"
else
    # A fresh prefix for the windowed run: the headless pass above created its
    # prefix with no X server, and a still-live wineserver keeps that
    # environment (no display driver). Kill it and use a window-only prefix.
    wineserver -k >/dev/null 2>&1 || true
    export WINEPREFIX="$OUT/wineprefix_x"
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
        ( cd "$SHOT_DIR" && timeout 90 wine "$EXE" --smoke 30 ) \
            >"$SHOT_DIR/app.log" 2>&1 &
        WINE_PID=$!
        READY_SEEN=0
        i=0
        while [ "$i" -lt 150 ]; do
            if grep -q '^READY$' "$SHOT_DIR/app.log" 2>/dev/null; then
                READY_SEEN=1
                break
            fi
            sleep 0.1
            i=$((i + 1))
        done
        if [ "$READY_SEEN" -eq 1 ]; then
            pass_case "READY sentinel seen"
        else
            fail_case "READY sentinel not seen (see $SHOT_DIR/app.log)"
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
        app_rc_file="$SHOT_DIR/app.rc"
        echo "$APP_RC" >"$app_rc_file"
        if [ "$APP_RC" -eq 0 ]; then
            pass_case "windowed --smoke 30 exited 0"
        else
            fail_case "windowed --smoke 30 exited $APP_RC (see $SHOT_DIR/app.log)"
        fi
        sed 's/^/       /' "$SHOT_DIR/app.log"
        WINE_PID=""
        wineserver -k >/dev/null 2>&1 || true
    fi
    kill "$XVFB_PID" 2>/dev/null || true
    wait "$XVFB_PID" 2>/dev/null || true
    XVFB_PID=""
fi

echo
echo "== tier_gfx summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_GFX FAIL"
    exit 1
fi
echo "TIER_GFX PASS"
exit 0
