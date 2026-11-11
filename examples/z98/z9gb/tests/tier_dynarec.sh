#!/bin/sh
# tier_dynarec.sh — z9gb P5 dynarec block IR unit gate.
#
# Env: ZIG  compiler (first positional arg, else $ZIG, else the P2 seed path)
#      OUT  scratch dir (default /tmp/z9gb_tier_dynarec)
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZS_FIRST="${1:-}"
ZIG="${1:-${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}}"
if [ "$#" -gt 0 ]; then shift; fi
OUT="${OUT:-/tmp/z9gb_tier_dynarec}"
if [ -n "${Z9GB_ROM_DIR:-}" ]; then
    ROM_DIR="$Z9GB_ROM_DIR"
elif [ -d /tmp/z9gb_roms ]; then
    ROM_DIR=/tmp/z9gb_roms
elif [ -d "$Z9DIR/testdata/roms" ]; then
    ROM_DIR="$Z9DIR/testdata/roms"
else
    ROM_DIR=/tmp/z9gb_roms
fi

if [ "$ZS_FIRST" = "--emit-ext" ]; then
    dest="${1:-}"
    if [ -z "$dest" ]; then
        echo "usage: tier_dynarec.sh --emit-ext <path>" >&2
        exit 2
    fi
    cat >"$dest" <<'ZIG'
const std = @import("std");
const filemod = @import("std_file");
const emumod = @import("z9gb/emu.zig");
const mmumod = @import("z9gb/mmu.zig");

const FB_BYTES: usize = 160 * 144 * 4;
const SERIAL_CAP: usize = 65536;
const PROTO_CAP: usize = 1024;

var g_emu: emumod.Emu = undefined;
var g_serial: [SERIAL_CAP]u8 = undefined;
var g_serial_len: usize = 0;
var g_fb: [FB_BYTES]u8 = undefined;
var g_proto: [PROTO_CAP]u8 = undefined;
var g_proto_len: usize = 0;
var g_proto_status: i32 = -1;
var g_audio: usize = 0;
var g_audio_buf: [4096]i16 = undefined;

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}
fn parseU32(s: []const u8) u32 {
    var v: u32 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c: u8 = s[i];
        if (c < '0' or c > '9') return 0;
        v = v * 10 + @intCast(u32, c - '0');
    }
    return v;
}
fn printU(v: usize) void {
    const x: u32 = @intCast(u32, v & 0xffffffff);
    std.io.printInt(@intCast(i32, x & 0x7fffffff));
}
fn printI(v: i32) void { std.io.printInt(v); }
fn join(prefix: []const u8, suffix: []const u8, buf: []u8) []const u8 {
    var n: usize = 0;
    while (n < prefix.len and n < buf.len) : (n += 1) buf[n] = prefix[n];
    var i: usize = 0;
    while (i < suffix.len and n < buf.len) : (i += 1) { buf[n] = suffix[i]; n += 1; }
    return buf[0..n];
}
fn writeOut(prefix: []const u8, suffix: []const u8, data: []const u8) bool {
    var buf: [512]u8 = undefined;
    const path: []const u8 = join(prefix, suffix, buf[0..]);
    filemod.writeAll(path, data) catch return false;
    return true;
}
fn readMem(addr: u16) u8 { return mmumod.read8(&g_emu.bus, addr); }
fn drainSerial() void {
    while (g_serial_len < SERIAL_CAP) {
        const got: usize = emumod.emuTakeSerial(&g_emu, g_serial[g_serial_len..SERIAL_CAP]);
        if (got == 0) break;
        g_serial_len += got;
    }
}
fn drainAudio() void {
    while (true) {
        const got: usize = emumod.emuAudioSamples(&g_emu, g_audio_buf[0..]);
        g_audio += got;
        if (got < g_audio_buf.len) break;
    }
}
fn putLe32(buf: []u8, off: usize, v: u32) void {
    buf[off] = @intCast(u8, v & 0xff);
    buf[off + 1] = @intCast(u8, (v >> 8) & 0xff);
    buf[off + 2] = @intCast(u8, (v >> 16) & 0xff);
    buf[off + 3] = @intCast(u8, (v >> 24) & 0xff);
}
fn protocolCheck() void {
    if (readMem(0xA001) != 0xDE or readMem(0xA002) != 0xB0 or readMem(0xA003) != 0x61) return;
    const status: u8 = readMem(0xA000);
    if (status == 0x80 or status == 0xFF) return;
    g_proto_status = @intCast(i32, status);
    g_proto_len = 0;
    while (g_proto_len < PROTO_CAP) : (g_proto_len += 1) {
        const c: u8 = readMem(@intCast(u16, 0xA004 + g_proto_len));
        if (c == 0) break;
        g_proto[g_proto_len] = c;
    }
}
fn reportMooneye() void {
    if (!emumod.emuMooneyeStopped(&g_emu)) {
        std.io.write("mooneye: TIMEOUT\n");
        return;
    }
    var sig: [6]u8 = undefined;
    emumod.emuMooneyeSignature(&g_emu, sig[0..]);
    std.io.write("mooneye: ");
    if (emumod.emuMooneyePass(&g_emu)) std.io.write("PASS") else std.io.write("FAIL");
    std.io.write(" B="); printU(@intCast(usize, sig[0]));
    std.io.write(" C="); printU(@intCast(usize, sig[1]));
    std.io.write(" D="); printU(@intCast(usize, sig[2]));
    std.io.write(" E="); printU(@intCast(usize, sig[3]));
    std.io.write(" H="); printU(@intCast(usize, sig[4]));
    std.io.write(" L="); printU(@intCast(usize, sig[5]));
    std.io.write("\n");
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    if (n < 7) std.os.exit(2);
    const rom: []const u8 = argAt(argv, 1);
    const frames: u32 = parseU32(argAt(argv, 2));
    const cgb: bool = parseU32(argAt(argv, 3)) != 0;
    const dyn: bool = parseU32(argAt(argv, 4)) != 0;
    const mooneye: bool = parseU32(argAt(argv, 5)) != 0;
    const prefix: []const u8 = argAt(argv, 6);

    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = cgb, .serial_log = false, .turbo = true, .dynarec = dyn });
    emumod.emuLoadRom(&g_emu, rom) catch {
        std.io.write("GATE_FAIL load\n");
        std.os.exit(1);
    };
    emumod.emuReset(&g_emu);
    emumod.emuSetMooneye(&g_emu, mooneye);

    var f: u32 = 0;
    while (f < frames) : (f += 1) {
        _ = emumod.emuRunFrame(&g_emu);
        drainSerial();
        drainAudio();
        protocolCheck();
        if (mooneye and emumod.emuMooneyeStopped(&g_emu)) break;
    }
    drainSerial();
    drainAudio();

    const fb: []const u32 = emumod.emuFramebuffer(&g_emu);
    var i: usize = 0;
    while (i < fb.len) : (i += 1) putLe32(g_fb[0..], i * 4, fb[i]);
    if (!writeOut(prefix, ".serial", g_serial[0..g_serial_len])) std.os.exit(3);
    if (!writeOut(prefix, ".fb", g_fb[0..])) std.os.exit(3);
    if (!writeOut(prefix, ".ram", g_emu.cart.ram[0..g_emu.cart.ram_size])) std.os.exit(3);
    if (!writeOut(prefix, ".proto", g_proto[0..g_proto_len])) std.os.exit(3);

    std.io.write("frames="); printU(@intCast(usize, f));
    std.io.write(" audio="); printU(g_audio);
    std.io.write(" serial_len="); printU(g_serial_len);
    std.io.write(" ram_len="); printU(g_emu.cart.ram_size);
    std.io.write(" protocol_status="); printI(g_proto_status);
    std.io.write(" protocol_len="); printU(g_proto_len);
    std.io.write("\n");
    if (mooneye) reportMooneye();
    if (dyn) {
        const st = emumod.emuDynarecStats(&g_emu);
        if (emumod.emuDynarecEnabled(&g_emu)) {
            std.io.write("dynarec=on blocks="); printU(@intCast(usize, st.blocks));
            std.io.write(" executed="); printU(@intCast(usize, st.executed));
            std.io.write(" fallback="); printU(@intCast(usize, st.fallback));
            std.io.write("\n");
        } else {
            std.io.write("dynarec=disabled\n");
        }
    }
    std.os.exit(0);
}
ZIG
    exit 0
fi

PASSES=0

FAILS=0
pass_case() { echo "ok   - $1"; PASSES=$((PASSES + 1)); }
fail_case() { echo "FAIL - $1"; FAILS=$((FAILS + 1)); }

if [ ! -x "$ZIG" ]; then
    echo "FAIL: compiler not found: $ZIG"
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

SKIPS=0
skip_case() { echo "SKIP - $1"; SKIPS=$((SKIPS + 1)); }

have_win_tools() {
    for t in i686-w64-mingw32-gcc wine; do
        command -v "$t" >/dev/null 2>&1 || return 1
    done
    return 0
}

build_cross() {
    entry="$1"
    dir="$2"
    exe="$3"
    flag="$4"
    mkdir -p "$dir"
    ln -sfn "$Z9DIR" "$dir/z9gb"
    cat >"$dir/gcc_o2.sh" <<'SH'
#!/bin/sh
exec i686-w64-mingw32-gcc -O2 "$@"
SH
    chmod +x "$dir/gcc_o2.sh"
    EXTRA_LIBS="-luser32 -lgdi32 -lwinmm" CROSS_GCC="$dir/gcc_o2.sh" \
        DUMP_TARGET="-osw $flag -I $ROOT/sf/src" \
        bash "$ROOT/scripts/win32_cross/cross_nocrt.sh" "$ZIG" "$entry" \
        "$dir/work" "$exe" >"$dir/build.log" 2>&1
}

setup_wine() {
    WIN_HOME="$OUT/winehome"
    mkdir -p "$WIN_HOME"
    printf 'pcm.!default { type null }\nctl.!default { type null }\n' >"$WIN_HOME/.asoundrc"
    HOME="$WIN_HOME"
    export HOME
    WINEPREFIX="$OUT/wineprefix"
    export WINEPREFIX
    WINEARCH=win32
    export WINEARCH
    WINEDEBUG="${WINEDEBUG:--all}"
    export WINEDEBUG
    wineserver -k >/dev/null 2>&1 || true
    wineboot -u >"$OUT/wineboot.log" 2>&1 || true
    wine reg add 'HKCU\Software\Wine\Drivers' /v Audio /t REG_SZ /d alsa /f >/dev/null 2>&1 || true
}

run_unit_mode() {
    mode="$1"
    flag="$2"
    bin="$OUT/$mode/dynarec_test"
    mkdir -p "$OUT/$mode"
    if timeout 120 "$ZIG" "$flag" -I "$ROOT/sf/src" -o "$OUT/$mode" "$Z9DIR/tests/dynarec_test.zig" >"$OUT/$mode/zig.log" 2>&1; then
        pass_case "dynarec $mode emits"
    else
        fail_case "dynarec $mode emits"
        tail -20 "$OUT/$mode/zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$OUT/$mode/build_target.sh" linux "$bin" >"$OUT/$mode/build.log" 2>&1; then
        pass_case "dynarec $mode links"
    else
        fail_case "dynarec $mode links"
        tail -20 "$OUT/$mode/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 60 "$bin" >"$OUT/$mode/run.out" 2>"$OUT/$mode/run.err"; then
        pass_case "dynarec $mode runs"
    else
        fail_case "dynarec $mode runs"
        tail -20 "$OUT/$mode/run.err" | sed 's/^/       /'
        return
    fi
    if grep -q '^dynarec ok ' "$OUT/$mode/run.out"; then
        pass_case "dynarec $mode output ($(cat "$OUT/$mode/run.out"))"
    else
        fail_case "dynarec $mode output (got $(cat "$OUT/$mode/run.out"))"
    fi
}

run_cli_host_gate() {
    cli="$OUT/cli"
    bin="$cli/z9gb"
    mkdir -p "$cli"
    if timeout 120 "$ZIG" -ffast -I "$ROOT/sf/src" -o "$cli" "$Z9DIR/main.zig" >"$cli/zig.log" 2>&1; then
        pass_case "dynarec cli emits"
    else
        fail_case "dynarec cli emits"
        tail -20 "$cli/zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$cli/build_target.sh" linux "$bin" >"$cli/build.log" 2>&1; then
        pass_case "dynarec cli links"
    else
        fail_case "dynarec cli links"
        tail -20 "$cli/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 60 "$bin" --headless --frames 0 --dynarec --dynarec-stats >"$cli/run.out" 2>"$cli/run.err"; then
        pass_case "dynarec cli runs"
    else
        fail_case "dynarec cli runs"
        tail -20 "$cli/run.err" | sed 's/^/       /'
        return
    fi
    if grep -qx 'dynarec=disabled reason=unsupported-host' "$cli/run.out"; then
        pass_case "dynarec cli non-Win32 disabled reason"
    else
        fail_case "dynarec cli non-Win32 disabled reason (got $(cat "$cli/run.out"))"
    fi
}

audio_close() {
    off="$1"
    on="$2"
    frames="$3"
    [ -n "$off" ] && [ -n "$on" ] || return 1
    [ "$on" -gt 0 ] || return 1
    if [ "$on" -ge "$off" ]; then delta=$((on - off)); else delta=$((off - on)); fi
    limit=$((frames * 16 + 64))
    [ "$delta" -le "$limit" ]
}

run_win_supp() {
    if ! have_win_tools; then
        skip_case "dynarec Win32 supplemental host"
        return
    fi
    win="$OUT/win"
    mkdir -p "$win"
    ln -sfn "$Z9DIR" "$win/z9gb"
    sh "$SCRIPT_DIR/tier_dynarec.sh" --emit-ext "$win/ext.zig" || {
        fail_case "dynarec ext harness emit"
        return
    }

    cat >"$win/cov.zig" <<'ZIG'
const std = @import("std");
const cartmod = @import("z9gb/cart.zig");
const mmumod = @import("z9gb/mmu.zig");
const cpumod = @import("z9gb/cpu.zig");
const cachemod = @import("z9gb/dynarec/cache.zig");
const dynarecmod = @import("z9gb/dynarec/dynarec.zig");
const blockmod = @import("z9gb/dynarec/block.zig");

var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_cpu: cpumod.Cpu = undefined;
var g_dyn: cachemod.Dynarec = undefined;
var g_rom: [0x8000]u8 = undefined;
var g_pass: u32 = 0;
var g_fail: u32 = 0;

fn printU(v: usize) void {
    const x: u32 = @intCast(u32, v & 0xffffffff);
    std.io.printInt(@intCast(i32, x & 0x7fffffff));
}
fn fail1(label: []const u8) void {
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write("\n");
}
fn romClear() void {
    var i: usize = 0;
    while (i < g_rom.len) : (i += 1) g_rom[i] = 0;
}
fn installPages() void {
    var i: usize = 0;
    while (i < 0x40) : (i += 1) {
        g_bus.pages[i] = mmumod.Page{ .kind = .rom0, .base = @ptrCast([*]u8, &g_rom[i * 256]) };
        g_bus.pages[0x40 + i] = mmumod.Page{ .kind = .romx, .base = @ptrCast([*]u8, &g_rom[0x4000 + i * 256]) };
    }
    g_cart.rom0_off = 0;
    g_cart.romx_off = 0;
}
fn fresh() void {
    cartmod.cartInit(&g_cart);
    g_cart.rom = g_rom[0..];
    mmumod.busInit(&g_bus, &g_cart);
    installPages();
    cpumod.cpuInit(&g_cpu);
    g_cpu.a = 0x12;
    g_cpu.f = 0;
    g_cpu.b = 0x34;
    g_cpu.c = 0x56;
    g_cpu.d = 0x78;
    g_cpu.e = 0x9A;
    g_cpu.h = 0xC1;
    g_cpu.l = 0x00;
    g_cpu.sp = 0xD000;
    g_cpu.pc = 0x0100;
    g_cpu.ime = false;
    mmumod.write8(&g_bus, 0xFF80, 0x5A);
    mmumod.write8(&g_bus, 0xC000, 0xA5);
    mmumod.write8(&g_bus, 0xC100, 0x3C);
    mmumod.write8(&g_bus, 0xD000, 0x00);
    mmumod.write8(&g_bus, 0xD001, 0x02);
    mmumod.write8(&g_bus, 0xD002, 0x34);
    mmumod.write8(&g_bus, 0xD003, 0x12);
}
fn insnBytesFor(op: u8) u8 {
    switch (op) {
        0x10, 0xCB, 0x18, 0x20, 0x28, 0x30, 0x38 => return 2,
        0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E, 0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE, 0xE0, 0xF0, 0xE8, 0xF8 => return 2,
        0x01, 0x11, 0x21, 0x31, 0xC2, 0xC3, 0xCA, 0xD2, 0xDA, 0xC4, 0xCC, 0xCD, 0xD4, 0xDC, 0x08, 0xEA, 0xFA => return 3,
        else => return 1,
    }
}
fn fillProg(op: u8, cb2: u8, flags: u8) void {
    romClear();
    var k: usize = 0;
    while (k < 0x8000) : (k += 1) g_rom[k] = 0x76;
    g_cart.rom = g_rom[0..];
    fresh();
    g_cpu.f = flags;
    g_rom[0x0100] = op;
    var at: usize = 0x0101;
    if (op == 0xCB) {
        g_rom[at] = cb2;
        at += 1;
    } else {
        const n = insnBytesFor(op);
        if (n > 1) {
            if (op == 0x18 or op == 0x20 or op == 0x28 or op == 0x30 or op == 0x38) {
                g_rom[at] = 0x00;
            } else if (op == 0xE0 or op == 0xF0 or op == 0xE8 or op == 0xF8) {
                g_rom[at] = 0x80;
            } else if (n == 2) {
                g_rom[at] = 0x5A;
            } else {
                if (op == 0xEA or op == 0x08 or op == 0xFA) {
                    g_rom[at] = 0x00;
                    g_rom[at + 1] = 0xC0;
                } else {
                    g_rom[at] = 0x00;
                    g_rom[at + 1] = 0x02;
                }
            }
            at += n - 1;
        }
    }
    g_rom[at] = 0xC3;
    g_rom[at + 1] = 0x00;
    g_rom[at + 2] = 0x02;
}
const Snap = struct { a: u8, f: u8, b: u8, c: u8, d: u8, e: u8, h: u8, l: u8, sp: u16, pc: u16, halted: bool, cycles: u32 };
fn snap(cycles: u32) Snap {
    return Snap{ .a = g_cpu.a, .f = g_cpu.f, .b = g_cpu.b, .c = g_cpu.c, .d = g_cpu.d, .e = g_cpu.e, .h = g_cpu.h, .l = g_cpu.l, .sp = g_cpu.sp, .pc = g_cpu.pc, .halted = g_cpu.halted, .cycles = cycles };
}
fn snapEq(x: Snap, y: Snap) bool {
    return x.a == y.a and x.f == y.f and x.b == y.b and x.c == y.c and x.d == y.d and x.e == y.e and x.h == y.h and x.l == y.l and x.sp == y.sp and x.pc == y.pc and x.halted == y.halted and x.cycles == y.cycles;
}
fn runOracle() Snap {
    var cyc: u32 = 0;
    var i: u8 = 0;
    while (i < 32 and !g_cpu.halted) : (i += 1) cyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    return snap(cyc);
}
fn runDyn() Snap {
    var cyc: u32 = 0;
    var i: u8 = 0;
    while (i < 32 and !g_cpu.halted) : (i += 1) {
        if (g_cpu.pc > 0x7FFF) {
            cyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
        } else {
            const c: u32 = dynarecmod.dynarecRunBlock(&g_dyn, &g_cpu, &g_bus);
            if (c == 0) cyc +%= cpumod.cpuStep(&g_cpu, &g_bus) else cyc +%= c;
        }
    }
    return snap(cyc);
}
fn illegalPrimary(op: u8) bool {
    return op == 0xD3 or op == 0xDB or op == 0xDD or op == 0xE3 or op == 0xE4 or op == 0xEB or op == 0xEC or op == 0xED or op == 0xF4 or op == 0xFC or op == 0xFD;
}
fn testIllegal(op: u8) void {
    fillProg(op, 0, 0);
    var blk: blockmod.Block = undefined;
    if (!blockmod.blockBuild(&g_cpu, &g_bus, &blk)) {
        fail1("illegal build");
        return;
    }
    if (blk.len != 1 or blk.insns[0].op != blockmod.BlockOp.unsupported or !blk.ends_block) {
        fail1("illegal boundary");
        return;
    }
    g_pass += 2;
}
fn testOp(op: u8, cb2: u8, flags: u8) void {
    fillProg(op, cb2, flags);
    const want: Snap = runOracle();
    const wram0: u8 = g_bus.wram[0];
    const wram1: u8 = g_bus.wram[1];
    const hram0: u8 = g_bus.hram[0];
    fillProg(op, cb2, flags);
    dynarecmod.dynarecFlush(&g_dyn);
    const b0: u32 = g_dyn.stats.blocks;
    const f0: u32 = g_dyn.stats.fallback;
    const got: Snap = runDyn();
    const got_wram0: u8 = g_bus.wram[0];
    const got_wram1: u8 = g_bus.wram[1];
    const got_hram0: u8 = g_bus.hram[0];
    if (!snapEq(got, want)) {
        g_fail += 1;
        std.io.write("FAIL op=");
        printU(@intCast(usize, op));
        if (op == 0xCB) { std.io.write("/cb="); printU(@intCast(usize, cb2)); }
        std.io.write(" flags=");
        printU(@intCast(usize, flags));
        std.io.write(" gotpc=");
        printU(@intCast(usize, got.pc));
        std.io.write(" wantpc=");
        printU(@intCast(usize, want.pc));
        std.io.write(" gotcyc=");
        printU(@intCast(usize, got.cycles));
        std.io.write(" wantcyc=");
        printU(@intCast(usize, want.cycles));
        std.io.write("\n");
        return;
    }
    g_pass += 1;
    if (wram0 != got_wram0 or wram1 != got_wram1 or hram0 != got_hram0) {
        fail1("op memory");
    } else {
        g_pass += 1;
    }
    const bd: u32 = g_dyn.stats.blocks -% b0;
    const fd: u32 = g_dyn.stats.fallback -% f0;
    if (op == 0x10 or op == 0x40 or op == 0x76) {
        if (fd == 0) fail1("op no-fallback") else g_pass += 1;
    } else if (bd == 0) {
        fail1("op not-translated");
    } else {
        g_pass += 1;
    }
}
pub fn main() void {
    if (!dynarecmod.dynarecOpen(&g_dyn, &g_bus)) {
        std.io.write("cov FAIL cache open\n");
        std.os.exit(1);
    }
    fresh();
    var op: u16 = 0;
    while (op < 256) : (op += 1) {
        const o: u8 = @intCast(u8, op);
        if (illegalPrimary(o)) {
            testIllegal(o);
        } else {
            testOp(o, 0, 0x00);
            testOp(o, 0, 0xF0);
        }
    }
    var cb: u16 = 0;
    while (cb < 256) : (cb += 1) {
        testOp(0xCB, @intCast(u8, cb), 0x00);
        testOp(0xCB, @intCast(u8, cb), 0xF0);
    }
    dynarecmod.dynarecClose(&g_dyn);
    std.io.write("cov ");
    if (g_fail == 0) {
        std.io.write("ok ");
        printU(@intCast(usize, g_pass));
        std.io.write(" checks\n");
        std.os.exit(0);
    }
    std.io.write("FAIL ");
    printU(@intCast(usize, g_fail));
    std.io.write(" failed, ");
    printU(@intCast(usize, g_pass));
    std.io.write(" passed\n");
    std.os.exit(1);
}
ZIG

    cat >"$win/mbc.zig" <<'ZIG'
const std = @import("std");
const cartmod = @import("z9gb/cart.zig");
const mmumod = @import("z9gb/mmu.zig");
const cpumod = @import("z9gb/cpu.zig");
const cachemod = @import("z9gb/dynarec/cache.zig");
const dynarecmod = @import("z9gb/dynarec/dynarec.zig");

var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_cpu: cpumod.Cpu = undefined;
var g_dyn: cachemod.Dynarec = undefined;
var g_rom: [0x20000]u8 = undefined;
var g_pass: u32 = 0;
var g_rom_len: usize = 0;
var g_fail: u32 = 0;

fn p(v: usize) void { std.io.printInt(@intCast(i32, @intCast(u32, v & 0x7fffffff))); }
fn ck(label: []const u8, ok: bool) void { if (ok) { g_pass += 1; } else { g_fail += 1; std.io.write("FAIL "); std.io.write(label); std.io.write("\n"); } }
fn eq(label: []const u8, got: u32, want: u32) void { if (got == want) { g_pass += 1; } else { g_fail += 1; std.io.write("FAIL "); std.io.write(label); std.io.write(" got="); p(@intCast(usize,got)); std.io.write(" want="); p(@intCast(usize,want)); std.io.write("\n"); } }
fn buildRom(banks: usize, markers: [8]u8) void {
    var i: usize = 0;
    while (i < g_rom.len) : (i += 1) g_rom[i] = 0;
    g_rom[0x0147] = 0x03;
    g_rom[0x0148] = 0x01;
    g_rom[0x0149] = 0x02;
    var b: usize = 0;
    while (b < banks) : (b += 1) g_rom[b * 0x4000] = markers[b];
    g_rom_len = banks * 0x4000;
    g_cart.rom = g_rom[0..g_rom_len];
}
fn load() bool {
    cartmod.cartInit(&g_cart);
    g_cart.rom = g_rom[0..g_rom_len];
    cartmod.cartLoad(&g_cart, g_cart.rom) catch return false;
    mmumod.busInit(&g_bus, &g_cart);
    cpumod.cpuInit(&g_cpu);
    g_cpu.sp = 0xD000;
    g_cpu.pc = 0x0100;
    g_cpu.f = 0;
    return true;
}
fn runOn(max: usize) u32 {
    var cyc: u32 = 0;
    var i: usize = 0;
    while (i < max and !g_cpu.halted) : (i += 1) {
        const r0 = g_cart.rom0_off;
        const rx = g_cart.romx_off;
        var c = dynarecmod.dynarecRunBlock(&g_dyn, &g_cpu, &g_bus);
        if (c == 0) c = cpumod.cpuStep(&g_cpu, &g_bus);
        cyc +%= c;
        if (g_cart.rom0_off != r0) dynarecmod.dynarecInvalidateRom0(&g_dyn);
        if (g_cart.romx_off != rx) dynarecmod.dynarecInvalidateRomx(&g_dyn);
    }
    return cyc;
}
fn runOff(max: usize) u32 {
    var cyc: u32 = 0;
    var i: usize = 0;
    while (i < max and !g_cpu.halted) : (i += 1) cyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    return cyc;
}
fn put(addr: usize, bytes: []const u8) void {
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) g_rom[addr + i] = bytes[i];
}
fn midblock(want_marker: u8) void {
    var markers: [8]u8 = undefined;
    var mi: usize = 0;
    while (mi < 8) : (mi += 1) markers[mi] = 0;
    markers[0] = 0x00; markers[1] = 0x11; markers[2] = 0x22; markers[3] = 0x33;
    buildRom(4, markers);
    var mid = [_]u8{ 0x3E, 0x02, 0xEA, 0x00, 0x20, 0xFA, 0x00, 0x40, 0xEA, 0x00, 0xC0, 0x76 };
    put(0x0100, mid[0..]);
    var warm = [_]u8{ 0x3E, 0x11, 0xC3, 0x00, 0x02 };
    put(0x4010, warm[0..]);
    ck("mid load", load());
    ck("mid cache", dynarecmod.dynarecOpen(&g_dyn, &g_bus));
    g_cpu.pc = 0x4010;
    _ = dynarecmod.dynarecRunBlock(&g_dyn, &g_cpu, &g_bus);
    ck("mid prewarm", dynarecmod.dynarecLookup(&g_dyn, 1, 0x4010) != null);
    g_cpu.pc = 0x0100; g_cpu.a = 0; g_cpu.halted = false; g_cpu.sp = 0xD000;
    const r0 = g_cart.rom0_off;
    const rx = g_cart.romx_off;
    const c = dynarecmod.dynarecRunBlock(&g_dyn, &g_cpu, &g_bus);
    if (g_cart.rom0_off != r0) dynarecmod.dynarecInvalidateRom0(&g_dyn);
    if (g_cart.romx_off != rx) dynarecmod.dynarecInvalidateRomx(&g_dyn);
    ck("mid block ended at write", g_cpu.pc == 0x0105);
    eq("mid write cycles", c, 24);
    eq("mid bank", @intCast(u32, g_cart.romx_off), 0x8000);
    ck("mid old romx invalidated", dynarecmod.dynarecLookup(&g_dyn, 1, 0x4010) == null);
    _ = runOn(20);
    ck("mid reads fresh bank", g_bus.wram[0] == want_marker);
    dynarecmod.dynarecClose(&g_dyn);
}
fn bankswitch() void {
    var markers: [8]u8 = undefined;
    var mi: usize = 0;
    while (mi < 8) : (mi += 1) markers[mi] = 0;
    markers[0] = 0x00; markers[1] = 0xB1; markers[2] = 0xB2; markers[3] = 0xB3;
    buildRom(4, markers);
    var prog = [_]u8{
        0x3E, 0x01, 0xEA, 0x00, 0x20, 0xFA, 0x00, 0x40, 0xEA, 0x00, 0xC0,
        0x3E, 0x02, 0xEA, 0x00, 0x20, 0xFA, 0x00, 0x40, 0xEA, 0x01, 0xC0,
        0x3E, 0x03, 0xEA, 0x00, 0x20, 0xFA, 0x00, 0x40, 0xEA, 0x02, 0xC0,
        0x3E, 0x02, 0xEA, 0x00, 0x20, 0xFA, 0x00, 0x40, 0xEA, 0x03, 0xC0,
        0x3E, 0xAA, 0xEA, 0xFF, 0xC0, 0x76,
    };
    put(0x0100, prog[0..]);
    ck("bank load", load());
    ck("bank cache", dynarecmod.dynarecOpen(&g_dyn, &g_bus));
    dynarecmod.dynarecFlush(&g_dyn);
    g_dyn.used = cachemod.CODE_CACHE_BYTES - 8;
    const resets0 = g_dyn.stats.resets;
    _ = runOn(200);
    ck("bank halted", g_cpu.halted);
    eq("bank reset forced", g_dyn.stats.resets -% resets0, 1);
    eq("bank m0", g_bus.wram[0], 0xB1);
    eq("bank m1", g_bus.wram[1], 0xB2);
    eq("bank m2", g_bus.wram[2], 0xB3);
    eq("bank m3", g_bus.wram[3], 0xB2);
    eq("bank done", g_bus.wram[0xFF], 0xAA);
    _ = load();
    _ = runOff(200);
    ck("bank off halted", g_cpu.halted);
    eq("bank off m0", g_bus.wram[0], 0xB1);
    eq("bank off m1", g_bus.wram[1], 0xB2);
    eq("bank off m2", g_bus.wram[2], 0xB3);
    eq("bank off m3", g_bus.wram[3], 0xB2);
    dynarecmod.dynarecClose(&g_dyn);
}
pub fn main() void {
    midblock(0x22);
    bankswitch();
    std.io.write("mbc ");
    if (g_fail == 0) { std.io.write("ok "); p(@intCast(usize,g_pass)); std.io.write(" checks\n"); std.os.exit(0); }
    std.io.write("FAIL "); p(@intCast(usize,g_fail)); std.io.write(" failed, "); p(@intCast(usize,g_pass)); std.io.write(" passed\n"); std.os.exit(1);
}
ZIG

    cat >"$win/wram.zig" <<'ZIG'
const std = @import("std");
const cartmod = @import("z9gb/cart.zig");
const emumod = @import("z9gb/emu.zig");

var g_emu: emumod.Emu = undefined;
var g_pass: u32 = 0;
var g_fail: u32 = 0;

fn p(v: usize) void { std.io.printInt(@intCast(i32, @intCast(u32, v & 0x7fffffff))); }
fn ck(label: []const u8, ok: bool) void { if (ok) { g_pass += 1; } else { g_fail += 1; std.io.write("FAIL "); std.io.write(label); std.io.write("\n"); } }
fn eq(label: []const u8, got: u32, want: u32) void { if (got == want) { g_pass += 1; } else { g_fail += 1; std.io.write("FAIL "); std.io.write(label); std.io.write(" got="); p(@intCast(usize,got)); std.io.write(" want="); p(@intCast(usize,want)); std.io.write("\n"); } }
fn put(addr: usize, bytes: []const u8) void { var i: usize = 0; while (i < bytes.len) : (i += 1) g_emu.rom[addr + i] = bytes[i]; }
fn setup(on: bool) void {
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = false, .serial_log = false, .turbo = true, .dynarec = on });
    var i: usize = 0;
    while (i < 0x8000) : (i += 1) g_emu.rom[i] = 0;
    g_emu.rom[0x0147] = 0x00;
    g_emu.rom[0x0148] = 0x00;
    g_emu.rom[0x0149] = 0x00;
    var copy = [_]u8{
        0x3E, 0x3C, 0xEA, 0x00, 0xC0,
        0x3E, 0xEA, 0xEA, 0x01, 0xC0,
        0x3E, 0x00, 0xEA, 0x02, 0xC0,
        0x3E, 0xC0, 0xEA, 0x03, 0xC0,
        0x3E, 0x18, 0xEA, 0x04, 0xC0,
        0x3E, 0xFA, 0xEA, 0x05, 0xC0,
        0xC3, 0x00, 0xC0,
    };
    put(0x0100, copy[0..]);
    var loop = [_]u8{ 0x3C, 0xEA, 0x00, 0xC0, 0x18, 0xFA };
    put(0x0200, loop[0..]);
    g_emu.rom_len = 0x8000;
    cartmod.cartLoad(&g_emu.cart, g_emu.rom[0..0x8000]) catch {};
    emumod.emuReset(&g_emu);
    g_emu.bus.ie = 0;
    g_emu.bus.io[0x0F] = 0;
}
pub fn main() void {
    setup(true);
    ck("wram dyn enabled", emumod.emuDynarecEnabled(&g_emu));
    _ = emumod.emuRunFrame(&g_emu);
    _ = emumod.emuRunFrame(&g_emu);
    const st1 = emumod.emuDynarecStats(&g_emu);
    ck("wram frame2 blocks", st1.blocks > 0);
    ck("wram frame2 executed", st1.executed > 0);
    ck("wram frame2 pc in wram", g_emu.cpu.pc >= 0xC000);
    _ = emumod.emuRunFrame(&g_emu);
    const st2 = emumod.emuDynarecStats(&g_emu);
    eq("wram blocks unchanged", st2.blocks, st1.blocks);
    eq("wram executed unchanged", st2.executed, st1.executed);
    ck("wram fallback grows", st2.fallback > st1.fallback);
    const a_on = g_emu.cpu.a;
    const w_on = g_emu.bus.wram[0];
    var fb_on: [160 * 144]u32 = undefined;
    var i: usize = 0;
    while (i < fb_on.len) : (i += 1) fb_on[i] = emumod.emuFramebuffer(&g_emu)[i];
    setup(false);
    _ = emumod.emuRunFrame(&g_emu);
    _ = emumod.emuRunFrame(&g_emu);
    _ = emumod.emuRunFrame(&g_emu);
    ck("wram off pc in wram", g_emu.cpu.pc >= 0xC000);
    ck("wram off wram0 nonzero", g_emu.bus.wram[0] != 0);
    ck("wram on wram0 nonzero", w_on != 0);
    ck("wram a parity", g_emu.cpu.a == a_on);
    eq("wram off wram0", @intCast(u32, g_emu.bus.wram[0]), @intCast(u32, w_on));
    var fb_same: bool = true;
    i = 0;
    while (i < fb_on.len) : (i += 1) {
        if (fb_on[i] != emumod.emuFramebuffer(&g_emu)[i]) fb_same = false;
    }
    ck("wram framebuffer parity", fb_same);
    std.io.write("wram ");
    if (g_fail == 0) { std.io.write("ok "); p(@intCast(usize,g_pass)); std.io.write(" checks\n"); std.os.exit(0); }
    std.io.write("FAIL "); p(@intCast(usize,g_fail)); std.io.write(" failed, "); p(@intCast(usize,g_pass)); std.io.write(" passed\n"); std.os.exit(1);
}
ZIG

    for h in cov mbc wram ext; do
        if build_cross "$win/$h.zig" "$win" "$win/$h.exe" -ffast; then
            pass_case "dynarec win32 $h builds"
        else
            fail_case "dynarec win32 $h builds"
            tail -10 "$win/build.log" | sed 's/^/       /'
            continue
        fi
        if [ "$h" = "ext" ]; then
            continue
        fi
        if timeout 180 wine "$win/$h.exe" >"$win/$h.out" 2>"$win/$h.err"; then
            if grep -q "^$h ok " "$win/$h.out"; then
                pass_case "dynarec win32 $h ($(cat "$win/$h.out"))"
            else
                fail_case "dynarec win32 $h output (got $(cat "$win/$h.out"))"
            fi
        else
            fail_case "dynarec win32 $h run"
            tail -10 "$win/$h.err" | sed 's/^/       /'
        fi
    done
}

run_2048() {
    if ! have_win_tools; then
        skip_case "dynarec 2048 Win32 host"
        return
    fi
    ROM=""
    for cand in "$ROM_DIR/2048.gb" "$ROM_DIR/homebrew/2048.gb"; do
        if [ -f "$cand" ]; then ROM="$cand"; break; fi
    done
    if [ -z "$ROM" ]; then
        skip_case "2048.gb under $ROM_DIR"
        return
    fi
    if [ "$(stat -c %s "$ROM" 2>/dev/null)" != "32768" ]; then
        fail_case "2048.gb size"
        return
    fi
    want="$(awk '$2 == "2048.gb" { print $1; exit }' "$Z9DIR/testdata/roms/manifest.sha256" 2>/dev/null)"
    got="$(sha256sum "$ROM" | cut -d' ' -f1)"
    if [ -n "$want" ] && [ "$got" != "$want" ]; then
        fail_case "2048.gb sha256"
        return
    fi
    win="$OUT/win"
    mkdir -p "$win/2048"
    cp "$ROM" "$win/2048/off.gb"
    cp "$ROM" "$win/2048/on.gb"
    if ! build_cross "$Z9DIR/main.zig" "$win" "$win/z9gb.exe" -ffast; then
        fail_case "dynarec 2048 CLI builds"
        tail -10 "$win/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 120 wine "$win/z9gb.exe" --headless --frames 600 --serial --save \
        --no-dynarec --rom "$win/2048/off.gb" --fb-out "$win/2048/off.fb" \
        >"$win/2048/off.log" 2>"$win/2048/off.err"; then
        pass_case "2048 CLI --no-dynarec runs"
    else
        fail_case "2048 CLI --no-dynarec runs"
        return
    fi
    if timeout 120 wine "$win/z9gb.exe" --headless --frames 600 --serial --save \
        --dynarec --rom "$win/2048/on.gb" --fb-out "$win/2048/on.fb" \
        >"$win/2048/on.log" 2>"$win/2048/on.err"; then
        pass_case "2048 CLI --dynarec runs"
    else
        fail_case "2048 CLI --dynarec runs"
        return
    fi
    if cmp -s "$win/2048/off.fb" "$win/2048/on.fb"; then
        pass_case "2048 framebuffer hash parity"
    else
        fail_case "2048 framebuffer hash parity"
    fi
    if cmp -s "$win/2048/off.log" "$win/2048/on.log"; then
        pass_case "2048 serial log parity"
    else
        # The dynarec run appends its anti-vacuous counter line.
        grep -v '^dynarec=' "$win/2048/on.log" >"$win/2048/on.clean"
        if cmp -s "$win/2048/off.log" "$win/2048/on.clean"; then
            pass_case "2048 serial log parity (stats line excluded)"
        else
            fail_case "2048 serial log parity"
        fi
    fi
    if [ -f "$win/2048/off.sav" ] || [ -f "$win/2048/on.sav" ]; then
        if cmp -s "$win/2048/off.sav" "$win/2048/on.sav"; then
            pass_case "2048 save RAM parity"
        else
            fail_case "2048 save RAM parity"
        fi
    else
        pass_case "2048 save RAM parity (no battery save)"
    fi
    if grep -q '^dynarec=on blocks=' "$win/2048/on.log"; then
        on_blocks="$(sed -n 's/^dynarec=on blocks=\([0-9]*\) executed=\([0-9]*\).*/\1/p' "$win/2048/on.log")"
        on_exec="$(sed -n 's/^dynarec=on blocks=\([0-9]*\) executed=\([0-9]*\).*/\2/p' "$win/2048/on.log")"
        if [ -n "$on_blocks" ] && [ "$on_blocks" -gt 0 ] && [ -n "$on_exec" ] && [ "$on_exec" -gt 0 ]; then
            pass_case "2048 anti-vacuous dynarec=on blocks=$on_blocks executed=$on_exec"
        else
            fail_case "2048 anti-vacuous counters"
        fi
    else
        fail_case "2048 dynarec=on counter line missing"
    fi
    if [ -x "$win/ext.exe" ]; then
        if timeout 120 wine "$win/ext.exe" "$ROM" 600 0 0 0 "$win/2048/ext_off" >"$win/2048/ext_off.log" 2>&1 \
            && timeout 120 wine "$win/ext.exe" "$ROM" 600 0 1 0 "$win/2048/ext_on" >"$win/2048/ext_on.log" 2>&1; then
            off_audio="$(sed -n 's/.* audio=\([0-9]*\).*/\1/p' "$win/2048/ext_off.log" | head -1)"
            on_audio="$(sed -n 's/.* audio=\([0-9]*\).*/\1/p' "$win/2048/ext_on.log" | head -1)"
            if audio_close "$off_audio" "$on_audio" 600; then
                pass_case "2048 audio sample count parity (off=$off_audio on=$on_audio)"
            else
                fail_case "2048 audio sample count parity (off=$off_audio on=$on_audio)"
            fi
        else
            fail_case "2048 audio parity runs"
        fi
    else
        skip_case "2048 audio parity (no ext harness)"
    fi
}

echo "== dynarec block IR builder vs interpreter oracle =="
run_unit_mode fast -ffast
run_unit_mode safe -fsafe

echo "== dynarec CLI host gate =="
run_cli_host_gate

echo "== dynarec Win32 supplemental gates =="
if have_win_tools; then
    setup_wine
fi
run_win_supp

echo "== homebrew 2048 on/off parity =="
run_2048

if command -v wineserver >/dev/null 2>&1; then
    wineserver -k >/dev/null 2>&1 || true
fi

echo
echo "== tier_dynarec summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_DYNAREC FAIL"
    exit 1
fi
if [ "$SKIPS" -ne 0 ]; then
    echo "TIER_DYNAREC SKIP"
    exit 77
fi
echo "TIER_DYNAREC PASS"
exit 0
