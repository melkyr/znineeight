#!/bin/sh
# run_px_probe.sh — M9 Task 2 Wine evidence for the Windows px binding.
#
# EVIDENCE ONLY: this script is not part of the native gate. It builds a tiny
# -osw probe that imports std_gfx_px, opens the standalone fixed 640x480 px
# window, fills a deterministic 565 ramp under lock, presents it, and writes a
# short log. If Wine/Xvfb (or the seed compiler) is absent it prints a LOUD
# skip and exits 0.
#
# Env: ZIG compiler (default /tmp/seed151_build/zig1_5_clean)
#      OUT scratch dir (default /tmp/m9_px_probe)
#      WINEPREFIX defaults under $HOME (never /tmp)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
ZIG="${ZIG:-/tmp/seed151_build/zig1_5_clean}"
OUT="${OUT:-/tmp/m9_px_probe}"
CROSS="$ROOT/scripts/win32_cross/cross_nocrt.sh"

rm -rf "$OUT"
mkdir -p "$OUT"

cat > "$OUT/px_probe.zig" <<'PROBE_EOF'
const px = @import("std_gfx_px");
const pal = @import("std_gfx_pal");
const gfx = @import("std_gfx");
const io = @import("std_io");
const os = @import("std_os");

pub fn main() void {
    const g = px.gfxPxOpen("UNDERSANDED PX PROBE", 640, 480) catch {
        io.write("PXPROBE open-failed\n");
        return;
    };
    if (!pal.pxWindowVisible(g.opaque.win)) {
        io.write("PXPROBE visible=0\n");
        px.gfxPxClose(g);
        return;
    }
    io.write("PXPROBE visible=1\n");
    const sf = px.gfxPxLock(g) catch {
        io.write("PXPROBE lock-failed\n");
        px.gfxPxClose(g);
        return;
    };
    var y: i32 = 0;
    while (y < 480) : (y += 1) {
        const row = sf.pixels + @intCast(usize, y) * @intCast(usize, sf.pitch);
        var x: i32 = 0;
        while (x < 640) : (x += 1) {
            const r: u16 = @intCast(u16, x * 31 / 639);
            const gg: u16 = @intCast(u16, y * 63 / 479);
            const b: u16 = @intCast(u16, (x + y) * 31 / 1118);
            const c: u16 = (r << 11) | (gg << 5) | b;
            const off = @intCast(usize, x * 2);
            row[off] = @intCast(u8, c & 0xFF);
            row[off + 1] = @intCast(u8, (c >> 8) & 0xFF);
        }
    }
    px.gfxPxUnlock(g);
    if (pal.pxGdiPresent565(g.opaque.win, g.opaque.px_surface, 32, 16, 64, 32)) {
        io.write("PXPROBE gdi-present=1\n");
    } else {
        io.write("PXPROBE gdi-present=0\n");
    }
    px.gfxPxPresent(g, 0, 0, 640, 480);
    var ev: gfx.Event = undefined;
    while (px.gfxPxPollEvent(g, &ev)) {}
    const mem = gfx.gfxOpenMemory(80, 30) catch return;
    if (px.gfxPxAttach(mem) != null) {
        io.write("PXPROBE memattach=non-null\n");
    } else {
        io.write("PXPROBE memattach=null\n");
    }
    gfx.gfxClose(mem);
    io.write("PXPROBE ok 640x480 ramp presented\n");
    io.sleepMs(250);
    px.gfxPxClose(g);
    os.exit(0);
}
PROBE_EOF

if [ ! -x "$ZIG" ]; then
    echo "EVIDENCE-SKIP: px probe compiler missing at $ZIG (not built)"
    exit 0
fi
if [ ! -f "$CROSS" ]; then
    echo "EVIDENCE-SKIP: cross harness missing at $CROSS"
    exit 0
fi

ROOT="$ROOT" \
DUMP_TARGET="-osw" \
EXTRA_LIBS="-luser32 -lgdi32" \
    bash "$CROSS" "$ZIG" "$OUT/px_probe.zig" "$OUT/work" "$OUT/px_probe.exe" \
    >"$OUT/build.log" 2>&1
if [ $? -ne 0 ] || [ ! -f "$OUT/px_probe.exe" ]; then
    echo "EVIDENCE-FAIL: px probe did not build (see $OUT/build.log)"
    tail -20 "$OUT/build.log" | sed 's/^/       /'
    exit 1
fi
echo "ok   - px probe.exe built (no-CRT, -osw, user32+gdi32)"

MISSING=""
for tool in wine wineserver Xvfb xdpyinfo; do
    command -v "$tool" >/dev/null 2>&1 || MISSING="$MISSING $tool"
done
if [ -n "$MISSING" ]; then
    echo "EVIDENCE-SKIP: LOUD SKIP — px probe Wine/Xvfb run not executed (missing:$MISSING)"
    echo "operator-hardware: run px_probe.exe on Win98 and confirm 'PXPROBE visible=1' plus 'PXPROBE ok'"
    exit 0
fi
if [ -z "${HOME:-}" ]; then
    echo "EVIDENCE-SKIP: LOUD SKIP — px probe Wine prefix needs \$HOME (unset)"
    exit 0
fi

export WINEARCH=win32
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEPREFIX="$HOME/.cache/m9_px_probe_wineprefix"
mkdir -p "$WINEPREFIX"
wineserver -k >/dev/null 2>&1 || true

DISPLAY_NUM=":88"
export DISPLAY="$DISPLAY_NUM"
Xvfb "$DISPLAY_NUM" -screen 0 1024x768x24 -nolisten tcp \
    >"$OUT/xvfb.log" 2>&1 &
XVFB_PID=$!
i=0
while [ "$i" -lt 50 ]; do
    if xdpyinfo >/dev/null 2>&1; then break; fi
    sleep 0.1
    i=$((i + 1))
done
if ! xdpyinfo >/dev/null 2>&1; then
    kill "$XVFB_PID" 2>/dev/null || true
    wait "$XVFB_PID" 2>/dev/null || true
    echo "EVIDENCE-FAIL: Xvfb did not come up on $DISPLAY_NUM (see $OUT/xvfb.log)"
    exit 1
fi

timeout 180 wineboot -i >"$OUT/wineboot.log" 2>&1 || true
( cd "$OUT" && timeout 120 wine ./px_probe.exe </dev/null ) >"$OUT/probe.log" 2>&1
PROBE_RC=$?

kill "$XVFB_PID" 2>/dev/null || true
wait "$XVFB_PID" 2>/dev/null || true
wineserver -k >/dev/null 2>&1 || true

if [ "$PROBE_RC" -eq 0 ] \
    && grep -q 'PXPROBE visible=1' "$OUT/probe.log" \
    && grep -q 'PXPROBE memattach=null' "$OUT/probe.log" \
    && grep -q 'PXPROBE gdi-present=1' "$OUT/probe.log" \
    && grep -q 'PXPROBE ok' "$OUT/probe.log" \
    && ! grep -q 'gfxPx: present failed' "$OUT/probe.log"; then
    echo "EVIDENCE-PASS: px probe visible, opened 640x480, filled ramp, presented (log $OUT/probe.log)"
else
    echo "EVIDENCE-FAIL: px probe rc=$PROBE_RC (see $OUT/probe.log)"
    tail -20 "$OUT/probe.log" | sed 's/^/       /'
    exit 1
fi
exit 0
