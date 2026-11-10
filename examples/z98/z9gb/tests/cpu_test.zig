// cpu_test.zig — SM83 ALU, flags, DAA, rotate, and SP-offset tests (Task 2).
//
// Run as a normal executable under both -ffast and -fsafe. Each check is
// counted; the process exits 0 only when every check passes.

const std = @import("std");
const cartmod = @import("../cart.zig");
const mmumod = @import("../mmu.zig");
const cpumod = @import("../cpu.zig");

const FLAG_Z: u8 = 0x80;
const FLAG_N: u8 = 0x40;
const FLAG_H: u8 = 0x20;
const FLAG_C: u8 = 0x10;

const CODE: u16 = 0xC000;

var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_cpu: cpumod.Cpu = undefined;
var g_pass: u32 = 0;
var g_fail: u32 = 0;

fn printU(v: usize) void {
    const x: u32 = @intCast(u32, v & 0xffffffff);
    std.io.printInt(@intCast(i32, x & 0x7fffffff));
}

fn reset() void {
    cartmod.cartInit(&g_cart);
    mmumod.busInit(&g_bus, &g_cart);
    cpumod.cpuInit(&g_cpu);
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

fn flagMask(z: bool, n: bool, h: bool, c: bool) u8 {
    var f: u8 = 0;
    if (z) f |= FLAG_Z;
    if (n) f |= FLAG_N;
    if (h) f |= FLAG_H;
    if (c) f |= FLAG_C;
    return f;
}

fn checkFlags(label: []const u8, z: bool, n: bool, h: bool, c: bool) void {
    checkByte(label, g_cpu.f, flagMask(z, n, h, c));
}

fn run1(addr: u16, op: u8) void {
    mmumod.write8(&g_bus, addr, op);
    g_cpu.pc = addr;
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
}

fn runImm(addr: u16, op: u8, imm: u8) void {
    mmumod.write8(&g_bus, addr, op);
    mmumod.write8(&g_bus, addr +% 1, imm);
    g_cpu.pc = addr;
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
}

fn run2(addr: u16, b0: u8, b1: u8) void {
    mmumod.write8(&g_bus, addr, b0);
    mmumod.write8(&g_bus, addr +% 1, b1);
    g_cpu.pc = addr;
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
}

fn hl() u16 {
    const h: u16 = @intCast(u16, g_cpu.h);
    const l: u16 = @intCast(u16, g_cpu.l);
    return (h << 8) | l;
}

fn testAlu() void {
    const vals = [4]u8{ 0x00, 0x0F, 0x80, 0xFF };
    const add_ops = [2]u8{ 0x80, 0x88 };
    const sub_ops = [2]u8{ 0x90, 0x98 };
    const logic_ops = [4]u8{ 0xA0, 0xA8, 0xB0, 0xB8 };

    var ai: usize = 0;
    while (ai < vals.len) : (ai += 1) {
        var bi: usize = 0;
        while (bi < vals.len) : (bi += 1) {
            const a: u8 = vals[ai];
            const b: u8 = vals[bi];
            const ux: u16 = @intCast(u16, a);
            const uy: u16 = @intCast(u16, b);

            var oi: usize = 0;
            while (oi < add_ops.len) : (oi += 1) {
                const carry: u8 = if (oi == 1) 1 else 0;
                reset();
                g_cpu.a = a;
                g_cpu.b = b;
                g_cpu.f = if (carry == 1) FLAG_C else 0;
                run1(CODE, add_ops[oi]);
                const sum: u16 = ux + uy + @intCast(u16, carry);
                const r: u8 = @intCast(u8, sum & 0xFF);
                checkByte("add/adc result", g_cpu.a, r);
                checkFlags("add/adc flags", r == 0, false, ((ux & 0x0F) + (uy & 0x0F) + @intCast(u16, carry)) > 0x0F, sum > 0xFF);
            }

            oi = 0;
            while (oi < sub_ops.len) : (oi += 1) {
                const carry: u8 = if (oi == 1) 1 else 0;
                reset();
                g_cpu.a = a;
                g_cpu.b = b;
                g_cpu.f = if (carry == 1) FLAG_C else 0;
                run1(CODE, sub_ops[oi]);
                const diff: u16 = (ux + 0x100) - uy - @intCast(u16, carry);
                const r: u8 = @intCast(u8, diff & 0xFF);
                checkByte("sub/sbc result", g_cpu.a, r);
                checkFlags("sub/sbc flags", r == 0, true, (ux & 0x0F) < ((uy & 0x0F) + @intCast(u16, carry)), ux < (uy + @intCast(u16, carry)));
            }

            oi = 0;
            while (oi < logic_ops.len) : (oi += 1) {
                const op: u8 = logic_ops[oi];
                reset();
                g_cpu.a = a;
                g_cpu.b = b;
                g_cpu.f = 0xF0;
                run1(CODE, op);
                if (op == 0xA0) {
                    const r: u8 = a & b;
                    checkByte("and result", g_cpu.a, r);
                    checkFlags("and flags", r == 0, false, true, false);
                } else if (op == 0xA8) {
                    const r: u8 = a ^ b;
                    checkByte("xor result", g_cpu.a, r);
                    checkFlags("xor flags", r == 0, false, false, false);
                } else if (op == 0xB0) {
                    const r: u8 = a | b;
                    checkByte("or result", g_cpu.a, r);
                    checkFlags("or flags", r == 0, false, false, false);
                } else {
                    const diff: u16 = (ux + 0x100) - uy;
                    const r: u8 = @intCast(u8, diff & 0xFF);
                    checkByte("cp result", g_cpu.a, a);
                    checkFlags("cp flags", r == 0, true, (ux & 0x0F) < (uy & 0x0F), ux < uy);
                }
            }
        }
    }
}

fn testIncDec() void {
    reset();
    g_cpu.a = 0x0F;
    g_cpu.f = FLAG_C;
    run1(CODE, 0x3C);
    checkByte("inc 0x0F", g_cpu.a, 0x10);
    checkFlags("inc 0x0F flags", false, false, true, true);

    reset();
    g_cpu.a = 0xFF;
    g_cpu.f = 0;
    run1(CODE, 0x3C);
    checkByte("inc 0xFF", g_cpu.a, 0x00);
    checkFlags("inc 0xFF flags", true, false, true, false);

    reset();
    g_cpu.a = 0x10;
    g_cpu.f = FLAG_C;
    run1(CODE, 0x3D);
    checkByte("dec 0x10", g_cpu.a, 0x0F);
    checkFlags("dec 0x10 flags", false, true, true, true);

    reset();
    g_cpu.a = 0x01;
    g_cpu.f = FLAG_C;
    run1(CODE, 0x3D);
    checkByte("dec 0x01", g_cpu.a, 0x00);
    checkFlags("dec 0x01 flags", true, true, false, true);

    reset();
    g_cpu.b = 0x0F;
    g_cpu.f = 0;
    run1(CODE, 0x04);
    checkByte("inc B 0x0F", g_cpu.b, 0x10);
    checkFlags("inc B flags", false, false, true, false);

    reset();
    g_cpu.b = 0x10;
    g_cpu.f = 0;
    run1(CODE, 0x05);
    checkByte("dec B 0x10", g_cpu.b, 0x0F);
    checkFlags("dec B flags", false, true, true, false);
}

fn testDaa() void {
    reset();
    g_cpu.a = 0x45;
    g_cpu.b = 0x38;
    run2(CODE, 0x80, 0x27);
    checkByte("daa add 45+38", g_cpu.a, 0x83);
    checkFlags("daa add 45+38 flags", false, false, false, false);

    reset();
    g_cpu.a = 0x0F;
    g_cpu.b = 0x01;
    run2(CODE, 0x80, 0x27);
    checkByte("daa add 0F+01", g_cpu.a, 0x16);
    checkFlags("daa add 0F+01 flags", false, false, false, false);

    reset();
    g_cpu.a = 0x99;
    g_cpu.b = 0x01;
    run2(CODE, 0x80, 0x27);
    checkByte("daa add 99+01", g_cpu.a, 0x00);
    checkFlags("daa add 99+01 flags", true, false, false, true);

    reset();
    g_cpu.a = 0x99;
    g_cpu.b = 0x99;
    run2(CODE, 0x80, 0x27);
    checkByte("daa add 99+99", g_cpu.a, 0x98);
    checkFlags("daa add 99+99 flags", false, false, false, true);

    reset();
    g_cpu.a = 0x20;
    g_cpu.b = 0x05;
    run2(CODE, 0x90, 0x27);
    checkByte("daa sub 20-05", g_cpu.a, 0x15);
    checkFlags("daa sub 20-05 flags", false, true, false, false);

    reset();
    g_cpu.a = 0x00;
    g_cpu.b = 0x01;
    run2(CODE, 0x90, 0x27);
    checkByte("daa sub 00-01", g_cpu.a, 0x99);
    checkFlags("daa sub 00-01 flags", false, true, false, true);
}

fn testRotates() void {
    reset();
    g_cpu.a = 0x80;
    run1(CODE, 0x07);
    checkByte("rlca 0x80", g_cpu.a, 0x01);
    checkFlags("rlca 0x80 flags", false, false, false, true);

    reset();
    g_cpu.a = 0x7F;
    run1(CODE, 0x07);
    checkByte("rlca 0x7F", g_cpu.a, 0xFE);
    checkFlags("rlca 0x7F flags", false, false, false, false);

    reset();
    g_cpu.a = 0x01;
    run1(CODE, 0x0F);
    checkByte("rrca 0x01", g_cpu.a, 0x80);
    checkFlags("rrca 0x01 flags", false, false, false, true);

    reset();
    g_cpu.a = 0x80;
    run1(CODE, 0x0F);
    checkByte("rrca 0x80", g_cpu.a, 0x40);
    checkFlags("rrca 0x80 flags", false, false, false, false);

    reset();
    g_cpu.a = 0x80;
    g_cpu.f = 0;
    run1(CODE, 0x17);
    checkByte("rla 0x80 c0", g_cpu.a, 0x00);
    checkFlags("rla 0x80 c0 flags", false, false, false, true);

    reset();
    g_cpu.a = 0x80;
    g_cpu.f = FLAG_C;
    run1(CODE, 0x17);
    checkByte("rla 0x80 c1", g_cpu.a, 0x01);
    checkFlags("rla 0x80 c1 flags", false, false, false, true);

    reset();
    g_cpu.a = 0x00;
    g_cpu.f = FLAG_C;
    run1(CODE, 0x17);
    checkByte("rla 0x00 c1", g_cpu.a, 0x01);
    checkFlags("rla 0x00 c1 flags", false, false, false, false);

    reset();
    g_cpu.a = 0x01;
    g_cpu.f = 0;
    run1(CODE, 0x1F);
    checkByte("rra 0x01 c0", g_cpu.a, 0x00);
    checkFlags("rra 0x01 c0 flags", false, false, false, true);

    reset();
    g_cpu.a = 0x01;
    g_cpu.f = FLAG_C;
    run1(CODE, 0x1F);
    checkByte("rra 0x01 c1", g_cpu.a, 0x80);
    checkFlags("rra 0x01 c1 flags", false, false, false, true);

    reset();
    g_cpu.a = 0x00;
    g_cpu.f = FLAG_C;
    run1(CODE, 0x1F);
    checkByte("rra 0x00 c1", g_cpu.a, 0x80);
    checkFlags("rra 0x00 c1 flags", false, false, false, false);
}

fn testMisc() void {
    reset();
    g_cpu.a = 0x55;
    g_cpu.f = FLAG_C;
    run1(CODE, 0x2F);
    checkByte("cpl 0x55", g_cpu.a, 0xAA);
    checkFlags("cpl flags", false, true, true, true);

    reset();
    g_cpu.f = FLAG_Z;
    run1(CODE, 0x37);
    checkFlags("scf flags", true, false, false, true);

    reset();
    g_cpu.f = 0;
    run1(CODE, 0x3F);
    checkFlags("ccf c0 flags", false, false, false, true);

    reset();
    g_cpu.f = FLAG_Z | FLAG_N | FLAG_H | FLAG_C;
    run1(CODE, 0x3F);
    checkFlags("ccf c1 flags", true, false, false, false);
}

fn testSpOffset() void {
    reset();
    g_cpu.sp = 0xFFF8;
    runImm(CODE, 0xE8, 0x08);
    checkByte("add sp lo", @intCast(u8, g_cpu.sp & 0xFF), 0x00);
    checkByte("add sp hi", @intCast(u8, g_cpu.sp >> 8), 0x00);
    checkFlags("add sp +8 flags", false, false, true, true);

    reset();
    g_cpu.sp = 0x0000;
    runImm(CODE, 0xE8, 0xFF);
    checkByte("add sp -1 lo", @intCast(u8, g_cpu.sp & 0xFF), 0xFF);
    checkByte("add sp -1 hi", @intCast(u8, g_cpu.sp >> 8), 0xFF);
    checkFlags("add sp -1 flags", false, false, false, false);

    reset();
    g_cpu.sp = 0x0FFF;
    runImm(CODE, 0xE8, 0x01);
    checkByte("add sp +1 lo", @intCast(u8, g_cpu.sp & 0xFF), 0x00);
    checkByte("add sp +1 hi", @intCast(u8, g_cpu.sp >> 8), 0x10);
    checkFlags("add sp +1 flags", false, false, true, true);

    reset();
    g_cpu.sp = 0xFFF8;
    runImm(CODE, 0xF8, 0x08);
    checkByte("ld hl sp lo", @intCast(u8, hl() & 0xFF), 0x00);
    checkByte("ld hl sp hi", @intCast(u8, hl() >> 8), 0x00);
    checkByte("ld hl sp keeps sp lo", @intCast(u8, g_cpu.sp & 0xFF), 0xF8);
    checkByte("ld hl sp keeps sp hi", @intCast(u8, g_cpu.sp >> 8), 0xFF);
    checkFlags("ld hl sp flags", false, false, true, true);

    reset();
    g_cpu.sp = 0x1234;
    runImm(CODE, 0xF8, 0xF0);
    checkByte("ld hl sp -16 lo", @intCast(u8, hl() & 0xFF), 0x24);
    checkByte("ld hl sp -16 hi", @intCast(u8, hl() >> 8), 0x12);
    checkFlags("ld hl sp -16 flags", false, false, false, true);
}

pub fn main() void {
    testAlu();
    testIncDec();
    testDaa();
    testRotates();
    testMisc();
    testSpOffset();

    std.io.write("cpu ");
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
