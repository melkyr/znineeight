#!/bin/sh
# run_dinput_probe.sh — focused Win32/pure-Z98 probe for std_dinput.
#
# Builds a Win32-only probe (no-CRT mingw harness, -osw) that imports
# std_dinput.zig and std_ddraw.zig. Two modes:
#   --map-test  feeds a zero 256-byte key array and one with DIK_LEFT set
#               through dinputMapKeys and prints keyboard=0 / keyboard=1.
#   --smoke     opens a DDraw window, opens DirectInput on that window, and
#               prints dinput=ok (DInput8) or dinput=fallback (GetAsyncKeyState).
#
# The Wine smoke only asserts the dinput= backend line. The import gate and the
# absence of a static DINPUT8.DLL import are checked after linking.
#
# Env: ZIG       compiler (first positional arg, else $ZIG, else seed path)
#      OUT       scratch dir (default /tmp/z9gb_dinput_probe)
#      WINEPREFIX (default $OUT/wineprefix; isolated from $HOME/.wine)
#
# Exits non-zero on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${1:-${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}}"
OUT="${OUT:-/tmp/z9gb_dinput_probe}"
CROSS="$ROOT/scripts/win32_cross/cross_nocrt.sh"
CHECK="$ROOT/scripts/win32_cross/check_win9x_imports.sh"
SRC="$OUT/dinput_probe.zig"
EXE="$OUT/dinput_probe.exe"
WINEPREFIX="${WINEPREFIX:-$OUT/wineprefix}"
export WINEPREFIX
export WINEARCH=win32
export WINEDEBUG="${WINEDEBUG:--all}"

PASSES=0
FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

fail_summary() {
    echo
    echo "== dinput probe summary: $PASSES passed, $FAILS failed =="
    echo "DINPUT_PROBE FAIL"
    exit 1
}

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi
for tool in i686-w64-mingw32-gcc i686-w64-mingw32-objdump file wine xvfb-run timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required host tool not found: $tool"
        exit 1
    fi
done

rm -rf "$OUT"
mkdir -p "$OUT"

cat >"$SRC" <<'ZIG'
const std = @import("std");
const ddraw = @import("std_ddraw.zig");
const dinput = @import("std_dinput.zig");

const FRAME_W: u32 = 160;
const FRAME_H: u32 = 144;
const FB_PIXELS: usize = 160 * 144;

var g_pixels: [FB_PIXELS]u32 = undefined;

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn anyPressed(b: *const dinput.Buttons) bool {
    return b.right or b.left or b.up or b.down or b.a or b.b
        or b.select or b.start or b.quit;
}

fn fillPixels() void {
    var i: usize = 0;
    while (i < FB_PIXELS) : (i += 1) g_pixels[i] = 0x00123456;
}

fn mapTest() void {
    var keys: [256]u8 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) keys[i] = 0;
    var b: dinput.Buttons = undefined;

    dinput.dinputMapKeys(keys[0..256], &b);
    if (anyPressed(&b)) {
        std.io.write("keyboard=1\n");
    } else {
        std.io.write("keyboard=0\n");
    }

    keys[0xCB] = 0x80;
    dinput.dinputMapKeys(keys[0..256], &b);
    if (b.left and !b.right and !b.up and !b.down) {
        std.io.write("keyboard=1\n");
    } else {
        std.io.write("keyboard=0\n");
    }
}

fn smoke() void {
    fillPixels();
    const wnd = ddraw.ddrawOpen("z9gb dinput probe", FRAME_W, FRAME_H, 2) catch {
        std.io.write("dinput probe: ddrawOpen failed\n");
        std.os.exit(2);
    };
    const wh = ddraw.ddrawWindow(wnd);
    const d = dinput.dinputOpen(wh) catch {
        ddraw.ddrawClose(wnd);
        std.io.write("dinput probe: dinputOpen failed\n");
        std.os.exit(2);
    };
    const kind = dinput.dinputBackendKind(d);
    if (kind == 1) {
        std.io.write("dinput=ok\n");
    } else if (kind == 2) {
        std.io.write("dinput=fallback\n");
    } else {
        dinput.dinputClose(d);
        ddraw.ddrawClose(wnd);
        std.io.write("dinput probe: unknown backend\n");
        std.os.exit(2);
    }
    var b: dinput.Buttons = undefined;
    dinput.dinputPoll(d, &b);
    dinput.dinputClose(d);
    ddraw.ddrawClose(wnd);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    var do_map: bool = false;
    var do_smoke: bool = false;
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const tok: []const u8 = argAt(argv, i);
        if (eq(tok, "--map-test")) {
            do_map = true;
        } else if (eq(tok, "--smoke")) {
            do_smoke = true;
        } else {
            std.os.exit(1);
        }
    }
    if (do_map) {
        mapTest();
        std.os.exit(0);
    }
    if (do_smoke) {
        smoke();
        std.os.exit(0);
    }
    std.os.exit(1);
}
ZIG

cd "$ROOT" || exit 1

echo "== build probe (-osw, -I $ROOT/sf/src) =="
BUILD_LOG="$OUT/build.log"
EXTRA_LIBS="-luser32 -lgdi32" \
    DUMP_TARGET="-osw -I $ROOT/sf/src" \
    bash "$CROSS" "$ZIG" "$SRC" "$OUT/work" "$EXE" >"$BUILD_LOG" 2>&1
BUILD_RC=$?
tail -5 "$BUILD_LOG" | sed 's/^/       /'
if [ "$BUILD_RC" -eq 0 ] && [ -f "$EXE" ]; then
    pass_case "no-CRT build produced dinput_probe.exe"
else
    fail_case "no-CRT build failed (rc=$BUILD_RC; see $BUILD_LOG)"
    fail_summary
fi

FILEOUT="$(file "$EXE" 2>/dev/null)"
case "$FILEOUT" in
    *PE32*Intel\ 80386*) pass_case "file: $FILEOUT" ;;
    *) fail_case "not a PE32 i386 executable: ${FILEOUT:-<none>}" ;;
esac

IMPORTS="$OUT/imports.log"
if bash "$CHECK" "$EXE" 9x >"$IMPORTS" 2>&1; then
    pass_case "check_win9x_imports.sh 9x PASS"
else
    fail_case "check_win9x_imports.sh 9x FAILED (see $IMPORTS)"
fi
sed 's/^/       /' "$IMPORTS"

DLLS="$(i686-w64-mingw32-objdump -p "$EXE" 2>/dev/null \
    | sed -n 's/.*DLL Name: //p' | tr -d '\r' | tr '[:lower:]' '[:upper:]' | sort -u)"
echo "$DLLS" | sed 's/^/       DLL /'
if echo "$DLLS" | grep -qx 'DINPUT8.DLL'; then
    fail_case "DINPUT8.DLL imported (must be loaded dynamically)"
else
    pass_case "no DINPUT8.DLL import (loaded dynamically)"
fi

# ---- deterministic keymap unit test ----
wineserver -k >/dev/null 2>&1 || true
if timeout 90 wine "$EXE" --map-test >"$OUT/map.log" 2>&1; then
    pass_case "keymap test exited 0"
else
    fail_case "keymap test failed (see $OUT/map.log)"
fi
sed 's/^/       /' "$OUT/map.log" 2>/dev/null || true
ZERO="$(grep -c '^keyboard=0$' "$OUT/map.log" 2>/dev/null || true)"
ONE="$(grep -c '^keyboard=1$' "$OUT/map.log" 2>/dev/null || true)"
if [ "$ZERO" = "1" ] && [ "$ONE" = "1" ]; then
    pass_case "keymap: zero array -> keyboard=0, DIK_LEFT -> keyboard=1"
else
    fail_case "keymap output mismatch (keyboard=0 count=$ZERO, keyboard=1 count=$ONE)"
fi
wineserver -k >/dev/null 2>&1 || true

# ---- windowed backend smoke under Xvfb + Wine ----
if timeout 180 xvfb-run -a -s "-screen 0 1024x768x24" \
    wine "$EXE" --smoke >"$OUT/smoke.log" 2>&1; then
    pass_case "windowed --smoke exited 0"
else
    fail_case "windowed --smoke failed (see $OUT/smoke.log)"
fi
sed 's/^/       /' "$OUT/smoke.log" 2>/dev/null || true
if grep -Eq '^dinput=(ok|fallback)$' "$OUT/smoke.log" 2>/dev/null; then
    pass_case "smoke printed a dinput backend line"
else
    fail_case "smoke dinput=ok/fallback line missing"
fi
wineserver -k >/dev/null 2>&1 || true

echo
echo "== dinput probe summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "DINPUT_PROBE FAIL"
    exit 1
fi
echo "DINPUT_PROBE PASS"
exit 0
