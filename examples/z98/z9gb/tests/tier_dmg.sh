#!/bin/sh
# tier_dmg.sh — z9gb P2 DMG core gates.
#
# Env: ZIG  compiler (first positional arg, else $ZIG, else the P2 seed path)
#      OUT  scratch dir (default /tmp/z9gb_tier_dmg)
#
# POSIX sh + coreutils. Run from anywhere (paths resolved from this script).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
Z9DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$Z9DIR/../../.." && pwd)"
ZIG="${1:-${ZIG:-/tmp/z9gb_p2_seed/zig1_5_clean}}"
if [ "$#" -gt 0 ]; then shift; fi
OUT="${OUT:-/tmp/z9gb_tier_dmg}"

ONLY=""
RUN_ALL=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --only)
            shift
            if [ "$#" -eq 0 ]; then
                echo "usage: tier_dmg.sh <zig> [--only cart|cpu|timer|ppu] [--all]" >&2
                exit 2
            fi
            ONLY="$1"
            ;;
        --only=*)
            ONLY="${1#--only=}"
            ;;
        --all)
            RUN_ALL=1
            ;;
        *)
            echo "usage: tier_dmg.sh <zig> [--only cart|cpu|timer|ppu] [--all]" >&2
            exit 2
            ;;
    esac
    shift
done

if [ "$RUN_ALL" -eq 1 ]; then
    ONLY=""
fi
RUN_CART=0
RUN_CPU=0
RUN_TIMER=0
RUN_PPU=0
if [ -z "$ONLY" ]; then
    RUN_CART=1
    RUN_CPU=1
    RUN_TIMER=1
    RUN_PPU=1
elif [ "$ONLY" = "cart" ]; then
    RUN_CART=1
elif [ "$ONLY" = "cpu" ]; then
    RUN_CPU=1
elif [ "$ONLY" = "timer" ]; then
    RUN_TIMER=1
elif [ "$ONLY" = "ppu" ]; then
    RUN_PPU=1
else
    echo "unknown tier: $ONLY" >&2
    exit 2
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
ln -s "$Z9DIR" "$OUT/z9gb"

cat >"$OUT/cart_test.zig" <<'ZIG'
const std = @import("std");
const filemod = @import("std_file");
const cartmod = @import("z9gb/cart.zig");

const ROM_BYTES: usize = 32768;
var g_rom: [ROM_BYTES]u8 = undefined;
var g_cart: cartmod.Cart = undefined;
var g_arena_buf: [1]u8 = undefined;

fn argAt(argv: [*][*]u8, i: usize) []const u8 {
    const p: [*]const u8 = @ptrCast([*]const u8, argv[i]);
    var n: usize = 0;
    while (p[n] != 0) : (n += 1) {}
    return p[0..n];
}

fn printU(v: usize) void {
    const x: u32 = @intCast(u32, v & 0xffffffff);
    std.io.printInt(@intCast(i32, x & 0x7fffffff));
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    if (n < 2) std.os.exit(1);
    const path: []const u8 = argAt(argv, 1);

    var arena = std.arena.init(g_arena_buf[0..]);
    var f = filemod.open(&arena, path, filemod.Mode.Read) catch {
        std.os.exit(2);
        return;
    };
    const sz = filemod.size(&f) catch {
        filemod.close(&f);
        std.os.exit(2);
        return;
    };
    if (sz != @intCast(i64, ROM_BYTES)) {
        filemod.close(&f);
        std.os.exit(3);
    }

    var got: usize = 0;
    while (got < ROM_BYTES) {
        const r = filemod.read(&f, g_rom[got..ROM_BYTES]) catch {
            filemod.close(&f);
            std.os.exit(2);
            return;
        };
        if (r == 0) break;
        got += r;
    }
    filemod.close(&f);
    if (got != ROM_BYTES) std.os.exit(3);

    cartmod.cartLoad(&g_cart, g_rom[0..ROM_BYTES]) catch {
        std.io.write("cart err\n");
        std.os.exit(4);
        return;
    };

    std.io.write("cart ok mbc=");
    printU(@intCast(usize, @enumToInt(g_cart.mbc)));
    std.io.write(" rom=");
    printU(g_cart.rom_size);
    std.io.write(" ram=");
    printU(g_cart.ram_size);
    std.io.write("\n");
    std.os.exit(0);
}
ZIG

cat >"$OUT/timer_test.zig" <<'ZIG'
const std = @import("std");
const cartmod = @import("z9gb/cart.zig");
const mmumod = @import("z9gb/mmu.zig");
const cpumod = @import("z9gb/cpu.zig");
const timermod = @import("z9gb/timer.zig");
const serialmod = @import("z9gb/serial.zig");
const emumod = @import("z9gb/emu.zig");

const CODE: u16 = 0xC000;

var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_cpu: cpumod.Cpu = undefined;
var g_emu: emumod.Emu = undefined;
var g_pass: u32 = 0;
var g_fail: u32 = 0;

fn printU(v: usize) void {
    const x: u32 = @intCast(u32, v & 0xffffffff);
    std.io.printInt(@intCast(i32, x & 0x7fffffff));
}

fn checkByte(label: []const u8, got: u8, want: u8) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write(" got=");
    printU(@intCast(usize, got));
    std.io.write(" want=");
    printU(@intCast(usize, want));
    std.io.write("\n");
}

fn checkWord(label: []const u8, got: u16, want: u16) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write(" got=");
    printU(@intCast(usize, got));
    std.io.write(" want=");
    printU(@intCast(usize, want));
    std.io.write("\n");
}

fn checkBool(label: []const u8, got: bool, want: bool) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write("\n");
}

fn reset() void {
    cartmod.cartInit(&g_cart);
    mmumod.busInit(&g_bus, &g_cart);
    cpumod.cpuInit(&g_cpu);
}

fn tick(n: u32) void {
    timermod.timerTick(&g_bus.timer, n);
}

fn tWrite(addr: u16, value: u8) void {
    timermod.timerWrite(&g_bus.timer, addr, value);
}

fn tRead(addr: u16) u8 {
    return timermod.timerRead(&g_bus.timer, addr);
}

fn testDiv() void {
    reset();
    checkByte("div initial", tRead(0xFF04), 0x00);
    tick(255);
    checkByte("div before edge", tRead(0xFF04), 0x00);
    tick(1);
    checkByte("div 256 cycles", tRead(0xFF04), 0x01);

    reset();
    tick(0x1234);
    checkByte("div high byte", tRead(0xFF04), 0x12);
    tWrite(0xFF04, 0x55);
    checkByte("div write resets", tRead(0xFF04), 0x00);
    tick(1);
    checkByte("div low byte cleared", tRead(0xFF04), 0x00);
    tick(255);
    checkByte("div low byte reset full", tRead(0xFF04), 0x01);
}

fn testDivWriteGlitch() void {
    reset();
    tWrite(0xFF07, 0x00);
    tick(0x80);
    checkByte("div glitch tima before", tRead(0xFF05), 0x00);
    tWrite(0xFF05, 0x00);
    tWrite(0xFF07, 0x07);
    checkByte("div glitch enable rising", tRead(0xFF05), 0x00);
    tWrite(0xFF04, 0x00);
    checkByte("div write falling tick", tRead(0xFF05), 0x01);
    checkByte("div write zero divider", tRead(0xFF04), 0x00);
}

fn testTacRates() void {
    reset();
    tWrite(0xFF07, 0x04);
    tick(1023);
    checkByte("tac 4096 before", tRead(0xFF05), 0x00);
    tick(1);
    checkByte("tac 4096 edge", tRead(0xFF05), 0x01);

    reset();
    tWrite(0xFF07, 0x05);
    tick(15);
    checkByte("tac 262144 before", tRead(0xFF05), 0x00);
    tick(1);
    checkByte("tac 262144 edge", tRead(0xFF05), 0x01);

    reset();
    tWrite(0xFF07, 0x06);
    tick(63);
    checkByte("tac 65536 before", tRead(0xFF05), 0x00);
    tick(1);
    checkByte("tac 65536 edge", tRead(0xFF05), 0x01);

    reset();
    tWrite(0xFF07, 0x07);
    tick(255);
    checkByte("tac 16384 before", tRead(0xFF05), 0x00);
    tick(1);
    checkByte("tac 16384 edge", tRead(0xFF05), 0x01);
}

fn testTacGlitch() void {
    reset();
    tWrite(0xFF07, 0x00);
    tick(0x80);
    tWrite(0xFF05, 0x00);
    tWrite(0xFF07, 0x07);
    checkByte("tac select rising", tRead(0xFF05), 0x00);
    tWrite(0xFF07, 0x05);
    checkByte("tac select falling tick", tRead(0xFF05), 0x01);

    reset();
    tWrite(0xFF07, 0x00);
    tick(0x80);
    tWrite(0xFF05, 0x00);
    tWrite(0xFF07, 0x07);
    tWrite(0xFF07, 0x03);
    checkByte("tac disable falling tick", tRead(0xFF05), 0x01);
}

fn testOverflow() void {
    reset();
    tWrite(0xFF07, 0x00);
    tWrite(0xFF04, 0x00);
    tWrite(0xFF06, 0x42);
    tWrite(0xFF05, 0xFF);
    g_bus.io[0x0F] = 0x00;
    tWrite(0xFF07, 0x06);
    tick(63);
    checkByte("overflow tima ff", tRead(0xFF05), 0xFF);
    checkByte("overflow if quiet before", g_bus.io[0x0F] & 0x04, 0x00);
    tick(1);
    checkByte("overflow holds zero", tRead(0xFF05), 0x00);
    checkByte("overflow if delayed", g_bus.io[0x0F] & 0x04, 0x00);
    tick(15);
    checkByte("overflow holds 4 mcycles", tRead(0xFF05), 0x00);
    checkByte("overflow if still quiet", g_bus.io[0x0F] & 0x04, 0x00);
    tick(1);
    checkByte("overflow reloads tma", tRead(0xFF05), 0x42);
    checkByte("overflow if raised", g_bus.io[0x0F] & 0x04, 0x04);
    checkByte("tma readback", tRead(0xFF06), 0x42);
}

fn testInterruptDispatch() void {
    reset();
    g_cpu.sp = 0xD000;
    g_cpu.pc = CODE;
    g_cpu.ime = true;
    g_bus.ie = 0x04;
    g_bus.io[0x0F] = 0x04;
    const cyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkByte("irq dispatch cycles", @intCast(u8, cyc), 20);
    checkWord("irq dispatch pc", g_cpu.pc, 0x50);
    checkWord("irq dispatch sp", g_cpu.sp, 0xCFFE);
    checkBool("irq dispatch ime", g_cpu.ime, false);
    checkByte("irq dispatch if", g_bus.io[0x0F], 0x00);
    checkWord("irq dispatch pushed pc", mmumod.read16(&g_bus, 0xCFFE), CODE);

    reset();
    g_cpu.sp = 0xD000;
    g_cpu.pc = CODE;
    g_cpu.ime = true;
    g_bus.ie = 0x0C;
    g_bus.io[0x0F] = 0x0C;
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    checkWord("irq priority pc", g_cpu.pc, 0x50);
    checkByte("irq priority if", g_bus.io[0x0F], 0x08);
}

fn testEiDelay() void {
    reset();
    g_cpu.sp = 0xD000;
    g_cpu.pc = CODE;
    g_cpu.ime = false;
    g_bus.ie = 0x04;
    g_bus.io[0x0F] = 0x04;
    mmumod.write8(&g_bus, CODE, 0xFB);
    mmumod.write8(&g_bus, CODE + 1, 0x00);
    mmumod.write8(&g_bus, CODE + 2, 0x00);
    const c1: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkByte("ei cycles", @intCast(u8, c1), 4);
    checkBool("ei not immediate", g_cpu.ime, false);
    checkWord("ei pc", g_cpu.pc, CODE + 1);
    const c2: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkByte("ei next cycles", @intCast(u8, c2), 4);
    checkBool("ei after next", g_cpu.ime, true);
    checkWord("ei next pc", g_cpu.pc, CODE + 2);
    checkByte("ei pending if kept", g_bus.io[0x0F], 0x04);
    const c3: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkByte("ei dispatch cycles", @intCast(u8, c3), 20);
    checkWord("ei dispatch pc", g_cpu.pc, 0x50);
    checkByte("ei dispatch if", g_bus.io[0x0F], 0x00);
    checkWord("ei dispatch pushed pc", mmumod.read16(&g_bus, 0xCFFE), CODE + 2);
}

fn testDiCancel() void {
    reset();
    g_cpu.sp = 0xD000;
    g_cpu.pc = CODE;
    g_cpu.ime = false;
    g_bus.ie = 0x04;
    g_bus.io[0x0F] = 0x04;
    mmumod.write8(&g_bus, CODE, 0xFB);
    mmumod.write8(&g_bus, CODE + 1, 0xF3);
    mmumod.write8(&g_bus, CODE + 2, 0x00);
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    checkBool("di ei armed", g_cpu.ime, false);
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    checkBool("di cancels ime", g_cpu.ime, false);
    checkByte("di cancels delay", g_cpu.ei_delay, 0);
    checkWord("di pc", g_cpu.pc, CODE + 2);
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    checkBool("di no dispatch", g_cpu.ime, false);
    checkWord("di nop pc", g_cpu.pc, CODE + 3);
    checkByte("di keeps if", g_bus.io[0x0F], 0x04);
}

fn testReti() void {
    reset();
    g_cpu.sp = 0xD000;
    g_cpu.pc = CODE;
    g_cpu.ime = false;
    mmumod.write8(&g_bus, CODE, 0xD9);
    mmumod.write16(&g_bus, 0xD000, 0x1234);
    const cyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkWord("reti pc", g_cpu.pc, 0x1234);
    checkWord("reti sp", g_cpu.sp, 0xD002);
    checkBool("reti ime", g_cpu.ime, true);
    checkByte("reti cycles", @intCast(u8, cyc), 16);
}

fn testHaltBug() void {
    reset();
    g_cpu.sp = 0xD000;
    g_cpu.pc = CODE;
    g_cpu.ime = false;
    g_cpu.b = 0;
    g_bus.ie = 0x04;
    g_bus.io[0x0F] = 0x04;
    mmumod.write8(&g_bus, CODE, 0x76);
    mmumod.write8(&g_bus, CODE + 1, 0x04);
    mmumod.write8(&g_bus, CODE + 2, 0x00);
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    checkBool("halt bug not halted", g_cpu.halted, false);
    checkBool("halt bug armed", g_cpu.halt_bug, true);
    checkWord("halt bug pc", g_cpu.pc, CODE + 1);
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    checkByte("halt bug first inc", g_cpu.b, 0x01);
    checkWord("halt bug first pc", g_cpu.pc, CODE + 1);
    checkBool("halt bug cleared", g_cpu.halt_bug, false);
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    checkByte("halt bug double inc", g_cpu.b, 0x02);
    checkWord("halt bug second pc", g_cpu.pc, CODE + 2);
}

fn testHaltWake() void {
    reset();
    g_cpu.pc = CODE;
    g_cpu.ime = false;
    g_cpu.b = 0;
    g_bus.ie = 0x00;
    g_bus.io[0x0F] = 0x00;
    mmumod.write8(&g_bus, CODE, 0x76);
    mmumod.write8(&g_bus, CODE + 1, 0x04);
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    checkBool("halt enters halt", g_cpu.halted, true);
    checkBool("halt no bug", g_cpu.halt_bug, false);
    g_bus.ie = 0x04;
    g_bus.io[0x0F] = 0x04;
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    checkBool("halt wakes", g_cpu.halted, false);
    checkByte("halt wake inc", g_cpu.b, 0x01);
    checkWord("halt wake pc", g_cpu.pc, CODE + 2);
}

fn testSerial() void {
    reset();
    mmumod.write8(&g_bus, 0xFF01, 0x48);
    checkByte("serial sb readback", mmumod.read8(&g_bus, 0xFF01), 0x48);
    mmumod.write8(&g_bus, 0xFF02, 0x81);
    checkByte("serial sc clear", mmumod.read8(&g_bus, 0xFF02), 0x01);
    checkByte("serial irq quiet", g_bus.io[0x0F] & 0x08, 0x00);
    mmumod.busTick(&g_bus, 7);
    checkByte("serial irq not early", g_bus.io[0x0F] & 0x08, 0x00);
    mmumod.busTick(&g_bus, 1);
    checkByte("serial irq raised", g_bus.io[0x0F] & 0x08, 0x08);
    var buf: [8]u8 = undefined;
    const n: usize = serialmod.serialTake(&g_bus.serial, buf[0..]);
    checkByte("serial take count", @intCast(u8, n), 0x01);
    checkByte("serial take byte", buf[0], 0x48);
    const n2: usize = serialmod.serialTake(&g_bus.serial, buf[0..]);
    checkByte("serial take drains", @intCast(u8, n2), 0x00);
}

fn testPostBoot() void {
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = false, .serial_log = false, .turbo = false, .dynarec = false });
    emumod.emuReset(&g_emu);
    checkByte("postboot a", g_emu.cpu.a, 0x01);
    checkByte("postboot f", g_emu.cpu.f, 0xB0);
    checkByte("postboot b", g_emu.cpu.b, 0x00);
    checkByte("postboot c", g_emu.cpu.c, 0x13);
    checkByte("postboot d", g_emu.cpu.d, 0x00);
    checkByte("postboot e", g_emu.cpu.e, 0xD8);
    checkByte("postboot h", g_emu.cpu.h, 0x01);
    checkByte("postboot l", g_emu.cpu.l, 0x4D);
    checkWord("postboot sp", g_emu.cpu.sp, 0xFFFE);
    checkWord("postboot pc", g_emu.cpu.pc, 0x0100);
    checkBool("postboot ime", g_emu.cpu.ime, false);
    checkBool("postboot halted", g_emu.cpu.halted, false);
    checkByte("postboot ff00", mmumod.read8(&g_emu.bus, 0xFF00), 0xCF);
    checkByte("postboot ff0f", mmumod.read8(&g_emu.bus, 0xFF0F), 0xE1);
    checkByte("postboot ff40", mmumod.read8(&g_emu.bus, 0xFF40), 0x91);
    checkByte("postboot ff47", mmumod.read8(&g_emu.bus, 0xFF47), 0xFC);
    checkByte("postboot ff48", mmumod.read8(&g_emu.bus, 0xFF48), 0xFF);
    checkByte("postboot ff49", mmumod.read8(&g_emu.bus, 0xFF49), 0xFF);
    checkByte("postboot ff4a", mmumod.read8(&g_emu.bus, 0xFF4A), 0x00);
    checkByte("postboot ff4b", mmumod.read8(&g_emu.bus, 0xFF4B), 0x00);
    checkByte("postboot ly", mmumod.read8(&g_emu.bus, 0xFF44), 0x91);
    checkByte("postboot ie", mmumod.read8(&g_emu.bus, 0xFFFF), 0x00);
}

pub fn main() void {
    testDiv();
    testDivWriteGlitch();
    testTacRates();
    testTacGlitch();
    testOverflow();
    testInterruptDispatch();
    testEiDelay();
    testDiCancel();
    testReti();
    testHaltBug();
    testHaltWake();
    testSerial();
    testPostBoot();

    std.io.write("timer ");
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

cat >"$OUT/ppu_test.zig" <<'ZIG'
const std = @import("std");
const cartmod = @import("z9gb/cart.zig");
const mmumod = @import("z9gb/mmu.zig");
const ppumod = @import("z9gb/ppu.zig");
const emumod = @import("z9gb/emu.zig");

var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_ppu: ppumod.Ppu = undefined;
var g_emu: emumod.Emu = undefined;
var g_pass: u32 = 0;
var g_fail: u32 = 0;

fn printU(v: usize) void {
    const x: u32 = @intCast(u32, v & 0xffffffff);
    std.io.printInt(@intCast(i32, x & 0x7fffffff));
}

fn checkByte(label: []const u8, got: u8, want: u8) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write(" got=");
    printU(@intCast(usize, got));
    std.io.write(" want=");
    printU(@intCast(usize, want));
    std.io.write("\n");
}

fn checkWord(label: []const u8, got: u16, want: u16) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write(" got=");
    printU(@intCast(usize, got));
    std.io.write(" want=");
    printU(@intCast(usize, want));
    std.io.write("\n");
}

fn checkU32(label: []const u8, got: u32, want: u32) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write(" got=");
    printU(@intCast(usize, got));
    std.io.write(" want=");
    printU(@intCast(usize, want));
    std.io.write("\n");
}

fn checkFrame(label: []const u8, x: usize, y: usize, want: u32) void {
    checkU32(label, g_ppu.fb[y * ppumod.SCREEN_W + x], want);
}

fn reset() void {
    cartmod.cartInit(&g_cart);
    mmumod.busInit(&g_bus, &g_cart);
    ppumod.ppuReset(&g_ppu);
    g_bus.io[0x0F] = 0;
}

fn writeReg(addr: u16, value: u8) void {
    ppumod.ppuWrite(&g_ppu, addr, value);
}

fn tick(n: u32) void {
    ppumod.ppuTick(&g_ppu, n, &g_bus);
}

fn fillTile(tile: u8, lo: u8, hi: u8) void {
    var row: usize = 0;
    while (row < 8) : (row += 1) {
        const a: usize = @intCast(usize, tile) * 16 + row * 2;
        g_bus.vram[a] = lo;
        g_bus.vram[a + 1] = hi;
    }
}

fn setOam(index: usize, y: u8, x: u8, tile: u8, attr: u8) void {
    const o: usize = index * 4;
    g_bus.oam[o] = y;
    g_bus.oam[o + 1] = x;
    g_bus.oam[o + 2] = tile;
    g_bus.oam[o + 3] = attr;
}

fn testModeSequence() void {
    reset();
    checkByte("ppu initial mode", g_ppu.mode, 2);
    checkByte("ppu initial ly", g_ppu.ly, 0);
    tick(79);
    checkByte("ppu mode2 at 79", g_ppu.mode, 2);
    tick(1);
    checkByte("ppu mode3 at 80", g_ppu.mode, 3);
    checkWord("ppu mode3 base length", @intCast(u16, g_ppu.mode3_len), 172);
    tick(g_ppu.mode3_len);
    checkByte("ppu mode0 after mode3", g_ppu.mode, 0);
    const rest: u32 = 456 - 80 - g_ppu.mode3_len;
    tick(rest);
    checkByte("ppu next line ly", g_ppu.ly, 1);
    checkByte("ppu next line mode2", g_ppu.mode, 2);
    tick(143 * 456);
    checkByte("ppu vblank ly", g_ppu.ly, 144);
    checkByte("ppu vblank mode1", g_ppu.mode, 1);
    tick(10 * 456);
    checkByte("ppu frame wrap ly", g_ppu.ly, 0);
    checkByte("ppu frame wrap mode2", g_ppu.mode, 2);

    reset();
    writeReg(0xFF43, 5);
    tick(80);
    checkWord("ppu mode3 scx penalty", @intCast(u16, g_ppu.mode3_len), 177);

    reset();
    writeReg(0xFF40, 0x93);
    setOam(0, 16, 0, 0, 0);
    tick(80);
    checkWord("ppu mode3 obj x0 penalty", @intCast(u16, g_ppu.mode3_len), 183);
}

fn testStatInterrupts() void {
    reset();
    writeReg(0xFF41, 0x08);
    tick(80);
    tick(g_ppu.mode3_len);
    checkByte("ppu stat mode0 irq", g_bus.io[0x0F] & 0x02, 0x02);

    reset();
    writeReg(0xFF41, 0x10);
    g_ppu.line = 143;
    g_ppu.ly = 143;
    g_ppu.dot = 450;
    g_ppu.mode = 0;
    tick(6);
    checkByte("ppu stat mode1 ly", g_ppu.ly, 144);
    checkByte("ppu stat mode1 irq", g_bus.io[0x0F] & 0x02, 0x02);

    reset();
    writeReg(0xFF41, 0x40);
    writeReg(0xFF45, 1);
    tick(456);
    checkByte("ppu lyc coincidence", ppumod.ppuRead(&g_ppu, 0xFF41) & 0x04, 0x04);
    checkByte("ppu lyc stat irq", g_bus.io[0x0F] & 0x02, 0x02);
}

fn testBackground() void {
    reset();
    writeReg(0xFF40, 0x91);
    writeReg(0xFF47, 0xE4);
    writeReg(0xFF42, 0);
    writeReg(0xFF43, 0);
    fillTile(1, 0xFF, 0xFF);
    fillTile(2, 0xFF, 0x00);
    fillTile(0x80, 0x00, 0xFF);
    g_bus.vram[0x1800] = 1;
    g_bus.vram[0x1801] = 2;
    g_bus.vram[0x1802] = 0x80;
    tick(80);
    checkFrame("ppu bg tile1 color3", 0, 0, 0x000F380F);
    checkFrame("ppu bg tile2 color1", 8, 0, 0x008BAC0F);
    checkFrame("ppu bg signed tile color2", 16, 0, 0x00306230);
}

fn testWindow() void {
    reset();
    writeReg(0xFF40, 0xF1);
    writeReg(0xFF47, 0xE4);
    writeReg(0xFF4A, 0);
    writeReg(0xFF4B, 0);
    fillTile(0, 0x00, 0xFF);
    g_bus.vram[0x1C00] = 0;
    tick(80);
    checkWord("ppu window mode3 penalty", @intCast(u16, g_ppu.mode3_len), 178);
    checkFrame("ppu window pixel0", 0, 0, 0x00306230);
    checkFrame("ppu window pixel159", 159, 0, 0x00306230);
    checkByte("ppu window line counter", g_ppu.window_line, 1);

    reset();
    writeReg(0xFF40, 0xF1);
    writeReg(0xFF47, 0xE4);
    writeReg(0xFF4A, 0);
    writeReg(0xFF4B, 15);
    fillTile(1, 0x00, 0xFF);
    g_bus.vram[0x1C00] = 1;
    tick(80);
    checkFrame("ppu window left edge bg", 7, 0, 0x009BBC0F);
    checkFrame("ppu window left edge win", 8, 0, 0x00306230);
}

fn testSprite8x8() void {
    reset();
    writeReg(0xFF40, 0x93);
    writeReg(0xFF47, 0xE4);
    writeReg(0xFF48, 0xE4);
    fillTile(0, 0xFF, 0x00);
    fillTile(1, 0xFF, 0xFF);
    g_bus.vram[0x1800] = 1;
    g_bus.vram[0x1801] = 1;
    setOam(0, 16, 8, 0, 0);
    tick(80);
    checkFrame("ppu sprite 8x8 pixel0", 0, 0, 0x008BAC0F);
    checkFrame("ppu sprite 8x8 bg pixel8", 8, 0, 0x000F380F);
}

fn spriteRomSetup(lcdc: u8) void {
    reset();
    writeReg(0xFF40, lcdc);
    writeReg(0xFF47, 0xE4);
    writeReg(0xFF48, 0xE4);
    fillTile(0, 0xFF, 0x00);
    fillTile(1, 0x00, 0xFF);
    fillTile(2, 0x00, 0xFF);
    fillTile(3, 0xFF, 0x00);
}

fn testSprite8x16() void {
    spriteRomSetup(0x97);
    setOam(0, 16, 8, 2, 0);
    tick(80);
    checkFrame("ppu sprite 8x16 top tile", 0, 0, 0x00306230);

    spriteRomSetup(0x97);
    setOam(0, 16, 8, 2, 0);
    tick(8 * 456);
    tick(80);
    checkByte("ppu sprite 8x16 line8", g_ppu.ly, 8);
    checkFrame("ppu sprite 8x16 bottom tile", 0, 8, 0x008BAC0F);
}

fn testSpritePriority() void {
    spriteRomSetup(0x93);
    g_bus.vram[0x1800] = 0;
    setOam(0, 16, 8, 0, 0);
    setOam(1, 16, 8, 2, 0);
    tick(80);
    checkFrame("ppu sprite same x oam index", 0, 0, 0x008BAC0F);

    spriteRomSetup(0x93);
    g_bus.vram[0x1800] = 0;
    setOam(0, 16, 9, 2, 0);
    setOam(1, 16, 8, 0, 0);
    tick(80);
    checkFrame("ppu sprite x priority", 1, 0, 0x008BAC0F);

    spriteRomSetup(0x93);
    g_bus.vram[0x1800] = 1;
    setOam(0, 16, 8, 0, 0x80);
    tick(80);
    checkFrame("ppu sprite behind bg", 0, 0, 0x00306230);

    spriteRomSetup(0x93);
    g_bus.vram[0x1800] = 0;
    setOam(0, 16, 8, 0, 0x80);
    tick(80);
    checkFrame("ppu sprite over bg zero", 0, 0, 0x008BAC0F);
}

fn testPalette() void {
    reset();
    writeReg(0xFF40, 0x91);
    writeReg(0xFF47, 0x1B);
    fillTile(1, 0xFF, 0x00);
    g_bus.vram[0x1800] = 1;
    tick(80);
    checkFrame("ppu bgp remap", 0, 0, 0x00306230);
    writeReg(0xFF47, 0xE4);
    tick(456 - 80);
    tick(80);
    checkFrame("ppu bgp recompute", 0, 1, 0x008BAC0F);

    spriteRomSetup(0x93);
    g_bus.vram[0x1800] = 0;
    writeReg(0xFF48, 0x1B);
    setOam(0, 16, 8, 0, 0);
    tick(80);
    checkFrame("ppu obp remap", 0, 0, 0x00306230);
}

fn testEmuFramebuffer() void {
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = false, .serial_log = false, .turbo = false, .dynarec = false });
    const fb: []const u32 = emumod.emuFramebuffer(&g_emu);
    checkWord("ppu emu framebuffer length", @intCast(u16, fb.len), 23040);
    const pfb: []const u32 = ppumod.ppuFramebuffer(&g_ppu);
    checkWord("ppu framebuffer length", @intCast(u16, pfb.len), 23040);
}

pub fn main() void {
    testModeSequence();
    testStatInterrupts();
    testBackground();
    testWindow();
    testSprite8x8();
    testSprite8x16();
    testSpritePriority();
    testPalette();
    testEmuFramebuffer();

    std.io.write("ppu ");
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

ROM="$Z9DIR/testdata/synth/minimal.gb"
EXPECT="cart ok mbc=0 rom=32768 ram=0"

run_cart_mode() {
    mode="$1"
    flag="$2"
    bin="$OUT/$mode/cart_test"
    mkdir -p "$OUT/$mode"
    if timeout 120 "$ZIG" "$flag" -o "$OUT/$mode" "$OUT/cart_test.zig" >"$OUT/$mode/zig.log" 2>&1; then
        pass_case "cart $mode emits"
    else
        fail_case "cart $mode emits"
        tail -20 "$OUT/$mode/zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$OUT/$mode/build_target.sh" linux "$bin" >"$OUT/$mode/build.log" 2>&1; then
        pass_case "cart $mode links"
    else
        fail_case "cart $mode links"
        tail -20 "$OUT/$mode/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 60 "$bin" "$ROM" >"$OUT/$mode/run.out" 2>"$OUT/$mode/run.err"; then
        pass_case "cart $mode runs"
    else
        fail_case "cart $mode runs"
        tail -20 "$OUT/$mode/run.err" | sed 's/^/       /'
        return
    fi
    if grep -qxF "$EXPECT" "$OUT/$mode/run.out"; then
        pass_case "cart $mode output ($EXPECT)"
    else
        fail_case "cart $mode output (want $EXPECT, got $(cat "$OUT/$mode/run.out"))"
    fi
}

run_cpu_mode() {
    mode="$1"
    flag="$2"
    bin="$OUT/$mode/cpu_test"
    mkdir -p "$OUT/$mode"
    if timeout 120 "$ZIG" "$flag" -o "$OUT/$mode" "$Z9DIR/tests/cpu_test.zig" >"$OUT/$mode/zig.log" 2>&1; then
        pass_case "cpu $mode emits"
    else
        fail_case "cpu $mode emits"
        tail -20 "$OUT/$mode/zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$OUT/$mode/build_target.sh" linux "$bin" >"$OUT/$mode/build.log" 2>&1; then
        pass_case "cpu $mode links"
    else
        fail_case "cpu $mode links"
        tail -20 "$OUT/$mode/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 60 "$bin" >"$OUT/$mode/run.out" 2>"$OUT/$mode/run.err"; then
        pass_case "cpu $mode runs"
    else
        fail_case "cpu $mode runs"
        tail -20 "$OUT/$mode/run.err" | sed 's/^/       /'
        return
    fi
    if grep -q '^cpu ok ' "$OUT/$mode/run.out"; then
        pass_case "cpu $mode output ($(cat "$OUT/$mode/run.out"))"
    else
        fail_case "cpu $mode output (got $(cat "$OUT/$mode/run.out"))"
    fi
}

run_timer_mode() {
    mode="$1"
    flag="$2"
    bin="$OUT/$mode/timer_test"
    mkdir -p "$OUT/$mode"
    if timeout 120 "$ZIG" "$flag" -o "$OUT/$mode" "$OUT/timer_test.zig" >"$OUT/$mode/zig.log" 2>&1; then
        pass_case "timer $mode emits"
    else
        fail_case "timer $mode emits"
        tail -20 "$OUT/$mode/zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$OUT/$mode/build_target.sh" linux "$bin" >"$OUT/$mode/build.log" 2>&1; then
        pass_case "timer $mode links"
    else
        fail_case "timer $mode links"
        tail -20 "$OUT/$mode/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 60 "$bin" >"$OUT/$mode/run.out" 2>"$OUT/$mode/run.err"; then
        pass_case "timer $mode runs"
    else
        fail_case "timer $mode runs"
        tail -20 "$OUT/$mode/run.err" | sed 's/^/       /'
        return
    fi
    if grep -q '^timer ok ' "$OUT/$mode/run.out"; then
        pass_case "timer $mode output ($(cat "$OUT/$mode/run.out"))"
    else
        fail_case "timer $mode output (got $(cat "$OUT/$mode/run.out"))"
    fi
}

run_ppu_mode() {
    mode="$1"
    flag="$2"
    bin="$OUT/$mode/ppu_test"
    mkdir -p "$OUT/$mode"
    if timeout 120 "$ZIG" "$flag" -o "$OUT/$mode" "$OUT/ppu_test.zig" >"$OUT/$mode/zig.log" 2>&1; then
        pass_case "ppu $mode emits"
    else
        fail_case "ppu $mode emits"
        tail -20 "$OUT/$mode/zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$OUT/$mode/build_target.sh" linux "$bin" >"$OUT/$mode/build.log" 2>&1; then
        pass_case "ppu $mode links"
    else
        fail_case "ppu $mode links"
        tail -20 "$OUT/$mode/build.log" | sed 's/^/       /'
        return
    fi
    if timeout 60 "$bin" >"$OUT/$mode/run.out" 2>"$OUT/$mode/run.err"; then
        pass_case "ppu $mode runs"
    else
        fail_case "ppu $mode runs"
        tail -20 "$OUT/$mode/run.err" | sed 's/^/       /'
        return
    fi
    if grep -q '^ppu ok ' "$OUT/$mode/run.out"; then
        pass_case "ppu $mode output ($(cat "$OUT/$mode/run.out"))"
    else
        fail_case "ppu $mode output (got $(cat "$OUT/$mode/run.out"))"
    fi
}

cd "$ROOT" || exit 1

if [ "$RUN_CART" -eq 1 ]; then
    echo "== cartridge header + MBC1 =="
    if [ -f "$ROM" ]; then
        size="$(stat -c %s "$ROM")"
        if [ "$size" = "32768" ]; then
            pass_case "minimal.gb is 32768 bytes"
        else
            fail_case "minimal.gb is 32768 bytes (got $size)"
        fi
    else
        fail_case "minimal.gb exists"
    fi
    run_cart_mode fast -ffast
    run_cart_mode safe -fsafe
fi

if [ "$RUN_CPU" -eq 1 ]; then
    echo
    echo "== SM83 ALU, flags, DAA =="
    run_cpu_mode fast -ffast
    run_cpu_mode safe -fsafe
fi

if [ "$RUN_TIMER" -eq 1 ]; then
    echo
    echo "== timer, interrupts, HALT, serial, post-boot =="
    run_timer_mode fast -ffast
    run_timer_mode safe -fsafe
fi

if [ "$RUN_PPU" -eq 1 ]; then
    echo
    echo "== DMG scanline PPU: modes, STAT/LYC, BG/window, sprites, palettes =="
    run_ppu_mode fast -ffast
    run_ppu_mode safe -fsafe
fi

echo
echo "== tier_dmg summary: $PASSES passed, $FAILS failed =="
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_DMG FAIL"
    exit 1
fi
echo "TIER_DMG PASS"
exit 0
