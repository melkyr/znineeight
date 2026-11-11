#!/bin/sh
# run_dsound_probe.sh — focused Win32/pure-Z98 probe for std_dsound.
#
# Builds a Win32-only probe (no-CRT mingw harness, -osw) that imports
# std_ddraw.zig and std_dsound.zig, opens a DDraw window, opens DirectSound at
# 44,100 Hz stereo on that window, fills the free ring space (derived from
# dsoundQueued after the 256-frame DMA lead), and prints backend=<1|2>
# queued=<n> offered=<n> wrote=<n>. The primary run must choose backend 1
# (DirectSound) or 2 (waveOut). A second run disables dsound.dll through Wine so
# the waveOut fallback must be selected (backend=2).
#
# The isolated HOME gives Wine an ALSA null default PCM, so DirectSound and
# waveOut have a device even when the host has no audio card (the Task 0 setup).
# The import gate checks the no-CRT exe and the absence of a static DSOUND.DLL.
#
# Env: ZIG       compiler (first positional arg, else $ZIG, else seed path)
#      OUT       scratch dir (default /tmp/z9gb_dsound_probe)
#      WINEPREFIX (default $OUT/wineprefix; isolated from $HOME/.wine)
#
# Exits non-zero on any failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${1:-${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}}"
OUT="${OUT:-/tmp/z9gb_dsound_probe}"
CROSS="$ROOT/scripts/win32_cross/cross_nocrt.sh"
CHECK="$ROOT/scripts/win32_cross/check_win9x_imports.sh"
SRC="$OUT/dsound_probe.zig"
EXE="$OUT/dsound_probe.exe"
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
    echo "== dsound probe summary: $PASSES passed, $FAILS failed =="
    echo "DSOUND_PROBE FAIL"
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
const dsound = @import("std_dsound.zig");

const FRAME_W: u32 = 160;
const FRAME_H: u32 = 144;
const FB_PIXELS: usize = 160 * 144;
const AUDIO_FRAMES: usize = 2048;
const AUDIO_SAMPLES: usize = AUDIO_FRAMES * 2;

var g_pixels: [FB_PIXELS]u32 = undefined;
var g_silence: [AUDIO_SAMPLES]i16 = undefined;

fn fillPixels() void {
    var i: usize = 0;
    while (i < FB_PIXELS) : (i += 1) g_pixels[i] = 0x00123456;
}

fn fillSilence() void {
    var i: usize = 0;
    while (i < AUDIO_SAMPLES) : (i += 1) g_silence[i] = 0;
}

pub extern "stdcall" fn Sleep(ms: u32) void;

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

fn printBackend(kind: u8, queued: usize) void {
    std.io.write("backend=");
    std.io.printInt(@intCast(i32, kind));
    std.io.write(" queued=");
    std.io.printInt(@intCast(i32, queued));
    std.io.write("\n");
}

fn underrun(d: *dsound.Dsound) void {
    // Stall longer than the 256-frame lead but well under one ring lap so the
    // play cursor passes the queued write cursor and the missed span is visible
    // from the two positions. The underrun path resets the queue, so the full
    // ring must be accepted.
    Sleep(20);
    const w = dsound.dsoundWrite(d, g_silence[0..AUDIO_SAMPLES]);
    const q = dsound.dsoundQueued(d);
    std.io.write("underrun wrote=");
    std.io.printInt(@intCast(i32, w));
    std.io.write(" queued=");
    std.io.printInt(@intCast(i32, q));
    std.io.write("\n");
    if (w == AUDIO_SAMPLES) {
        std.io.write("UNDERRUN_PASS\n");
        std.os.exit(0);
    }
    std.io.write("UNDERRUN_FAIL\n");
    std.os.exit(3);
}

fn stress(d: *dsound.Dsound) void {
    var step: u32 = 0;
    var short: i32 = 0;
    var zeros: i32 = 0;
    var maxq: i32 = 0;
    while (step < 8) : (step += 1) {
        if (step == 4 or step == 6) Sleep(150);
        var offer: i32 = @intCast(i32, AUDIO_SAMPLES);
        var w: usize = 0;
        if (step == 2 or step == 3) {
            offer = 1500;
            w = dsound.dsoundWrite(d, g_silence[0..1500]);
        } else {
            w = dsound.dsoundWrite(d, g_silence[0..AUDIO_SAMPLES]);
        }
        const q = dsound.dsoundQueued(d);
        if (@intCast(i32, w) != offer) short += 1;
        if (w == 0) zeros += 1;
        if (@intCast(i32, q) > maxq) maxq = @intCast(i32, q);
        std.io.write("stress step=");
        std.io.printInt(@intCast(i32, step));
        std.io.write(" offered=");
        std.io.printInt(offer);
        std.io.write(" wrote=");
        std.io.printInt(@intCast(i32, w));
        std.io.write(" queued=");
        std.io.printInt(@intCast(i32, q));
        std.io.write("\n");
    }
    std.io.write("STRESS short=");
    std.io.printInt(short);
    std.io.write(" zeros=");
    std.io.printInt(zeros);
    std.io.write(" maxqueued=");
    std.io.printInt(maxq);
    std.io.write("\n");
    if (short == 0 and zeros == 0) {
        std.io.write("STRESS_PASS\n");
        std.os.exit(0);
    }
    std.io.write("STRESS_FAIL\n");
    std.os.exit(3);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    var mode: u8 = 0;
    var ai: usize = 1;
    while (ai < n) : (ai += 1) {
        const tok: []const u8 = argAt(argv, ai);
        if (eq(tok, "--underrun")) {
            mode = 1;
        } else if (eq(tok, "--stress")) {
            mode = 2;
        } else {
            std.os.exit(1);
        }
    }
    fillPixels();
    fillSilence();
    const wnd = ddraw.ddrawOpen("z9gb dsound probe", FRAME_W, FRAME_H, 2) catch {
        std.io.write("dsound probe: ddrawOpen failed\n");
        std.os.exit(2);
    };
    const wh = ddraw.ddrawWindow(wnd);
    const d = dsound.dsoundOpen(wh, 44100, 2) catch {
        ddraw.ddrawClose(wnd);
        std.io.write("dsound probe: dsoundOpen failed\n");
        std.os.exit(2);
    };
    const kind = dsound.dsoundBackendKind(d);
    if (mode == 1) {
        printBackend(kind, dsound.dsoundQueued(d));
        underrun(d);
    } else if (mode == 2) {
        printBackend(kind, dsound.dsoundQueued(d));
        stress(d);
    }
    const q_before = dsound.dsoundQueued(d);
    var offered: usize = AUDIO_SAMPLES;
    if (q_before < AUDIO_SAMPLES) offered = AUDIO_SAMPLES - q_before;
    if (offered > AUDIO_SAMPLES) offered = AUDIO_SAMPLES;
    const wrote = dsound.dsoundWrite(d, g_silence[0..offered]);
    const queued = dsound.dsoundQueued(d);
    printBackend(kind, queued);
    std.io.write("offered=");
    std.io.printInt(@intCast(i32, offered));
    std.io.write(" wrote=");
    std.io.printInt(@intCast(i32, wrote));
    std.io.write("\n");
    dsound.dsoundClose(d);
    ddraw.ddrawClose(wnd);
    std.os.exit(0);
}
ZIG

cd "$ROOT" || exit 1

echo "== build probe (-osw, -I $ROOT/sf/src) =="
BUILD_LOG="$OUT/build.log"
EXTRA_LIBS="-luser32 -lgdi32 -lwinmm" \
    DUMP_TARGET="-osw -I $ROOT/sf/src" \
    bash "$CROSS" "$ZIG" "$SRC" "$OUT/work" "$EXE" >"$BUILD_LOG" 2>&1
BUILD_RC=$?
tail -5 "$BUILD_LOG" | sed 's/^/       /'
if [ "$BUILD_RC" -eq 0 ] && [ -f "$EXE" ]; then
    pass_case "no-CRT build produced dsound_probe.exe"
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
if echo "$DLLS" | grep -qx 'DSOUND.DLL'; then
    fail_case "DSOUND.DLL imported (must be loaded dynamically)"
else
    pass_case "no DSOUND.DLL import (loaded dynamically)"
fi

# Hermetic Wine audio: an isolated HOME with a null ALSA default + Wine alsa
# driver, matching the Task 0 DirectSound evidence. No host audio card needed.
PROBE_HOME="$OUT/home"
mkdir -p "$PROBE_HOME"
cat >"$PROBE_HOME/.asoundrc" <<'ALSA'
pcm.!default { type null }
ctl.!default { type null }
ALSA
HOME="$PROBE_HOME"
export HOME
wineserver -k >/dev/null 2>&1 || true
wineboot -u >/dev/null 2>&1 || true
wine reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d alsa /f >/dev/null 2>&1 || true

# ---- primary run under Xvfb + Wine ----
# The first DDraw window of a freshly created Wine prefix can fail to
# initialise; retry the real run rather than treating that one-time host
# flake as a product failure.
PRIMARY_OK=0
ATTEMPT=1
while [ "$ATTEMPT" -le 3 ]; do
    if timeout 180 xvfb-run -a -s "-screen 0 1024x768x24" \
        wine "$EXE" >"$OUT/primary.log" 2>&1 \
        && grep -Eq '^backend=(1|2) queued=[0-9]+$' "$OUT/primary.log"; then
        PRIMARY_OK=1
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    wineserver -k >/dev/null 2>&1 || true
done
if [ "$PRIMARY_OK" = "1" ]; then
    pass_case "windowed probe exited 0 on attempt $ATTEMPT"
else
    fail_case "windowed probe failed after $ATTEMPT attempts (see $OUT/primary.log)"
fi
sed 's/^/       /' "$OUT/primary.log" 2>/dev/null || true
if grep -Eq '^backend=(1|2) queued=[0-9]+$' "$OUT/primary.log" 2>/dev/null; then
    pass_case "probe printed backend=<1|2> queued=<n>"
else
    fail_case "backend/queued line missing or malformed"
fi
if awk '/^offered=[0-9]+ wrote=[0-9]+$/ { split($1, a, "="); split($2, b, "="); if (a[2] == b[2]) ok = 1 } END { exit(ok ? 0 : 1) }' "$OUT/primary.log" 2>/dev/null; then
    pass_case "dsoundWrite accepted its derived free space (no short)"
else
    fail_case "dsoundWrite did not accept its derived free space (see offered/wrote line)"
fi
wineserver -k >/dev/null 2>&1 || true

# ---- underrun regression: stall past the queued lead, under one ring lap ----
UNDERRUN_OK=0
ATTEMPT=1
while [ "$ATTEMPT" -le 3 ]; do
    if timeout 180 xvfb-run -a -s "-screen 0 1024x768x24" \
        wine "$EXE" --underrun >"$OUT/underrun.log" 2>&1 \
        && grep -q '^UNDERRUN_PASS$' "$OUT/underrun.log"; then
        UNDERRUN_OK=1
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    wineserver -k >/dev/null 2>&1 || true
done
if [ "$UNDERRUN_OK" = "1" ]; then
    pass_case "underrun probe (20 ms stall past the lead) exited 0 on attempt $ATTEMPT"
else
    fail_case "underrun probe failed after $ATTEMPT attempts (see $OUT/underrun.log)"
fi
sed 's/^/       /' "$OUT/underrun.log" 2>/dev/null || true
if grep -Eq '^underrun wrote=4096 queued=[0-9]+$' "$OUT/underrun.log" 2>/dev/null; then
    pass_case "underrun accepted a full ring after the missed-span gap"
else
    fail_case "underrun consumed fewer than a full ring after the missed-span gap"
fi
wineserver -k >/dev/null 2>&1 || true

# ---- forced waveOut fallback: disable dsound.dll in this prefix ----
FALLBACK_OK=0
ATTEMPT=1
while [ "$ATTEMPT" -le 3 ]; do
    if timeout 180 xvfb-run -a -s "-screen 0 1024x768x24" \
        env WINEDLLOVERRIDES="dsound=d" wine "$EXE" >"$OUT/fallback.log" 2>&1 \
        && grep -Eq '^backend=2 queued=[0-9]+$' "$OUT/fallback.log"; then
        FALLBACK_OK=1
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    wineserver -k >/dev/null 2>&1 || true
done
if [ "$FALLBACK_OK" = "1" ]; then
    pass_case "forced-fallback probe exited 0 on attempt $ATTEMPT"
else
    fail_case "forced-fallback probe failed after $ATTEMPT attempts (see $OUT/fallback.log)"
fi
sed 's/^/       /' "$OUT/fallback.log" 2>/dev/null || true
if grep -Eq '^backend=2 queued=[0-9]+$' "$OUT/fallback.log" 2>/dev/null; then
    pass_case "waveOut fallback selected (backend=2) with dsound.dll disabled"
else
    fail_case "waveOut fallback backend=2 line missing"
fi
wineserver -k >/dev/null 2>&1 || true

# ---- fallback stress: both device buffers busy, pending absorbs the tail ----
STRESS_OK=0
ATTEMPT=1
while [ "$ATTEMPT" -le 3 ]; do
    if timeout 180 xvfb-run -a -s "-screen 0 1024x768x24" \
        env WINEDLLOVERRIDES="dsound=d" wine "$EXE" --stress >"$OUT/stress.log" 2>&1 \
        && grep -q '^STRESS_PASS$' "$OUT/stress.log"; then
        STRESS_OK=1
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    wineserver -k >/dev/null 2>&1 || true
done
if [ "$STRESS_OK" = "1" ]; then
    pass_case "waveOut stress (both buffers busy) exited 0 on attempt $ATTEMPT"
else
    fail_case "waveOut stress failed after $ATTEMPT attempts (see $OUT/stress.log)"
fi
sed 's/^/       /' "$OUT/stress.log" 2>/dev/null || true
if grep -q 'STRESS short=0 zeros=0' "$OUT/stress.log" 2>/dev/null; then
    STRESS_LINES="$(grep -c 'stress step=' "$OUT/stress.log" 2>/dev/null || true)"
    if [ "$STRESS_LINES" = "8" ]; then
        pass_case "every waveOut stress write accepted its full offer"
    else
        fail_case "waveOut stress line count $STRESS_LINES (want 8)"
    fi
else
    fail_case "waveOut stress short-consumed/dropped samples"
fi
if grep -q 'stress step=4 .*queued=8192' "$OUT/stress.log" 2>/dev/null; then
    pass_case "partial pending buffer was silence-padded and submitted"
else
    fail_case "partial pending buffer was not padded/submitted at step 4"
fi
wineserver -k >/dev/null 2>&1 || true

echo
echo "== dsound probe summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "DSOUND_PROBE FAIL"
    exit 1
fi
echo "DSOUND_PROBE PASS"
exit 0
