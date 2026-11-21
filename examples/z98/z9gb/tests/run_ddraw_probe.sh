#!/bin/sh
# run_ddraw_probe.sh — focused Win32/pure-Z98 probe for std_ddraw.
#
# Builds a Win32-only probe (no-CRT mingw harness, -osw) that imports
# std_ddraw.zig, opens a 160x144 surface at the requested scale, presents a
# deterministic solid-colour framebuffer, and dumps the 92,160-byte
# little-endian framebuffer through --fb-out. The windowed run is executed
# under Wine with Xvfb; a headless reference run writes the same source bytes
# with no window. The tier compares both checksums and the first pixel.
#
# Env: ZIG       compiler (first positional arg, else $ZIG, else seed path)
#      OUT       scratch dir (default /tmp/z9gb_ddraw_probe)
#      WINEPREFIX (default $OUT/wineprefix; isolated from $HOME/.wine)
#
# Exits non-zero on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${1:-${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}}"
OUT="${OUT:-/tmp/z9gb_ddraw_probe}"
CROSS="$ROOT/scripts/win32_cross/cross_nocrt.sh"
CHECK="$ROOT/scripts/win32_cross/check_win9x_imports.sh"
SRC="$OUT/ddraw_probe.zig"
EXE="$OUT/ddraw_probe.exe"
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
    echo "== ddraw probe summary: $PASSES passed, $FAILS failed =="
    echo "DDRAW_PROBE FAIL"
    exit 1
}

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi
for tool in i686-w64-mingw32-gcc i686-w64-mingw32-objdump file md5sum od wine timeout; do
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

const FRAME_W: u32 = 160;
const FRAME_H: u32 = 144;
const FB_PIXELS: usize = 160 * 144;
const FB_BYTES: usize = FB_PIXELS * 4;
const SOLID: u32 = 0x00123456;
const SOLID_COLORREF: u32 = 0x00563412;

pub extern "stdcall" fn GetDC(hwnd: *void) *void;
pub extern "stdcall" fn ReleaseDC(hwnd: *void, hdc: *void) i32;
pub extern "stdcall" fn GetPixel(hdc: *void, x: i32, y: i32) u32;

var g_pixels: [FB_PIXELS]u32 = undefined;
var g_bytes: [FB_BYTES]u8 = undefined;

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

fn parseU32(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var v: u64 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c: u8 = s[i];
        if (c < '0' or c > '9') return null;
        v = v * 10 + @intCast(u64, c - '0');
        if (v > 1000000) return null;
    }
    return @intCast(u32, v);
}

fn putLe32(buf: []u8, off: usize, v: u32) void {
    buf[off] = @intCast(u8, v & 0xff);
    buf[off + 1] = @intCast(u8, (v >> 8) & 0xff);
    buf[off + 2] = @intCast(u8, (v >> 16) & 0xff);
    buf[off + 3] = @intCast(u8, (v >> 24) & 0xff);
}

fn fillPixels() void {
    var i: usize = 0;
    while (i < FB_PIXELS) : (i += 1) g_pixels[i] = SOLID;
}

fn encodeBytes() void {
    var i: usize = 0;
    while (i < FB_PIXELS) : (i += 1) putLe32(g_bytes[0..], i * 4, g_pixels[i]);
}

fn writeFb(path: []const u8) bool {
    encodeBytes();
    const fdopt = std.io.fileOpen(path, true);
    if (fdopt) |fd| {
        std.io.fileWrite(fd, g_bytes[0..FB_BYTES]);
        std.io.fileClose(fd);
        return true;
    }
    return false;
}

fn writeHex(v: u32) void {
    std.io.write("0x");
    var shifts: [8]u32 = [8]u32{ 28, 24, 20, 16, 12, 8, 4, 0 };
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        const nib: u32 = (v >> shifts[i]) & 15;
        if (nib < 10) {
            std.io.writeByte(@intCast(u8, 48 + nib));
        } else {
            std.io.writeByte(@intCast(u8, 87 + nib));
        }
    }
}

// Read the presented window client through GDI. GetPixel returns COLORREF
// (0x00BBGGRR), so SOLID 0x00RRGGBB = 0x00123456 reads back as 0x00563412.
fn readbackCheck(hwnd: *void, scale: u32) bool {
    const hdc = GetDC(hwnd);
    if (@ptrToInt(hdc) == 0) {
        std.io.write("readback scale=");
        std.io.printInt(@intCast(i32, scale));
        std.io.write(" FAIL (GetDC null)\n");
        return false;
    }
    const w: i32 = @intCast(i32, FRAME_W * scale);
    const h: i32 = @intCast(i32, FRAME_H * scale);
    var xs: [5]i32 = [5]i32{ 0, w - 1, 0, w - 1, w / 2 };
    var ys: [5]i32 = [5]i32{ 0, 0, h - 1, h - 1, h / 2 };
    var ok: bool = true;
    var first: u32 = 0;
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const got = GetPixel(hdc, xs[i], ys[i]);
        if (i == 0) first = got;
        if (got != SOLID_COLORREF) {
            ok = false;
            std.io.write("readback scale=");
            std.io.printInt(@intCast(i32, scale));
            std.io.write(" p(");
            std.io.printInt(xs[i]);
            std.io.write(",");
            std.io.printInt(ys[i]);
            std.io.write(") want ");
            writeHex(SOLID_COLORREF);
            std.io.write(" got ");
            writeHex(got);
            std.io.write(" FAIL\n");
        }
    }
    _ = ReleaseDC(hwnd, hdc);
    if (ok) {
        std.io.write("readback scale=");
        std.io.printInt(@intCast(i32, scale));
        std.io.write(" PASS first=");
        writeHex(first);
        std.io.write("\n");
    }
    return ok;

}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    var scale: u32 = 2;
    var frames: u32 = 1;
    var fb_out: []const u8 = "";
    var headless: bool = false;
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const tok: []const u8 = argAt(argv, i);
        if (eq(tok, "--scale")) {
            i += 1;
            if (i >= n) std.os.exit(1);
            if (parseU32(argAt(argv, i))) |v| {
                scale = v;
            } else {
                std.os.exit(1);
            }
        } else if (eq(tok, "--frames")) {
            i += 1;
            if (i >= n) std.os.exit(1);
            if (parseU32(argAt(argv, i))) |v| {
                frames = v;
            } else {
                std.os.exit(1);
            }
        } else if (eq(tok, "--fb-out")) {
            i += 1;
            if (i >= n) std.os.exit(1);
            fb_out = argAt(argv, i);
        } else if (eq(tok, "--headless")) {
            headless = true;
        } else {
            std.os.exit(1);
        }
    }

    fillPixels();
    if (!headless) {
        const wnd = ddraw.ddrawOpen("z9gb ddraw probe", FRAME_W, FRAME_H, scale) catch {
            std.io.write("ddraw probe: ddrawOpen failed\n");
            std.os.exit(2);
        };
        var f: u32 = 0;
        while (f < frames) : (f += 1) {
            if (!ddraw.ddrawPresent(wnd, g_pixels[0..FB_PIXELS])) {
                ddraw.ddrawClose(wnd);
                std.io.write("ddraw probe: ddrawPresent failed\n");
                std.os.exit(2);
            }
            var ev: ddraw.DdrawEvent = undefined;
            _ = ddraw.ddrawPoll(wnd, &ev);
        }
        const wh = ddraw.ddrawWindow(wnd);
        if (@ptrToInt(wh) == 0) {
            ddraw.ddrawClose(wnd);
            std.io.write("ddraw probe: ddrawWindow null\n");
            std.os.exit(2);
        }
        if (!readbackCheck(wh, scale)) {
            ddraw.ddrawClose(wnd);
            std.io.write("ddraw probe: readback failed at requested scale\n");
            std.os.exit(2);
        }
        if (scale != 4) {
            if (!ddraw.ddrawSetScale(wnd, 4)) {
                ddraw.ddrawClose(wnd);
                std.io.write("ddraw probe: ddrawSetScale(4) failed\n");
                std.os.exit(2);
            }
            if (!ddraw.ddrawPresent(wnd, g_pixels[0..FB_PIXELS])) {
                ddraw.ddrawClose(wnd);
                std.io.write("ddraw probe: ddrawPresent(scale 4) failed\n");
                std.os.exit(2);
            }
            if (!readbackCheck(wh, 4)) {
                ddraw.ddrawClose(wnd);
                std.io.write("ddraw probe: readback failed at scale 4\n");
                std.os.exit(2);
            }
        }
        ddraw.ddrawClose(wnd);
    }

    if (fb_out.len != 0) {
        if (!writeFb(fb_out)) {
            std.io.write("ddraw probe: cannot write framebuffer\n");
            std.os.exit(2);
        }
    }
    std.io.write("ddraw probe: PASS\n");
    std.os.exit(0);
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
    pass_case "no-CRT build produced ddraw_probe.exe"
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
if echo "$DLLS" | grep -qx 'DDRAW.DLL'; then
    fail_case "DDRAW.DLL imported (must be loaded dynamically)"
else
    pass_case "no DDRAW.DLL import (loaded dynamically)"
fi

# ---- headless reference ----
wineserver -k >/dev/null 2>&1 || true
HEAD_FB="$OUT/headless.fb"
if timeout 90 wine "$EXE" --headless --fb-out "$HEAD_FB" >"$OUT/headless.log" 2>&1 \
    && [ -f "$HEAD_FB" ]; then
    pass_case "headless reference exited 0"
else
    fail_case "headless reference failed (see $OUT/headless.log)"
fi
sed 's/^/       /' "$OUT/headless.log" 2>/dev/null || true

# ---- windowed present under Xvfb + Wine ----
wineserver -k >/dev/null 2>&1 || true
WIN_FB="$OUT/windowed.fb"
if timeout 180 xvfb-run -a -s "-screen 0 1024x768x24" \
    wine "$EXE" --scale 2 --frames 1 --fb-out "$WIN_FB" >"$OUT/windowed.log" 2>&1 \
    && [ -f "$WIN_FB" ]; then
    pass_case "windowed --scale 2 --frames 1 exited 0"
else
    fail_case "windowed --scale 2 --frames 1 failed (see $OUT/windowed.log)"
fi
sed 's/^/       /' "$OUT/windowed.log" 2>/dev/null || true
wineserver -k >/dev/null 2>&1 || true

# Primary evidence: the presented window client must read back the solid
# colour through GDI GetPixel at scale 2 and at the ddrawSetScale(4) path.
RB2="$(grep -c '^readback scale=2 PASS' "$OUT/windowed.log" 2>/dev/null || true)"
if [ "$RB2" = "1" ]; then
    pass_case "presented surface readback at scale 2 (GDI GetPixel)"
else
    fail_case "presented surface readback at scale 2 missing/failed"
fi
RB4="$(grep -c '^readback scale=4 PASS' "$OUT/windowed.log" 2>/dev/null || true)"
if [ "$RB4" = "1" ]; then
    pass_case "presented surface readback at scale 4 after ddrawSetScale"
else
    fail_case "presented surface readback at scale 4 missing/failed"
fi

if [ -f "$HEAD_FB" ] && [ -f "$WIN_FB" ]; then
    HEAD_MD5="$(md5sum "$HEAD_FB" | cut -d' ' -f1)"
    WIN_MD5="$(md5sum "$WIN_FB" | cut -d' ' -f1)"
    echo "       headless md5 $HEAD_MD5"
    echo "       windowed md5 $WIN_MD5"
    if [ "$HEAD_MD5" = "$WIN_MD5" ]; then
        pass_case "framebuffer checksum matches headless source"
    else
        fail_case "framebuffer checksum differs from headless source"
    fi
    FIRST="$(od -An -tx4 -N4 "$WIN_FB" | tr -d ' \n' | tr '[:lower:]' '[:upper:]')"
    if [ "$FIRST" = "00123456" ]; then
        pass_case "first pixel $FIRST (solid 0x00123456)"
    else
        fail_case "first pixel want 00123456, got ${FIRST:-<none>}"
    fi
    SIZE="$(stat -c %s "$WIN_FB" 2>/dev/null || echo 0)"
    if [ "$SIZE" = "92160" ]; then
        pass_case "framebuffer is 92160 bytes"
    else
        fail_case "framebuffer is 92160 bytes (got $SIZE)"
    fi
else
    fail_case "framebuffer files missing"
fi

echo
echo "== ddraw probe summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "DDRAW_PROBE FAIL"
    exit 1
fi
echo "DDRAW_PROBE PASS"
exit 0
