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
RUN_GATES=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --only)
            shift
            if [ "$#" -eq 0 ]; then
                echo "usage: tier_dmg.sh <zig> [--only cart|cpu|timer|ppu|save] [--all] [--gates]" >&2
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
        --gates)
            RUN_GATES=1
            ;;
        *)
            echo "usage: tier_dmg.sh <zig> [--only cart|cpu|timer|ppu|save] [--all] [--gates]" >&2
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
RUN_SAVE=0
if [ -z "$ONLY" ]; then
    RUN_CART=1
    RUN_CPU=1
    RUN_TIMER=1
    RUN_PPU=1
    RUN_SAVE=1
elif [ "$ONLY" = "cart" ]; then
    RUN_CART=1
elif [ "$ONLY" = "cpu" ]; then
    RUN_CPU=1
elif [ "$ONLY" = "timer" ]; then
    RUN_TIMER=1
elif [ "$ONLY" = "ppu" ]; then
    RUN_PPU=1
elif [ "$ONLY" = "save" ]; then
    RUN_SAVE=1
else
    echo "unknown tier: $ONLY" >&2
    exit 2
fi

if [ "$RUN_GATES" -eq 1 ]; then
    RUN_CART=0
    RUN_CPU=0
    RUN_TIMER=0
    RUN_PPU=0
    RUN_SAVE=0
fi

PASSES=0
FAILS=0
SKIPS=0
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
    timermod.timerTick(&g_bus.timer, n, &g_bus);
}

fn tWrite(addr: u16, value: u8) void {
    timermod.timerWrite(&g_bus.timer, addr, value, &g_bus);
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
    tick(3);
    checkByte("overflow holds 1 mcycle", tRead(0xFF05), 0x00);
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

fn testIrqRouting() void {
    reset();
    g_bus.io[0x0F] = 0;
    mmumod.busRaiseIrq(&g_bus, 0x04);
    checkByte("busRaiseIrq timer", g_bus.io[0x0F] & 0x04, 0x04);
    mmumod.busRaiseIrq(&g_bus, 0x08);
    checkByte("busRaiseIrq or serial", g_bus.io[0x0F] & 0x0C, 0x0C);

    reset();
    g_bus.io[0x0F] = 0;
    serialmod.serialWrite(&g_bus.serial, 0xFF01, 0x41, &g_bus);
    serialmod.serialWrite(&g_bus.serial, 0xFF02, 0x81, &g_bus);
    serialmod.serialTick(&g_bus.serial, 7, &g_bus);
    checkByte("serial routing quiet", g_bus.io[0x0F] & 0x08, 0x00);
    serialmod.serialTick(&g_bus.serial, 1, &g_bus);
    checkByte("serial routing irq", g_bus.io[0x0F] & 0x08, 0x08);

    reset();
    g_bus.io[0x0F] = 0;
    g_bus.timer.tima = 0x00;
    g_bus.timer.tma = 0x42;
    g_bus.timer.reload = 1;
    timermod.timerTick(&g_bus.timer, 1, &g_bus);
    checkByte("timer routing reload", timermod.timerRead(&g_bus.timer, 0xFF05), 0x42);
    checkByte("timer routing irq", g_bus.io[0x0F] & 0x04, 0x04);
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
    testIrqRouting();
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
const cpumod = @import("z9gb/cpu.zig");
const emumod = @import("z9gb/emu.zig");

var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_ppu: ppumod.Ppu = undefined;
var g_emu: emumod.Emu = undefined;
var g_pass: u32 = 0;
var g_fail: u32 = 0;

const TEST_COLORS: [4]u32 = [4]u32{
    0x009BBC0F,
    0x008BAC0F,
    0x00306230,
    0x000F380F,
};

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
    ppumod.ppuWrite(&g_ppu, addr, value, &g_bus);
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

fn fillPatternTile(tile: u8) void {
    fillTile(tile, 0x55, 0x33);
}

fn windowSetup(wx: u8, scx: u8) void {
    reset();
    writeReg(0xFF40, 0xF1);
    writeReg(0xFF47, 0xE4);
    writeReg(0xFF42, 0);
    writeReg(0xFF43, scx);
    writeReg(0xFF4A, 0);
    writeReg(0xFF4B, wx);
    fillPatternTile(0);
    fillTile(1, 0xFF, 0xFF);
    var i: usize = 0;
    while (i < 32) : (i += 1) g_bus.vram[0x1800 + i] = 1;
    g_bus.vram[0x1C00] = 0;
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
    tick(83);
    checkByte("ppu mode2 at 83", g_ppu.mode, 2);
    tick(1);
    checkByte("ppu mode3 at 84", g_ppu.mode, 3);
    checkWord("ppu mode3 base length", @intCast(u16, g_ppu.mode3_len), 172);
    tick(g_ppu.mode3_len);
    checkByte("ppu mode0 after mode3", g_ppu.mode, 0);
    const rest: u32 = 456 - 84 - g_ppu.mode3_len;
    tick(rest);
    checkByte("ppu next line ly", g_ppu.ly, 1);
    tick(4);
    checkByte("ppu next line mode2", g_ppu.mode, 2);
    tick(143 * 456);
    checkByte("ppu vblank ly", g_ppu.ly, 144);
    checkByte("ppu vblank mode1", g_ppu.mode, 1);
    tick(10 * 456);
    checkByte("ppu frame wrap ly", g_ppu.ly, 0);
    checkByte("ppu frame wrap mode2", g_ppu.mode, 2);

    reset();
    writeReg(0xFF43, 5);
    tick(84);
    checkWord("ppu mode3 scx penalty", @intCast(u16, g_ppu.mode3_len), 177);

    reset();
    writeReg(0xFF40, 0x93);
    setOam(0, 16, 0, 0, 0);
    tick(84);
    checkWord("ppu mode3 obj x0 penalty", @intCast(u16, g_ppu.mode3_len), 183);
}

fn testStatInterrupts() void {
    reset();
    writeReg(0xFF41, 0x08);
    tick(84);
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
    tick(5);
    checkByte("ppu lyc coincidence", ppumod.ppuRead(&g_ppu, 0xFF41) & 0x04, 0x04);
    checkByte("ppu lyc stat irq", g_bus.io[0x0F] & 0x02, 0x02);
}

fn testStatLineEdge() void {
    reset();
    tick(84);
    tick(g_ppu.mode3_len);
    checkByte("ppu stat line idle", g_bus.io[0x0F] & 0x02, 0x00);
    writeReg(0xFF41, 0x08);
    checkByte("ppu stat line rising irq", g_bus.io[0x0F] & 0x02, 0x02);

    g_bus.io[0x0F] = 0;
    tick(10);
    checkByte("ppu stat line no refire", g_bus.io[0x0F] & 0x02, 0x00);

    tick(456 - 84 - g_ppu.mode3_len - 10);
    checkByte("ppu stat line cleared", g_bus.io[0x0F] & 0x02, 0x00);

    tick(84);
    tick(g_ppu.mode3_len);
    checkByte("ppu stat line refire", g_bus.io[0x0F] & 0x02, 0x02);
}

fn testModeAccessLocking() void {
    reset();
    writeReg(0xFF40, 0x00);
    writeReg(0xFF40, 0x91);
    g_bus.oam[0] = 0x12;
    g_bus.vram[0] = 0x34;
    checkByte("ppu access oam mode0 read", mmumod.read8(&g_bus, 0xFE00), 0x12);
    checkByte("ppu access vram mode0 read", mmumod.read8(&g_bus, 0x8000), 0x34);
    mmumod.write8(&g_bus, 0xFE00, 0x56);
    mmumod.write8(&g_bus, 0x8000, 0x78);
    checkByte("ppu access oam mode0 write", g_bus.oam[0], 0x56);
    checkByte("ppu access vram mode0 write", g_bus.vram[0], 0x78);

    tick(84);
    checkByte("ppu access first line mode3", g_ppu.mode, 3);
    checkByte("ppu access oam mode3 read", mmumod.read8(&g_bus, 0xFE00), 0xFF);
    checkByte("ppu access vram mode3 read", mmumod.read8(&g_bus, 0x8000), 0xFF);
    mmumod.write8(&g_bus, 0xFE00, 0x9A);
    mmumod.write8(&g_bus, 0x8000, 0xBC);
    checkByte("ppu access oam mode3 write", g_bus.oam[0], 0x56);
    checkByte("ppu access vram mode3 write", g_bus.vram[0], 0x78);

    tick(g_ppu.mode3_len);
    checkByte("ppu access mode0 after mode3", g_ppu.mode, 0);
    checkByte("ppu access oam mode0 restored", mmumod.read8(&g_bus, 0xFE00), 0x56);
    checkByte("ppu access vram mode0 restored", mmumod.read8(&g_bus, 0x8000), 0x78);

    tick(456 - 84 - g_ppu.mode3_len);
    checkByte("ppu access normal line start", g_ppu.ly, 1);
    checkByte("ppu access normal oam early", mmumod.read8(&g_bus, 0xFE00), 0xFF);
    checkByte("ppu access normal vram early", mmumod.read8(&g_bus, 0x8000), 0x78);
    tick(80);
    checkByte("ppu access normal mode2", g_ppu.mode, 2);
    checkByte("ppu access oam mode2 read", mmumod.read8(&g_bus, 0xFE00), 0xFF);
    checkByte("ppu access vram mode2 late read", mmumod.read8(&g_bus, 0x8000), 0xFF);
    tick(256 - 80);
    checkByte("ppu access normal mode0", g_ppu.mode, 0);
    checkByte("ppu access oam normal mode0", mmumod.read8(&g_bus, 0xFE00), 0x56);
    checkByte("ppu access vram normal mode0", mmumod.read8(&g_bus, 0x8000), 0x78);

    reset();
    writeReg(0xFF40, 0x00);
    checkByte("ppu access lcd off oam", mmumod.read8(&g_bus, 0xFE00), 0x00);
    checkByte("ppu access lcd off vram", mmumod.read8(&g_bus, 0x8000), 0x00);
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
    tick(84);
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
    tick(84);
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
    tick(84);
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
    tick(84);
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
    tick(84);
    checkFrame("ppu sprite 8x16 top tile", 0, 0, 0x00306230);

    spriteRomSetup(0x97);
    setOam(0, 16, 8, 2, 0);
    tick(8 * 456);
    tick(84);
    checkByte("ppu sprite 8x16 line8", g_ppu.ly, 8);
    checkFrame("ppu sprite 8x16 bottom tile", 0, 8, 0x008BAC0F);
}

fn testSpritePriority() void {
    spriteRomSetup(0x93);
    g_bus.vram[0x1800] = 0;
    setOam(0, 16, 8, 0, 0);
    setOam(1, 16, 8, 2, 0);
    tick(84);
    checkFrame("ppu sprite same x oam index", 0, 0, 0x008BAC0F);

    spriteRomSetup(0x93);
    g_bus.vram[0x1800] = 0;
    setOam(0, 16, 9, 2, 0);
    setOam(1, 16, 8, 0, 0);
    tick(84);
    checkFrame("ppu sprite x priority", 1, 0, 0x008BAC0F);

    spriteRomSetup(0x93);
    g_bus.vram[0x1800] = 1;
    setOam(0, 16, 8, 0, 0x80);
    tick(84);
    checkFrame("ppu sprite behind bg", 0, 0, 0x00306230);

    spriteRomSetup(0x93);
    g_bus.vram[0x1800] = 0;
    setOam(0, 16, 8, 0, 0x80);
    tick(84);
    checkFrame("ppu sprite over bg zero", 0, 0, 0x008BAC0F);
}

fn testPalette() void {
    reset();
    writeReg(0xFF40, 0x91);
    writeReg(0xFF47, 0x1B);
    fillTile(1, 0xFF, 0x00);
    g_bus.vram[0x1800] = 1;
    tick(84);
    checkFrame("ppu bgp remap", 0, 0, 0x00306230);
    writeReg(0xFF47, 0xE4);
    tick(456 - 84);
    tick(84);
    checkFrame("ppu bgp recompute", 0, 1, 0x008BAC0F);

    spriteRomSetup(0x93);
    g_bus.vram[0x1800] = 0;
    writeReg(0xFF48, 0x1B);
    setOam(0, 16, 8, 0, 0);
    tick(84);
    checkFrame("ppu obp remap", 0, 0, 0x00306230);
}

fn testWindowClipping() void {
    windowSetup(0, 3);
    tick(84);
    checkByte("ppu window wx0 start", g_ppu.win_start_x, 0);
    checkByte("ppu window wx0 skip", g_ppu.win_skip, 3);
    checkByte("ppu window wx0 len", g_ppu.win_visible_len, 160);
    checkFrame("ppu window wx0 scx shift pixel0", 0, 0, TEST_COLORS[3]);
    checkFrame("ppu window wx0 scx shift pixel1", 1, 0, TEST_COLORS[0]);

    var wx: u8 = 1;
    while (wx <= 6) : (wx += 1) {
        windowSetup(wx, 0);
        tick(84);
        checkByte("ppu window wx1..6 skip", g_ppu.win_skip, @intCast(u8, 7 - wx));
        const idx: u8 = @intCast(u8, g_ppu.win_skip & 3);
        checkFrame("ppu window wx1..6 first", 0, 0, TEST_COLORS[@intCast(usize, idx)]);
        const idx2: u8 = @intCast(u8, (g_ppu.win_skip + 1) & 3);
        checkFrame("ppu window wx1..6 second", 1, 0, TEST_COLORS[@intCast(usize, idx2)]);
    }

    windowSetup(7, 0);
    tick(84);
    checkByte("ppu window wx7 start", g_ppu.win_start_x, 0);
    checkByte("ppu window wx7 skip", g_ppu.win_skip, 0);
    checkFrame("ppu window wx7 pixel0", 0, 0, TEST_COLORS[0]);

    windowSetup(166, 0);
    tick(84);
    checkByte("ppu window wx166 start", g_ppu.win_start_x, 159);
    checkByte("ppu window wx166 len", g_ppu.win_visible_len, 1);
    checkFrame("ppu window wx166 bg", 158, 0, TEST_COLORS[3]);
    checkFrame("ppu window wx166 win", 159, 0, TEST_COLORS[0]);

    windowSetup(167, 0);
    tick(84);
    checkByte("ppu window wx167 disabled", g_ppu.win_visible_len, 0);
    checkFrame("ppu window wx167 bg", 0, 0, TEST_COLORS[3]);
    checkByte("ppu window wx167 counter", g_ppu.window_line, 0);
}

fn testMode3Tiles() void {
    reset();
    writeReg(0xFF40, 0x93);
    setOam(0, 16, 8, 0, 0);
    setOam(1, 16, 9, 0, 0);
    tick(84);
    checkWord("ppu mode3 same tile", @intCast(u16, g_ppu.mode3_len), 183);

    reset();
    writeReg(0xFF40, 0x93);
    setOam(0, 16, 8, 0, 0);
    setOam(1, 16, 16, 0, 0);
    tick(84);
    checkWord("ppu mode3 distinct tiles", @intCast(u16, g_ppu.mode3_len), 194);

    reset();
    writeReg(0xFF40, 0x93);
    setOam(0, 16, 0, 0, 0);
    tick(84);
    checkWord("ppu mode3 x0 capped", @intCast(u16, g_ppu.mode3_len), 183);
}

fn testLycWriteAndLcd() void {
    reset();
    writeReg(0xFF41, 0x40);
    g_bus.io[0x0F] = 0;
    writeReg(0xFF45, 0);
    checkByte("ppu lyc write coincidence", ppumod.ppuRead(&g_ppu, 0xFF41) & 0x04, 0x04);
    checkByte("ppu lyc write irq", g_bus.io[0x0F] & 0x02, 0x02);

    g_bus.io[0x0F] = 0;
    writeReg(0xFF45, 7);
    checkByte("ppu lyc write mismatch quiet", g_bus.io[0x0F] & 0x02, 0x00);

    reset();
    writeReg(0xFF40, 0x00);
    checkByte("ppu lcd off mode", g_ppu.mode, 0);
    checkByte("ppu lcd off ly", g_ppu.ly, 0);
    g_ppu.dot = 99;
    g_ppu.line = 42;
    writeReg(0xFF40, 0x91);
    checkByte("ppu lcd reenable mode", g_ppu.mode, 0);
    checkByte("ppu lcd reenable line", g_ppu.line, 0);
    checkByte("ppu lcd reenable dot", @intCast(u8, g_ppu.dot), 0);
    checkByte("ppu lcd reenable ly", g_ppu.ly, 0);
    tick(84);
    checkByte("ppu lcd reenable straight to mode3", g_ppu.mode, 3);

    reset();
    writeReg(0xFF41, 0x20);
    writeReg(0xFF40, 0x00);
    g_bus.io[0x0F] = 0;
    writeReg(0xFF40, 0x91);
    checkByte("ppu lcd reenable mode2 irq quiet", g_bus.io[0x0F] & 0x02, 0x00);
}

fn testLcdOffLycFrozen() void {
    reset();
    writeReg(0xFF41, 0x40);
    writeReg(0xFF45, 1);
    tick(456);
    tick(4);
    checkByte("ppu lcd off setup coincidence", ppumod.ppuRead(&g_ppu, 0xFF41) & 0x04, 0x04);

    g_bus.io[0x0F] = 0;
    writeReg(0xFF40, 0x00);
    checkByte("ppu lcd off no spurious irq", g_bus.io[0x0F] & 0x02, 0x00);
    checkByte("ppu lcd off ly", g_ppu.ly, 0);
    checkByte("ppu lcd off lyc frozen", ppumod.ppuRead(&g_ppu, 0xFF41) & 0x04, 0x04);

    g_bus.io[0x0F] = 0;
    writeReg(0xFF45, 0);
    checkByte("ppu lcd off lyc write quiet", g_bus.io[0x0F] & 0x02, 0x00);
    tick(456);
    checkByte("ppu lcd off tick quiet", g_bus.io[0x0F] & 0x02, 0x00);
    checkByte("ppu lcd off lyc frozen after tick", ppumod.ppuRead(&g_ppu, 0xFF41) & 0x04, 0x04);

    g_bus.io[0x0F] = 0;
    writeReg(0xFF40, 0x91);
    checkByte("ppu lcd reenable lyc irq", g_bus.io[0x0F] & 0x02, 0x02);
}

fn testSameValueLycWrite() void {
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = false, .serial_log = false, .turbo = false, .dynarec = false });
    emumod.emuReset(&g_emu);
    const gp: *ppumod.Ppu = &g_emu.ppu;
    const gb: *mmumod.Bus = &g_emu.bus;
    const gc: *cpumod.Cpu = &g_emu.cpu;
    gp.line = 0;
    gp.ly = 0;
    gp.dot = 0;
    gp.mode = 2;
    gp.lyc = 0;
    gp.coincidence = true;
    mmumod.write8(gb, 0xFF40, 0x91);
    mmumod.write8(gb, 0xFF41, 0x40);
    mmumod.write8(gb, 0xFF45, 0);
    mmumod.write8(gb, 0xFF0F, 0);
    gb.ie = 0;
    gb.lyc_dirty = false;

    const code: [18]u8 = [18]u8{
        0x3E, 0x00, 0xE0, 0x45,
        0x3E, 0x00, 0xE0, 0x0F,
        0x3E, 0x00, 0xE0, 0x45,
        0x3E, 0x00, 0xE0, 0x41,
        0x18, 0xFE,
    };
    var i: usize = 0;
    while (i < code.len) : (i += 1) {
        mmumod.write8(gb, @intCast(u16, 0xC000 + i), code[i]);
    }
    gc.pc = 0xC000;
    gc.sp = 0xFFFE;
    gc.ime = false;
    gc.halted = false;
    g_emu.rom_len = 1;
    _ = emumod.emuRunFrame(&g_emu);
    checkByte("ppu same-value lyc write irq", g_emu.bus.io[0x0F] & 0x02, 0x02);
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
    testStatLineEdge();
    testModeAccessLocking();
    testBackground();
    testWindow();
    testWindowClipping();
    testMode3Tiles();
    testLycWriteAndLcd();
    testLcdOffLycFrozen();
    testSprite8x8();
    testSprite8x16();
    testSpritePriority();
    testPalette();
    testSameValueLycWrite();
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

cat >"$OUT/save_test.zig" <<'ZIG'
const std = @import("std");
const filemod = @import("std_file");
const cartmod = @import("z9gb/cart.zig");
const mmumod = @import("z9gb/mmu.zig");
const emumod = @import("z9gb/emu.zig");
const savemod = @import("z9gb/save.zig");

const PATH_MAX: usize = 256;
const RAM_BYTES: usize = 32768;

var g_rom64: [65536]u8 = undefined;
var g_rom8: [8388608]u8 = undefined;
var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_emu: emumod.Emu = undefined;
var g_pass: u32 = 0;
var g_fail: u32 = 0;
var g_arena_buf: [1]u8 = undefined;
var g_sav_orig: [RAM_BYTES]u8 = undefined;
var g_rtc_orig: [32]u8 = undefined;

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

fn strEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
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

fn checkStr(label: []const u8, got: []const u8, want: []const u8) void {
    if (strEq(got, want)) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write("\n");
}

fn copy(out: []u8, data: []const u8) void {
    var i: usize = 0;
    while (i < data.len) : (i += 1) out[i] = data[i];
}

fn joinPath(dir: []const u8, name: []const u8, out: []u8) []const u8 {
    const need: usize = dir.len + 1 + name.len;
    if (need > out.len) return "";
    copy(out[0..dir.len], dir);
    out[dir.len] = '/';
    copy(out[dir.len + 1 .. need], name);
    return out[0..need];
}

fn makeRom(rom: []u8, typ: u8, romcode: u8, ramcode: u8) void {
    var i: usize = 0;
    while (i < 0x150) : (i += 1) rom[i] = 0;
    rom[0x0147] = typ;
    rom[0x0148] = romcode;
    rom[0x0149] = ramcode;
}

fn markBanks(rom: []u8, banks: usize) void {
    var b: usize = 0;
    while (b < banks) : (b += 1) {
        const off: usize = b * 0x4000;
        rom[off] = @intCast(u8, b & 0xFF);
        rom[off + 1] = @intCast(u8, (b >> 8) & 0xFF);
    }
}

fn latchNow(c: *cartmod.Cart) void {
    cartmod.rtcLatch(c, 0);
    cartmod.rtcLatch(c, 1);
}

fn testDerive() void {
    var b: [64]u8 = undefined;
    var n: usize = savemod.deriveSavePath("game.gb", ".sav", b[0..]);
    checkStr("derive simple", b[0..n], "game.sav");
    n = savemod.deriveSavePath("dir/game.gb", ".rtc", b[0..]);
    checkStr("derive dir rtc", b[0..n], "dir/game.rtc");
    n = savemod.deriveSavePath("game", ".sav", b[0..]);
    checkStr("derive no ext", b[0..n], "game.sav");
    n = savemod.deriveSavePath("a.b/c", ".sav", b[0..]);
    checkStr("derive dotted dir", b[0..n], "a.b/c.sav");
}

fn testMbc3() void {
    makeRom(g_rom64[0..], 0x10, 0x01, 0x03);
    markBanks(g_rom64[0..], 4);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom64[0..]) catch {
        checkBool("mbc3 load", false, true);
        return;
    };
    checkByte("mbc3 mbc", @enumToInt(g_cart.mbc), 3);
    cartmod.cartWrite(&g_cart, 0x2000, 2);
    checkByte("mbc3 rom bank2", cartmod.cartRead(&g_cart, 0x4000), 2);
    cartmod.cartWrite(&g_cart, 0x2000, 0);
    checkByte("mbc3 bank0 maps1", cartmod.cartRead(&g_cart, 0x4000), 1);
    cartmod.cartWrite(&g_cart, 0x0000, 0x0A);
    cartmod.cartWrite(&g_cart, 0x4000, 0);
    cartmod.cartWrite(&g_cart, 0xA000, 0x11);
    cartmod.cartWrite(&g_cart, 0x4000, 1);
    cartmod.cartWrite(&g_cart, 0xA000, 0x22);
    cartmod.cartWrite(&g_cart, 0x4000, 0);
    checkByte("mbc3 ram bank0", cartmod.cartRead(&g_cart, 0xA000), 0x11);
    cartmod.cartWrite(&g_cart, 0x4000, 1);
    checkByte("mbc3 ram bank1", cartmod.cartRead(&g_cart, 0xA000), 0x22);
    cartmod.cartWrite(&g_cart, 0x0000, 0x00);
    checkByte("mbc3 ram disabled", cartmod.cartRead(&g_cart, 0xA000), 0xFF);

    cartmod.rtcSetFixed(&g_cart, 2000000);
    cartmod.cartWrite(&g_cart, 0x4000, 8);
    checkByte("mbc3 rtc cart disabled read", cartmod.cartRead(&g_cart, 0xA000), 0xFF);
    cartmod.cartWrite(&g_cart, 0xA000, 9);
    latchNow(&g_cart);
    checkByte("mbc3 rtc cart disabled write", cartmod.cartRead(&g_cart, 0xA000), 0xFF);
    cartmod.cartWrite(&g_cart, 0x0000, 0x0A);
    latchNow(&g_cart);
    checkByte("mbc3 rtc cart enable gate", cartmod.cartRead(&g_cart, 0xA000), 0);
}

fn testMbc5() void {
    makeRom(g_rom8[0..], 0x19, 0x08, 0x04);
    markBanks(g_rom8[0..], 512);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom8[0..]) catch {
        checkBool("mbc5 load", false, true);
        return;
    };
    checkByte("mbc5 mbc", @enumToInt(g_cart.mbc), 5);
    cartmod.cartWrite(&g_cart, 0x2000, 0x34);
    cartmod.cartWrite(&g_cart, 0x3000, 0x00);
    checkByte("mbc5 bank 0x34 low", cartmod.cartRead(&g_cart, 0x4000), 0x34);
    checkByte("mbc5 bank 0x34 high", cartmod.cartRead(&g_cart, 0x4001), 0x00);
    cartmod.cartWrite(&g_cart, 0x2000, 0x00);
    cartmod.cartWrite(&g_cart, 0x3000, 0x00);
    checkByte("mbc5 bank0 valid", cartmod.cartRead(&g_cart, 0x4000), 0x00);
    cartmod.cartWrite(&g_cart, 0x2000, 0x00);
    cartmod.cartWrite(&g_cart, 0x3000, 0x01);
    checkByte("mbc5 bit8 low", cartmod.cartRead(&g_cart, 0x4000), 0x00);
    checkByte("mbc5 bit8 high", cartmod.cartRead(&g_cart, 0x4001), 0x01);
    cartmod.cartWrite(&g_cart, 0x2000, 0xFF);
    cartmod.cartWrite(&g_cart, 0x3000, 0x01);
    checkByte("mbc5 bank511 low", cartmod.cartRead(&g_cart, 0x4000), 0xFF);
    checkByte("mbc5 bank511 high", cartmod.cartRead(&g_cart, 0x4001), 0x01);
    cartmod.cartWrite(&g_cart, 0x0000, 0x0A);
    cartmod.cartWrite(&g_cart, 0x4000, 2);
    cartmod.cartWrite(&g_cart, 0xA000, 0x2A);
    cartmod.cartWrite(&g_cart, 0x4000, 5);
    cartmod.cartWrite(&g_cart, 0xA000, 0x5A);
    cartmod.cartWrite(&g_cart, 0x4000, 2);
    checkByte("mbc5 ram bank2", cartmod.cartRead(&g_cart, 0xA000), 0x2A);
    cartmod.cartWrite(&g_cart, 0x4000, 5);
    checkByte("mbc5 ram bank5", cartmod.cartRead(&g_cart, 0xA000), 0x5A);
}

fn testRtcWindow() void {
    makeRom(g_rom64[0..], 0x10, 0x01, 0x03);
    markBanks(g_rom64[0..], 4);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom64[0..]) catch {
        checkBool("rtc window load", false, true);
        return;
    };
    mmumod.busInit(&g_bus, &g_cart);
    cartmod.rtcSetFixed(&g_cart, 1000000);
    mmumod.write8(&g_bus, 0x4000, 8);
    checkBool("rtc window a0", g_bus.pages[0xA0].kind == .rtc, true);
    checkBool("rtc window bf", g_bus.pages[0xBF].kind == .rtc, true);
    latchNow(&g_cart);
    checkByte("rtc disabled read", mmumod.read8(&g_bus, 0xA000), 0xFF);
    mmumod.write8(&g_bus, 0xA000, 5);
    latchNow(&g_cart);
    checkByte("rtc disabled write ignored", mmumod.read8(&g_bus, 0xA000), 0xFF);
    mmumod.write8(&g_bus, 0x0000, 0x0A);
    latchNow(&g_cart);
    checkByte("rtc enabled write still zero", mmumod.read8(&g_bus, 0xA000), 0);
    mmumod.write8(&g_bus, 0xA000, 5);
    latchNow(&g_cart);
    checkByte("rtc mirror read a000", mmumod.read8(&g_bus, 0xA000), 5);
    checkByte("rtc mirror read bfff", mmumod.read8(&g_bus, 0xBFFF), 5);
    mmumod.write8(&g_bus, 0x4000, 0);
    checkBool("rtc window clears", g_bus.pages[0xA0].kind == .cart_ram, true);
    mmumod.write8(&g_bus, 0xA000, 0x33);
    checkByte("cart ram direct", mmumod.read8(&g_bus, 0xA000), 0x33);
}

fn testRtcSemantics() void {
    makeRom(g_rom64[0..], 0x10, 0x01, 0x03);
    markBanks(g_rom64[0..], 4);
    cartmod.cartInit(&g_cart);
    cartmod.cartLoad(&g_cart, g_rom64[0..]) catch {
        checkBool("rtc load", false, true);
        return;
    };
    cartmod.rtcSetFixed(&g_cart, 1000000);
    latchNow(&g_cart);
    checkByte("rtc starts sec", cartmod.rtcRead(&g_cart, 0), 0);
    cartmod.rtcSetFixed(&g_cart, 1000061);
    latchNow(&g_cart);
    checkByte("rtc delta sec", cartmod.rtcRead(&g_cart, 0), 1);
    checkByte("rtc delta min", cartmod.rtcRead(&g_cart, 1), 1);

    cartmod.rtcWrite(&g_cart, 0, 30);
    checkByte("rtc latched read stable", cartmod.rtcRead(&g_cart, 0), 1);
    latchNow(&g_cart);
    checkByte("rtc latch sees live write", cartmod.rtcRead(&g_cart, 0), 30);

    cartmod.rtcWrite(&g_cart, 4, 0x40);
    latchNow(&g_cart);
    checkByte("rtc halt flag", cartmod.rtcRead(&g_cart, 4) & 0x40, 0x40);
    const held: u8 = cartmod.rtcRead(&g_cart, 0);
    cartmod.rtcSetFixed(&g_cart, 1000061 + 3600);
    latchNow(&g_cart);
    checkByte("rtc halt freezes", cartmod.rtcRead(&g_cart, 0), held);

    cartmod.rtcWrite(&g_cart, 4, 0x00);
    cartmod.rtcSetFixed(&g_cart, 1000061 + 3600 + 2);
    latchNow(&g_cart);
    checkByte("rtc resumes after halt", cartmod.rtcRead(&g_cart, 0), 32);

    cartmod.rtcWrite(&g_cart, 3, 0xFF);
    cartmod.rtcWrite(&g_cart, 4, 0x01);
    latchNow(&g_cart);
    checkByte("rtc day 511 low", cartmod.rtcRead(&g_cart, 3), 0xFF);
    checkByte("rtc day 511 high", cartmod.rtcRead(&g_cart, 4) & 0x01, 0x01);
    cartmod.rtcSetFixed(&g_cart, 1000061 + 3600 + 2 + 86400);
    latchNow(&g_cart);
    checkByte("rtc day wraps low", cartmod.rtcRead(&g_cart, 3), 0);
    checkByte("rtc day wraps high", cartmod.rtcRead(&g_cart, 4) & 0x01, 0);
}

fn writeFile(path: []const u8, data: []const u8) bool {
    filemod.writeAll(path, data) catch return false;
    return true;
}

fn readFileExact(path: []const u8, out: []u8) bool {
    var arena = std.arena.init(g_arena_buf[0..]);
    var f = filemod.open(&arena, path, filemod.Mode.Read) catch return false;
    const sz = filemod.size(&f) catch {
        filemod.close(&f);
        return false;
    };
    if (sz != @intCast(i64, out.len)) {
        filemod.close(&f);
        return false;
    }
    var got: usize = 0;
    while (got < out.len) {
        const r = filemod.read(&f, out[got..out.len]) catch {
            filemod.close(&f);
            return false;
        };
        if (r == 0) break;
        got += r;
    }
    filemod.close(&f);
    return got == out.len;
}

fn fileSizeIs(path: []const u8, want: i64) bool {
    var arena = std.arena.init(g_arena_buf[0..]);
    var f = filemod.open(&arena, path, filemod.Mode.Read) catch return false;
    const sz = filemod.size(&f) catch {
        filemod.close(&f);
        return false;
    };
    filemod.close(&f);
    return sz == want;
}

fn expectCorrupt(e: *emumod.Emu, label: []const u8) void {
    var ok: bool = false;
    emumod.emuLoadBattery(e) catch |err| {
        if (err == error.SaveCorrupt) ok = true;
    };
    checkBool(label, ok, true);
}

fn setRamSentinels() void {
    mmumod.write8(&g_emu.bus, 0xA000, 0xA5);
    mmumod.write8(&g_emu.bus, 0xA001, 0x5A);
    mmumod.write8(&g_emu.bus, 0xA0FF, 0xC3);
}

fn checkRamSentinels(label: []const u8) void {
    checkBool(label, mmumod.read8(&g_emu.bus, 0xA000) == 0xA5 and mmumod.read8(&g_emu.bus, 0xA001) == 0x5A and mmumod.read8(&g_emu.bus, 0xA0FF) == 0xC3, true);
}

fn testSave(dir: []const u8) void {
    makeRom(g_rom64[0..], 0x10, 0x01, 0x03);
    markBanks(g_rom64[0..], 4);
    var rom_buf: [PATH_MAX]u8 = undefined;
    const rom_path: []const u8 = joinPath(dir, "rtc_round.gb", rom_buf[0..]);
    checkBool("save rom written", writeFile(rom_path, g_rom64[0..]), true);
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = false, .serial_log = false, .turbo = false, .dynarec = false });
    emumod.emuLoadRom(&g_emu, rom_path) catch {
        checkBool("save rom loads", false, true);
        return;
    };
    emumod.emuSetRtcFixed(&g_emu, 1700000000);
    checkBool("rtc seam freezes epoch", g_emu.cart.rtc.fixed and g_emu.cart.rtc.anchor == 1700000000, true);

    mmumod.write8(&g_emu.bus, 0x0000, 0x0A);
    mmumod.write8(&g_emu.bus, 0x4000, 0);
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        mmumod.write8(&g_emu.bus, @intCast(u16, 0xA000 + i), @intCast(u8, i & 0xFF));
    }
    cartmod.rtcWrite(&g_emu.cart, 0, 12);
    cartmod.rtcWrite(&g_emu.cart, 1, 34);
    cartmod.rtcWrite(&g_emu.cart, 2, 5);
    cartmod.rtcWrite(&g_emu.cart, 3, 0x78);
    cartmod.rtcWrite(&g_emu.cart, 4, 0x01);
    latchNow(&g_emu.cart);
    emumod.emuSaveBattery(&g_emu) catch {
        checkBool("save battery writes", false, true);
        return;
    };
    checkBool("save battery writes", true, true);

    var sav_buf: [PATH_MAX]u8 = undefined;
    var rtc_buf: [PATH_MAX]u8 = undefined;
    const slen: usize = savemod.deriveSavePath(rom_path, ".sav", sav_buf[0..]);
    const rlen: usize = savemod.deriveSavePath(rom_path, ".rtc", rtc_buf[0..]);
    const sav_path: []const u8 = sav_buf[0..slen];
    const rtc_path: []const u8 = rtc_buf[0..rlen];
    checkBool("sav size", fileSizeIs(sav_path, RAM_BYTES), true);
    checkBool("rtc size", fileSizeIs(rtc_path, 32), true);
    checkBool("sav readable", readFileExact(sav_path, g_sav_orig[0..]), true);
    checkBool("rtc readable", readFileExact(rtc_path, g_rtc_orig[0..]), true);
    var magic: [8]u8 = [8]u8{ 'Z', '9', '8', 'R', 'T', 'C', '1', 0 };
    checkStr("rtc magic", g_rtc_orig[0..8], magic[0..]);
    checkByte("rtc version", g_rtc_orig[8], 1);
    checkByte("rtc header seconds", g_rtc_orig[9], 12);
    checkByte("rtc header minutes", g_rtc_orig[10], 34);
    checkByte("rtc header hours", g_rtc_orig[11], 5);
    checkByte("rtc header day low", g_rtc_orig[12], 0x78);
    checkByte("rtc header day high", g_rtc_orig[13], 1);
    var tail_zero: bool = true;
    var ti: usize = 24;
    while (ti < 32) : (ti += 1) {
        if (g_rtc_orig[ti] != 0) tail_zero = false;
    }
    checkBool("rtc reserved tail zero", tail_zero, true);
    checkBool("rtc anchor captured", g_emu.cart.rtc.anchor == 1700000000, true);

    mmumod.write8(&g_emu.bus, 0xA000, 0xEE);
    mmumod.write8(&g_emu.bus, 0xA0FF, 0xEE);
    cartmod.rtcWrite(&g_emu.cart, 0, 1);
    latchNow(&g_emu.cart);
    emumod.emuLoadBattery(&g_emu) catch {
        checkBool("load battery reads", false, true);
        return;
    };
    checkBool("load battery reads", true, true);
    checkByte("sav restores byte0", g_emu.cart.ram[0], 0);
    checkByte("sav restores byte255", g_emu.cart.ram[255], 0xFF);
    checkByte("rtc restores seconds", cartmod.rtcRead(&g_emu.cart, 0), 12);
    checkByte("rtc restores minutes", cartmod.rtcRead(&g_emu.cart, 1), 34);
    checkByte("rtc restores hours", cartmod.rtcRead(&g_emu.cart, 2), 5);
    checkByte("rtc restores day low", cartmod.rtcRead(&g_emu.cart, 3), 0x78);
    checkByte("rtc restores day high", cartmod.rtcRead(&g_emu.cart, 4) & 0x01, 1);
    checkBool("rtc anchor preserved", g_emu.cart.rtc.anchor == 1700000000, true);

    setRamSentinels();
    checkBool("short rtc write", writeFile(rtc_path, g_rtc_orig[0..31]), true);
    expectCorrupt(&g_emu, "short rtc rejects");
    checkRamSentinels("short rtc keeps ram");
    checkBool("restore rtc 1", writeFile(rtc_path, g_rtc_orig[0..]), true);

    var bad: [32]u8 = undefined;
    copy(bad[0..], g_rtc_orig[0..]);
    bad[0] = 'X';
    checkBool("bad magic write", writeFile(rtc_path, bad[0..]), true);
    expectCorrupt(&g_emu, "bad magic rejects");
    checkRamSentinels("bad magic keeps ram");
    checkBool("restore rtc 2", writeFile(rtc_path, g_rtc_orig[0..]), true);

    copy(bad[0..], g_rtc_orig[0..]);
    bad[9] = 60;
    checkBool("bad counter write", writeFile(rtc_path, bad[0..]), true);
    expectCorrupt(&g_emu, "bad counter rejects");
    checkRamSentinels("bad counter keeps ram");
    checkBool("restore rtc 3", writeFile(rtc_path, g_rtc_orig[0..]), true);

    copy(bad[0..], g_rtc_orig[0..]);
    bad[14] = 0x80;
    checkBool("bad flags write", writeFile(rtc_path, bad[0..]), true);
    expectCorrupt(&g_emu, "bad flags rejects");
    checkRamSentinels("bad flags keeps ram");
    checkBool("restore rtc 4", writeFile(rtc_path, g_rtc_orig[0..]), true);

    copy(bad[0..], g_rtc_orig[0..]);
    var ai: usize = 16;
    while (ai < 24) : (ai += 1) {
        bad[ai] = 0xFF;
    }
    checkBool("bad anchor write", writeFile(rtc_path, bad[0..]), true);
    expectCorrupt(&g_emu, "bad anchor rejects");
    checkRamSentinels("bad anchor keeps ram");
    checkBool("restore rtc 5", writeFile(rtc_path, g_rtc_orig[0..]), true);

    copy(bad[0..], g_rtc_orig[0..]);
    bad[24] = 1;
    checkBool("bad reserved write", writeFile(rtc_path, bad[0..]), true);
    expectCorrupt(&g_emu, "bad reserved rejects");
    checkRamSentinels("bad reserved keeps ram");
    checkBool("restore rtc 6", writeFile(rtc_path, g_rtc_orig[0..]), true);

    setRamSentinels();
    checkBool("short sav write", writeFile(sav_path, g_sav_orig[0..1]), true);
    expectCorrupt(&g_emu, "short sav rejects");
    checkRamSentinels("short sav keeps ram");
    checkBool("restore sav", writeFile(sav_path, g_sav_orig[0..]), true);
}

fn testSaveNoTruncate(dir: []const u8) void {
    var path_buf: [PATH_MAX]u8 = undefined;
    const path: []const u8 = joinPath(dir, "trunc.sav", path_buf[0..]);
    checkBool("trunc original write", writeFile(path, "ORIGINAL"), true);
    emumod.emuSetSavePath(&g_emu, path);
    var got_io: bool = false;
    emumod.emuSaveBattery(&g_emu) catch |err| {
        if (err == error.Io) got_io = true;
    };
    checkBool("save failure is Io", got_io, true);
    var buf: [8]u8 = undefined;
    checkBool("trunc original readable", readFileExact(path, buf[0..]), true);
    checkStr("trunc original intact", buf[0..], "ORIGINAL");
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    const n: usize = @intCast(usize, argc);
    if (n < 2) {
        std.io.write("save FAIL no scratch dir\n");
        std.os.exit(2);
    }
    const dir: []const u8 = argAt(argv, 1);

    testDerive();
    testMbc3();
    testMbc5();
    testRtcWindow();
    testRtcSemantics();
    testSave(dir);
    testSaveNoTruncate(dir);

    std.io.write("save ");
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

run_save_mode() {
    mode="$1"
    flag="$2"
    bin="$OUT/$mode/save_test"
    mkdir -p "$OUT/$mode/save"
    mkdir -p "$OUT/$mode/save/trunc.sav.tmp"
    if timeout 120 "$ZIG" "$flag" -o "$OUT/$mode" "$OUT/save_test.zig" >"$OUT/$mode/save_zig.log" 2>&1; then
        pass_case "save $mode emits"
    else
        fail_case "save $mode emits"
        tail -20 "$OUT/$mode/save_zig.log" | sed 's/^/       /'
        return
    fi
    if sh "$OUT/$mode/build_target.sh" linux "$bin" >"$OUT/$mode/save_build.log" 2>&1; then
        pass_case "save $mode links"
    else
        fail_case "save $mode links"
        tail -20 "$OUT/$mode/save_build.log" | sed 's/^/       /'
        return
    fi
    if timeout 120 "$bin" "$OUT/$mode/save" >"$OUT/$mode/save_run.out" 2>"$OUT/$mode/save_run.err"; then
        pass_case "save $mode runs"
    else
        fail_case "save $mode runs"
        tail -20 "$OUT/$mode/save_run.err" | sed 's/^/       /'
        return
    fi
    if grep -q '^save ok ' "$OUT/$mode/save_run.out"; then
        pass_case "save $mode output ($(cat "$OUT/$mode/save_run.out"))"
    else
        fail_case "save $mode output (got $(cat "$OUT/$mode/save_run.out"))"
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

if [ "$RUN_SAVE" -eq 1 ]; then
    echo
    echo "== MBC3 RTC, MBC5, battery saves, corruption =="
    run_save_mode fast -ffast
    run_save_mode safe -fsafe
fi

if [ "$RUN_GATES" -eq 1 ]; then
    echo
    echo "== external ROM hard gates =="
    GATE_DIR="$OUT/gates"
    GATE_BUILD="$GATE_DIR/build"
    mkdir -p "$GATE_BUILD"
    GATE_READY=1
    if ! timeout 300 "$ZIG" -ffast -o "$GATE_BUILD" "$Z9DIR/main.zig" >"$GATE_DIR/build.log" 2>&1; then
        fail_case "gates build CLI"
        tail -20 "$GATE_DIR/build.log" | sed 's/^/       /'
        GATE_READY=0
    else
        # Optimize the emitted host C in the scratch tree only; the default
        # -O0 recipe is too slow for 200k-frame turbo verdict runs.
        if [ -f "$GATE_BUILD/build_target.sh" ]; then
            sed 's/-O0/-O2/g' "$GATE_BUILD/build_target.sh" >"$GATE_BUILD/build_target.sh.tmp" && mv "$GATE_BUILD/build_target.sh.tmp" "$GATE_BUILD/build_target.sh"
        fi
        if [ ! -f "$GATE_BUILD/build_target.sh" ] || ! sh "$GATE_BUILD/build_target.sh" linux "$GATE_BUILD/z9gb" >>"$GATE_DIR/build.log" 2>&1; then
            fail_case "gates link CLI"
            tail -20 "$GATE_DIR/build.log" | sed 's/^/       /'
            GATE_READY=0
        fi
    fi

    if [ "$GATE_READY" -eq 1 ]; then
        export Z9GB_BIN="$GATE_BUILD/z9gb"
        export ZIG

        run_gate() {
            gname="$1"
            gscript="$2"
            sh "$gscript" >"$GATE_DIR/$gname.out" 2>"$GATE_DIR/$gname.err"
            grc=$?
            cat "$GATE_DIR/$gname.out"
            if [ "$grc" -eq 0 ]; then
                pass_case "gate $gname"
            elif [ "$grc" -eq 77 ]; then
                echo "SKIP - gate $gname"
                SKIPS=$((SKIPS + 1))
            else
                fail_case "gate $gname (rc=$grc)"
                tail -20 "$GATE_DIR/$gname.err" | sed 's/^/       /'
            fi
        }

        run_gate blargg "$SCRIPT_DIR/run_blargg.sh"
        run_gate mooneye "$SCRIPT_DIR/run_mooneye.sh"
        run_gate acid2 "$SCRIPT_DIR/run_acid2.sh"
    fi
fi

echo
if [ "$RUN_GATES" -eq 1 ]; then
    echo "== tier_dmg summary: $PASSES passed, $FAILS failed, $SKIPS skipped =="
else
    echo "== tier_dmg summary: $PASSES passed, $FAILS failed =="
fi
if [ "$FAILS" -ne 0 ]; then
    echo "TIER_DMG FAIL"
    exit 1
fi
echo "TIER_DMG PASS"
exit 0
