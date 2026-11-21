#!/bin/sh
# run_interrupt_time.sh — z9gb interrupt_time memory-protocol hard gate.
#
# The pinned Blargg interrupt_time ROM reports through its documented memory protocol
# ($A000 status, $DE,$B0,$61 signature at $A001-$A003, zero-terminated text at
# $A004), not through the serial port. The gate runs with CGB hardware enabled,
# turbo on, and the 200,000-frame cap. PASS requires status 0, a terminal
# "Passed", and no "Failed"; any nonzero terminal status is a fail code. Hitting
# the cap without the magic/verdict is FAIL, never PASS.
#
# A missing ROM is `SKIP: <path>` (exit 77).
#
# Env:
#   ZIG                  compiler (or pass it as the first argument)
#   Z9GB_ROM_DIR         ROM root (default /tmp/z9gb_roms, else testdata/roms)
#   OUT                  scratch dir (default /tmp/z9gb_gate_interrupt_time)
#   Z9GB_CGB_GATE_TIMEOUT per-ROM wall-clock seconds (default 900)

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}"
OUT="${OUT:-/tmp/z9gb_gate_interrupt_time}"

if [ "$#" -gt 0 ]; then
    ZIG="$1"
    shift
fi

if [ -n "${Z9GB_ROM_DIR:-}" ]; then
    ROM_DIR="$Z9GB_ROM_DIR"
elif [ -d /tmp/z9gb_roms ]; then
    ROM_DIR=/tmp/z9gb_roms
elif [ -d "$Z9DIR/testdata/roms" ]; then
    ROM_DIR="$Z9DIR/testdata/roms"
else
    ROM_DIR=/tmp/z9gb_roms
fi

ROM="$ROM_DIR/blargg/interrupt_time/interrupt_time.gb"
if [ ! -f "$ROM" ]; then
    echo "SKIP: $ROM"
    exit 77
fi

want="$(awk '$2 == "blargg/interrupt_time/interrupt_time.gb" { print $1; exit }' \
    "$Z9DIR/testdata/roms/manifest.sha256" 2>/dev/null)"
if [ -z "$want" ]; then
    echo "FAIL: interrupt_time manifest row missing"
    exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "$ROM" | cut -d' ' -f1)"
    if [ "$got" != "$want" ]; then
        echo "FAIL: interrupt_time sha256 mismatch (got $got, want $want)"
        exit 1
    fi
    echo "interrupt_time: sha256 $got"
fi

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi
rm -rf "$OUT"
mkdir -p "$OUT"
ln -s "$Z9DIR" "$OUT/z9gb"

cat >"$OUT/gate.zig" <<'ZIG'
const std = @import("std");
const emumod = @import("z9gb/emu.zig");
const mmumod = @import("z9gb/mmu.zig");

var g_emu: emumod.Emu = undefined;
var g_text: [1024]u8 = undefined;

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn readMem(addr: u16) u8 {
    return mmumod.read8(&g_emu.bus, addr);
}

fn hasWord(text: []const u8, word: []const u8) bool {
    if (word.len == 0 or text.len < word.len) return false;
    var i: usize = 0;
    while (i + word.len <= text.len) : (i += 1) {
        var j: usize = 0;
        var ok: bool = true;
        while (j < word.len) : (j += 1) {
            if (text[i + j] != word[j]) {
                ok = false;
                break;
            }
        }
        if (ok) return true;
    }
    return false;
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    if (n < 2) std.os.exit(2);
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = true, .serial_log = false, .turbo = true, .dynarec = false });
    emumod.emuLoadRom(&g_emu, argAt(argv, 1)) catch {
        std.io.write("GATE_FAIL load\n");
        std.os.exit(1);
    };
    emumod.emuReset(&g_emu);
    var f: u32 = 0;
    while (f < 200000) : (f += 1) {
        _ = emumod.emuRunFrame(&g_emu);
        const magic: bool = readMem(0xA001) == 0xDE and readMem(0xA002) == 0xB0 and readMem(0xA003) == 0x61;
        if (!magic) continue;
        const status: u8 = readMem(0xA000);
        if (status == 0x80 or status == 0xFF) continue;

        var len: usize = 0;
        while (len < g_text.len) : (len += 1) {
            const c: u8 = readMem(@intCast(u16, 0xA004 + len));
            if (c == 0) break;
            g_text[len] = c;
        }
        std.io.write(g_text[0..len]);
        std.io.write("\n");
        const text: []const u8 = g_text[0..len];
        const failed: bool = hasWord(text, "Failed");
        const passed: bool = hasWord(text, "Passed");
        std.io.write("frames=");
        std.io.printInt(@intCast(i32, f & 0x7fffffff));
        std.io.write(" status=");
        std.io.printInt(@intCast(i32, status));
        std.io.write("\n");
        if (status == 0 and passed and !failed) {
            std.io.write("GATE_PASS\n");
            std.os.exit(0);
        }
        std.io.write("GATE_FAIL\n");
        std.os.exit(1);
    }
    std.io.write("GATE_FAIL timeout\n");
    std.os.exit(1);
}
ZIG

if ! timeout 120 "$ZIG" -ffast -I "$ROOT/sf/src" -o "$OUT" "$OUT/gate.zig" >"$OUT/gate_zig.log" 2>&1; then
    echo "FAIL: interrupt_time gate emits"
    tail -20 "$OUT/gate_zig.log" | sed 's/^/  /' >&2
    exit 1
fi
if [ -f "$OUT/build_target.sh" ]; then
    sed 's/-O0/-O2/g' "$OUT/build_target.sh" >"$OUT/build_target.sh.tmp" && mv "$OUT/build_target.sh.tmp" "$OUT/build_target.sh"
fi
if [ ! -f "$OUT/build_target.sh" ] || ! sh "$OUT/build_target.sh" linux "$OUT/interrupt_time_gate" >"$OUT/gate_build.log" 2>&1; then
    echo "FAIL: interrupt_time gate links"
    tail -20 "$OUT/gate_build.log" | sed 's/^/  /' >&2
    exit 1
fi

timeout "${Z9GB_CGB_GATE_TIMEOUT:-900}" "$OUT/interrupt_time_gate" "$ROM" \
    >"$OUT/gate.out" 2>"$OUT/gate.err"
rc=$?
if [ "$rc" -eq 0 ]; then
    grep -E 'GATE_PASS|Passed|status=|frames=' "$OUT/gate.out" | sed 's/^/  /'
    echo "interrupt_time: PASS"
    exit 0
fi
grep -E 'GATE_FAIL|Failed|status=|frames=' "$OUT/gate.out" | sed 's/^/  /'
if [ "$rc" -eq 124 ]; then
    echo "FAIL: interrupt_time (wall-clock timeout)"
else
    echo "FAIL: interrupt_time (no terminal Passed before frame cap)"
fi
tail -10 "$OUT/gate.err" | sed 's/^/  /' >&2
exit 1
