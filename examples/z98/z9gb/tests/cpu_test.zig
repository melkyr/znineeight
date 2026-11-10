// cpu_test.zig — SM83 ALU, flags, DAA, loads, stack, and control-flow tests.
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

fn runImm16(addr: u16, op: u8, imm: u16) void {
    mmumod.write8(&g_bus, addr, op);
    mmumod.write16(&g_bus, addr +% 1, imm);
    g_cpu.pc = addr;
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
}

fn run1C(addr: u16, op: u8) u32 {
    mmumod.write8(&g_bus, addr, op);
    g_cpu.pc = addr;
    return cpumod.cpuStep(&g_cpu, &g_bus);
}

fn runImmC(addr: u16, op: u8, imm: u8) u32 {
    mmumod.write8(&g_bus, addr, op);
    mmumod.write8(&g_bus, addr +% 1, imm);
    g_cpu.pc = addr;
    return cpumod.cpuStep(&g_cpu, &g_bus);
}

fn runImm16C(addr: u16, op: u8, imm: u16) u32 {
    mmumod.write8(&g_bus, addr, op);
    mmumod.write16(&g_bus, addr +% 1, imm);
    g_cpu.pc = addr;
    return cpumod.cpuStep(&g_cpu, &g_bus);
}

fn runCbC(addr: u16, op2: u8) u32 {
    mmumod.write8(&g_bus, addr, 0xCB);
    mmumod.write8(&g_bus, addr +% 1, op2);
    g_cpu.pc = addr;
    return cpumod.cpuStep(&g_cpu, &g_bus);
}

fn runCb(addr: u16, op2: u8) void {
    _ = runCbC(addr, op2);
}

fn cbMask(bit: u8) u16 {
    return @intCast(u16, 1) << @intCast(u4, bit);
}

fn checkCycles(label: []const u8, got: u32, want: u32) void {
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
    checkByte(label, @intCast(u8, got & 0xFF), @intCast(u8, want & 0xFF));
    checkByte(label, @intCast(u8, got >> 8), @intCast(u8, want >> 8));
}

fn checkBool(label: []const u8, got: bool, want: bool) void {
    checkByte(label, if (got) 1 else 0, if (want) 1 else 0);
}

fn hl() u16 {
    const h: u16 = @intCast(u16, g_cpu.h);
    const l: u16 = @intCast(u16, g_cpu.l);
    return (h << 8) | l;
}

fn bc() u16 {
    const b: u16 = @intCast(u16, g_cpu.b);
    const c: u16 = @intCast(u16, g_cpu.c);
    return (b << 8) | c;
}

fn de() u16 {
    const d: u16 = @intCast(u16, g_cpu.d);
    const e: u16 = @intCast(u16, g_cpu.e);
    return (d << 8) | e;
}

fn regGet(idx: u8) u8 {
    switch (idx) {
        0 => return g_cpu.b,
        1 => return g_cpu.c,
        2 => return g_cpu.d,
        3 => return g_cpu.e,
        4 => return g_cpu.h,
        5 => return g_cpu.l,
        6 => return mmumod.read8(&g_bus, hl()),
        7 => return g_cpu.a,
        else => unreachable,
    }
}

fn regSet(idx: u8, value: u8) void {
    switch (idx) {
        0 => g_cpu.b = value,
        1 => g_cpu.c = value,
        2 => g_cpu.d = value,
        3 => g_cpu.e = value,
        4 => g_cpu.h = value,
        5 => g_cpu.l = value,
        6 => mmumod.write8(&g_bus, hl(), value),
        7 => g_cpu.a = value,
        else => unreachable,
    }
}

fn seedReturn(value: u16) void {
    g_cpu.sp = 0xD000;
    mmumod.write16(&g_bus, g_cpu.sp, value);
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

fn testLoadRegReg() void {
    var op: u16 = 0x40;
    while (op <= 0x7F) : (op += 1) {
        if (op != 0x76) {
            reset();
            g_cpu.b = 0xB0;
            g_cpu.c = 0xC1;
            g_cpu.d = 0xD2;
            g_cpu.e = 0xE3;
            g_cpu.h = 0xC5;
            g_cpu.l = 0x06;
            g_cpu.a = 0xA4;
            mmumod.write8(&g_bus, 0xC506, 0x99);

            const dst: u8 = @intCast(u8, (op >> 3) & 0x07);
            const src: u8 = @intCast(u8, op & 0x07);
            const want: u8 = regGet(src);
            run1(CODE, @intCast(u8, op));
            if (dst == 6) {
                checkByte("ld (hl),r", mmumod.read8(&g_bus, 0xC506), want);
            } else {
                checkByte("ld r,r'", regGet(dst), want);
            }
        }
    }
}

fn testLoads() void {
    testLoadRegReg();

    reset();
    g_cpu.b = 0xC1;
    g_cpu.c = 0x10;
    g_cpu.a = 0x5A;
    run1(CODE, 0x02);
    checkByte("ld (bc),a", mmumod.read8(&g_bus, 0xC110), 0x5A);

    reset();
    g_cpu.d = 0xC1;
    g_cpu.e = 0x20;
    g_cpu.a = 0x6B;
    run1(CODE, 0x12);
    checkByte("ld (de),a", mmumod.read8(&g_bus, 0xC120), 0x6B);

    reset();
    g_cpu.h = 0xC1;
    g_cpu.l = 0x30;
    g_cpu.a = 0x7C;
    run1(CODE, 0x22);
    checkByte("ld (hl+),a mem", mmumod.read8(&g_bus, 0xC130), 0x7C);
    checkByte("ld (hl+),a lo", @intCast(u8, hl() & 0xFF), 0x31);
    checkByte("ld (hl+),a hi", @intCast(u8, hl() >> 8), 0xC1);

    reset();
    g_cpu.h = 0xC1;
    g_cpu.l = 0x40;
    g_cpu.a = 0x8D;
    run1(CODE, 0x32);
    checkByte("ld (hl-),a mem", mmumod.read8(&g_bus, 0xC140), 0x8D);
    checkByte("ld (hl-),a lo", @intCast(u8, hl() & 0xFF), 0x3F);
    checkByte("ld (hl-),a hi", @intCast(u8, hl() >> 8), 0xC1);

    reset();
    g_cpu.b = 0xC1;
    g_cpu.c = 0x50;
    mmumod.write8(&g_bus, 0xC150, 0x9E);
    run1(CODE, 0x0A);
    checkByte("ld a,(bc)", g_cpu.a, 0x9E);

    reset();
    g_cpu.d = 0xC1;
    g_cpu.e = 0x60;
    mmumod.write8(&g_bus, 0xC160, 0xAF);
    run1(CODE, 0x1A);
    checkByte("ld a,(de)", g_cpu.a, 0xAF);

    reset();
    g_cpu.h = 0xC1;
    g_cpu.l = 0x70;
    mmumod.write8(&g_bus, 0xC170, 0xB0);
    run1(CODE, 0x2A);
    checkByte("ld a,(hl+) value", g_cpu.a, 0xB0);
    checkByte("ld a,(hl+) lo", @intCast(u8, hl() & 0xFF), 0x71);
    checkByte("ld a,(hl+) hi", @intCast(u8, hl() >> 8), 0xC1);

    reset();
    g_cpu.h = 0xC1;
    g_cpu.l = 0x70;
    mmumod.write8(&g_bus, 0xC170, 0xB1);
    run1(CODE, 0x3A);
    checkByte("ld a,(hl-) value", g_cpu.a, 0xB1);
    checkByte("ld a,(hl-) lo", @intCast(u8, hl() & 0xFF), 0x6F);
    checkByte("ld a,(hl-) hi", @intCast(u8, hl() >> 8), 0xC1);

    reset();
    g_cpu.a = 0xC1;
    runImm(CODE, 0xE0, 0x80);
    checkByte("ldh (a8),a", mmumod.read8(&g_bus, 0xFF80), 0xC1);

    reset();
    mmumod.write8(&g_bus, 0xFF81, 0xD2);
    runImm(CODE, 0xF0, 0x81);
    checkByte("ldh a,(a8)", g_cpu.a, 0xD2);

    reset();
    g_cpu.c = 0x82;
    g_cpu.a = 0xE3;
    run1(CODE, 0xE2);
    checkByte("ld (c),a", mmumod.read8(&g_bus, 0xFF82), 0xE3);

    reset();
    g_cpu.c = 0x83;
    mmumod.write8(&g_bus, 0xFF83, 0xF4);
    run1(CODE, 0xF2);
    checkByte("ld a,(c)", g_cpu.a, 0xF4);

    reset();
    g_cpu.a = 0x55;
    runImm16(CODE, 0xEA, 0xC200);
    checkByte("ld (a16),a", mmumod.read8(&g_bus, 0xC200), 0x55);

    reset();
    mmumod.write8(&g_bus, 0xC201, 0x66);
    runImm16(CODE, 0xFA, 0xC201);
    checkByte("ld a,(a16)", g_cpu.a, 0x66);

    reset();
    g_cpu.sp = 0x1234;
    runImm16(CODE, 0x08, 0xC202);
    checkWord("ld (a16),sp", mmumod.read16(&g_bus, 0xC202), 0x1234);

    reset();
    runImm16(CODE, 0x01, 0xBEEF);
    checkWord("ld bc,d16", bc(), 0xBEEF);

    reset();
    runImm16(CODE, 0x11, 0xCAFE);
    checkWord("ld de,d16", de(), 0xCAFE);

    reset();
    runImm16(CODE, 0x21, 0xD00F);
    checkWord("ld hl,d16", hl(), 0xD00F);

    reset();
    runImm16(CODE, 0x31, 0xFFFE);
    checkWord("ld sp,d16", g_cpu.sp, 0xFFFE);

    reset();
    g_cpu.b = 0x10;
    g_cpu.c = 0xFF;
    run1(CODE, 0x03);
    checkWord("inc bc", bc(), 0x1100);

    reset();
    g_cpu.b = 0x10;
    g_cpu.c = 0x00;
    run1(CODE, 0x0B);
    checkWord("dec bc", bc(), 0x0FFF);

    reset();
    g_cpu.h = 0x0F;
    g_cpu.l = 0xFF;
    g_cpu.b = 0x00;
    g_cpu.c = 0x01;
    g_cpu.f = FLAG_Z;
    run1(CODE, 0x09);
    checkWord("add hl,bc", hl(), 0x1000);
    checkFlags("add hl,bc flags", true, false, true, false);

    reset();
    g_cpu.h = 0xD0;
    g_cpu.l = 0x42;
    const sp_hl_cycles: u32 = run1C(CODE, 0xF9);
    checkWord("ld sp,hl", g_cpu.sp, 0xD042);
    checkCycles("ld sp,hl cycles", sp_hl_cycles, 8);
}

fn testImmediateAlu() void {
    const ops = [8]u8{ 0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE };
    const avals = [3]u8{ 0x00, 0x0F, 0xFF };
    const bvals = [3]u8{ 0x00, 0x01, 0xF0 };

    var oi: usize = 0;
    while (oi < 8) : (oi += 1) {
        const op: u8 = ops[oi];
        var ci: usize = 0;
        while (ci < 2) : (ci += 1) {
            var ai: usize = 0;
            while (ai < 3) : (ai += 1) {
                var bi: usize = 0;
                while (bi < 3) : (bi += 1) {
                    const a: u8 = avals[ai];
                    const b: u8 = bvals[bi];
                    const carry: u8 = if (ci == 1) 1 else 0;
                    const use_carry: u8 = if (op == 0xCE or op == 0xDE) carry else 0;
                    reset();
                    g_cpu.a = a;
                    g_cpu.f = if (carry == 1) FLAG_C else 0;
                    const cyc: u32 = runImmC(CODE, op, b);
                    const ux: u16 = @intCast(u16, a);
                    const uy: u16 = @intCast(u16, b);

                    if (op == 0xC6 or op == 0xCE) {
                        const sum: u16 = ux + uy + @intCast(u16, use_carry);
                        const r: u8 = @intCast(u8, sum & 0xFF);
                        checkByte("add imm result", g_cpu.a, r);
                        checkFlags("add imm flags", r == 0, false, ((ux & 0x0F) + (uy & 0x0F) + @intCast(u16, use_carry)) > 0x0F, sum > 0xFF);
                    } else if (op == 0xD6 or op == 0xDE) {
                        const diff: u16 = (ux + 0x100) - uy - @intCast(u16, use_carry);
                        const r: u8 = @intCast(u8, diff & 0xFF);
                        checkByte("sub imm result", g_cpu.a, r);
                        checkFlags("sub imm flags", r == 0, true, (ux & 0x0F) < ((uy & 0x0F) + @intCast(u16, use_carry)), ux < (uy + @intCast(u16, use_carry)));
                    } else if (op == 0xE6) {
                        const r: u8 = a & b;
                        checkByte("and imm result", g_cpu.a, r);
                        checkFlags("and imm flags", r == 0, false, true, false);
                    } else if (op == 0xEE) {
                        const r: u8 = a ^ b;
                        checkByte("xor imm result", g_cpu.a, r);
                        checkFlags("xor imm flags", r == 0, false, false, false);
                    } else if (op == 0xF6) {
                        const r: u8 = a | b;
                        checkByte("or imm result", g_cpu.a, r);
                        checkFlags("or imm flags", r == 0, false, false, false);
                    } else {
                        const diff: u16 = (ux + 0x100) - uy;
                        const r: u8 = @intCast(u8, diff & 0xFF);
                        checkByte("cp imm preserves a", g_cpu.a, a);
                        checkFlags("cp imm flags", r == 0, true, (ux & 0x0F) < (uy & 0x0F), ux < uy);
                    }
                    checkCycles("imm alu cycles", cyc, 8);
                }
            }
        }
    }
}

fn testStack() void {
    reset();
    g_cpu.sp = 0xD000;
    g_cpu.b = 0x12;
    g_cpu.c = 0x34;
    run1(CODE, 0xC5);
    checkWord("push bc sp", g_cpu.sp, 0xCFFE);
    checkByte("push bc low", mmumod.read8(&g_bus, 0xCFFE), 0x34);
    checkByte("push bc high", mmumod.read8(&g_bus, 0xCFFF), 0x12);
    g_cpu.b = 0;
    g_cpu.c = 0;
    run1(CODE, 0xC1);
    checkWord("pop bc sp", g_cpu.sp, 0xD000);
    checkByte("pop bc b", g_cpu.b, 0x12);
    checkByte("pop bc c", g_cpu.c, 0x34);

    reset();
    g_cpu.sp = 0xD080;
    g_cpu.d = 0x56;
    g_cpu.e = 0x78;
    run1(CODE, 0xD5);
    checkWord("push de sp", g_cpu.sp, 0xD07E);
    checkByte("push de low", mmumod.read8(&g_bus, 0xD07E), 0x78);
    checkByte("push de high", mmumod.read8(&g_bus, 0xD07F), 0x56);
    g_cpu.d = 0;
    g_cpu.e = 0;
    run1(CODE, 0xD1);
    checkWord("pop de sp", g_cpu.sp, 0xD080);
    checkByte("pop de d", g_cpu.d, 0x56);
    checkByte("pop de e", g_cpu.e, 0x78);

    reset();
    g_cpu.sp = 0xD090;
    g_cpu.h = 0x9A;
    g_cpu.l = 0xBC;
    run1(CODE, 0xE5);
    checkWord("push hl sp", g_cpu.sp, 0xD08E);
    checkByte("push hl low", mmumod.read8(&g_bus, 0xD08E), 0xBC);
    checkByte("push hl high", mmumod.read8(&g_bus, 0xD08F), 0x9A);
    g_cpu.h = 0;
    g_cpu.l = 0;
    run1(CODE, 0xE1);
    checkWord("pop hl sp", g_cpu.sp, 0xD090);
    checkWord("pop hl value", hl(), 0x9ABC);

    reset();
    g_cpu.sp = 0xD100;
    g_cpu.a = 0xAB;
    g_cpu.f = 0xF0;
    run1(CODE, 0xF5);
    checkWord("push af sp", g_cpu.sp, 0xD0FE);
    checkByte("push af low", mmumod.read8(&g_bus, 0xD0FE), 0xF0);
    checkByte("push af high", mmumod.read8(&g_bus, 0xD0FF), 0xAB);
    g_cpu.a = 0;
    g_cpu.f = 0;
    run1(CODE, 0xF1);
    checkWord("pop af sp", g_cpu.sp, 0xD100);
    checkByte("pop af a", g_cpu.a, 0xAB);
    checkByte("pop af f", g_cpu.f, 0xF0);

    reset();
    g_cpu.sp = 0xD200;
    mmumod.write8(&g_bus, 0xD200, 0xEF);
    mmumod.write8(&g_bus, 0xD201, 0x12);
    run1(CODE, 0xF1);
    checkByte("pop af mask a", g_cpu.a, 0x12);
    checkByte("pop af mask f", g_cpu.f, 0xE0);
}

fn testJumps() void {
    reset();
    runImm16(CODE, 0xC3, 0xC123);
    checkWord("jp a16", g_cpu.pc, 0xC123);

    reset();
    g_cpu.h = 0xC4;
    g_cpu.l = 0x56;
    run1(CODE, 0xE9);
    checkWord("jp (hl)", g_cpu.pc, 0xC456);

    const jp_ops = [4]u8{ 0xC2, 0xCA, 0xD2, 0xDA };
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        reset();
        if (i == 1) g_cpu.f = FLAG_Z;
        if (i == 3) g_cpu.f = FLAG_C;
        const cyc: u32 = runImm16C(CODE, jp_ops[i], 0xC321);
        checkWord("jp cc taken", g_cpu.pc, 0xC321);
        checkCycles("jp cc taken cycles", cyc, 16);
    }
    i = 0;
    while (i < 4) : (i += 1) {
        reset();
        if (i == 0) g_cpu.f = FLAG_Z;
        if (i == 1) g_cpu.f = 0;
        if (i == 2) g_cpu.f = FLAG_C;
        if (i == 3) g_cpu.f = 0;
        const cyc: u32 = runImm16C(CODE, jp_ops[i], 0xC321);
        checkWord("jp cc not taken", g_cpu.pc, CODE +% 3);
        checkCycles("jp cc not taken cycles", cyc, 12);
    }

    reset();
    runImm(CODE, 0x18, 0x02);
    checkWord("jr +2", g_cpu.pc, CODE +% 4);

    reset();
    runImm(CODE, 0x18, 0xFE);
    checkWord("jr -2", g_cpu.pc, CODE);

    const jr_ops = [4]u8{ 0x20, 0x28, 0x30, 0x38 };
    i = 0;
    while (i < 4) : (i += 1) {
        reset();
        if (i == 1) g_cpu.f = FLAG_Z;
        if (i == 3) g_cpu.f = FLAG_C;
        const cyc: u32 = runImmC(CODE, jr_ops[i], 0x04);
        checkWord("jr cc taken", g_cpu.pc, CODE +% 6);
        checkCycles("jr cc taken cycles", cyc, 12);
    }
    i = 0;
    while (i < 4) : (i += 1) {
        reset();
        if (i == 0) g_cpu.f = FLAG_Z;
        if (i == 1) g_cpu.f = 0;
        if (i == 2) g_cpu.f = FLAG_C;
        if (i == 3) g_cpu.f = 0;
        const cyc: u32 = runImmC(CODE, jr_ops[i], 0x04);
        checkWord("jr cc not taken", g_cpu.pc, CODE +% 2);
        checkCycles("jr cc not taken cycles", cyc, 8);
    }
}

fn testCalls() void {
    reset();
    g_cpu.sp = 0xD000;
    runImm16(CODE, 0xCD, 0xC200);
    checkWord("call a16 pc", g_cpu.pc, 0xC200);
    checkWord("call a16 sp", g_cpu.sp, 0xCFFE);
    checkWord("call a16 ret", mmumod.read16(&g_bus, 0xCFFE), CODE +% 3);

    mmumod.write8(&g_bus, 0xC200, 0xC9);
    _ = cpumod.cpuStep(&g_cpu, &g_bus);
    checkWord("ret after call pc", g_cpu.pc, CODE +% 3);
    checkWord("ret after call sp", g_cpu.sp, 0xD000);

    reset();
    seedReturn(0xC345);
    run1(CODE, 0xC9);
    checkWord("ret pc", g_cpu.pc, 0xC345);
    checkWord("ret sp", g_cpu.sp, 0xD002);

    const ret_ops = [4]u8{ 0xC0, 0xC8, 0xD0, 0xD8 };
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        reset();
        if (i == 1) g_cpu.f = FLAG_Z;
        if (i == 3) g_cpu.f = FLAG_C;
        seedReturn(0xC456);
        const cyc: u32 = run1C(CODE, ret_ops[i]);
        checkWord("ret cc taken pc", g_cpu.pc, 0xC456);
        checkWord("ret cc taken sp", g_cpu.sp, 0xD002);
        checkCycles("ret cc taken cycles", cyc, 20);
    }
    i = 0;
    while (i < 4) : (i += 1) {
        reset();
        if (i == 0) g_cpu.f = FLAG_Z;
        if (i == 1) g_cpu.f = 0;
        if (i == 2) g_cpu.f = FLAG_C;
        if (i == 3) g_cpu.f = 0;
        seedReturn(0xC456);
        const cyc: u32 = run1C(CODE, ret_ops[i]);
        checkWord("ret cc not taken pc", g_cpu.pc, CODE +% 1);
        checkWord("ret cc not taken sp", g_cpu.sp, 0xD000);
        checkCycles("ret cc not taken cycles", cyc, 8);
    }

    reset();
    g_cpu.sp = 0xD020;
    g_cpu.ime = false;
    mmumod.write16(&g_bus, 0xD020, 0xC0DE);
    run1(CODE, 0xD9);
    checkWord("reti pc", g_cpu.pc, 0xC0DE);
    checkWord("reti sp", g_cpu.sp, 0xD022);
    checkBool("reti ime", g_cpu.ime, true);

    const call_ops = [4]u8{ 0xC4, 0xCC, 0xD4, 0xDC };
    i = 0;
    while (i < 4) : (i += 1) {
        reset();
        g_cpu.sp = 0xD000;
        if (i == 1) g_cpu.f = FLAG_Z;
        if (i == 3) g_cpu.f = FLAG_C;
        const cyc: u32 = runImm16C(CODE, call_ops[i], 0xC300);
        checkWord("call cc taken pc", g_cpu.pc, 0xC300);
        checkWord("call cc taken sp", g_cpu.sp, 0xCFFE);
        checkWord("call cc taken ret", mmumod.read16(&g_bus, 0xCFFE), CODE +% 3);
        checkCycles("call cc taken cycles", cyc, 24);
    }
    i = 0;
    while (i < 4) : (i += 1) {
        reset();
        g_cpu.sp = 0xD000;
        if (i == 0) g_cpu.f = FLAG_Z;
        if (i == 1) g_cpu.f = 0;
        if (i == 2) g_cpu.f = FLAG_C;
        if (i == 3) g_cpu.f = 0;
        const cyc: u32 = runImm16C(CODE, call_ops[i], 0xC300);
        checkWord("call cc not taken pc", g_cpu.pc, CODE +% 3);
        checkWord("call cc not taken sp", g_cpu.sp, 0xD000);
        checkCycles("call cc not taken cycles", cyc, 12);
    }

    const rst_ops = [8]u8{ 0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF };
    i = 0;
    while (i < 8) : (i += 1) {
        reset();
        g_cpu.sp = 0xD000;
        run1(CODE, rst_ops[i]);
        const vec: u16 = @intCast(u16, rst_ops[i]) & 0x0038;
        checkWord("rst pc", g_cpu.pc, vec);
        checkWord("rst sp", g_cpu.sp, 0xCFFE);
        checkWord("rst ret", mmumod.read16(&g_bus, 0xCFFE), CODE +% 1);
    }
}

fn cbExpectShift(kind: u8, value: u8, carry_in: bool, out_result: *u8, out_z: *bool, out_c: *bool) void {
    const x: u16 = @intCast(u16, value);
    var result: u16 = x;
    var carry: bool = false;
    switch (kind) {
        0 => {
            carry = (x & 0x80) != 0;
            const bit: u16 = if (carry) 1 else 0;
            result = ((x << 1) | bit) & 0xFF;
        },
        1 => {
            carry = (x & 0x01) != 0;
            const bit: u16 = if (carry) 0x80 else 0;
            result = ((x >> 1) | bit) & 0xFF;
        },
        2 => {
            carry = (x & 0x80) != 0;
            const bit: u16 = if (carry_in) 1 else 0;
            result = ((x << 1) | bit) & 0xFF;
        },
        3 => {
            carry = (x & 0x01) != 0;
            const bit: u16 = if (carry_in) 0x80 else 0;
            result = ((x >> 1) | bit) & 0xFF;
        },
        4 => {
            carry = (x & 0x80) != 0;
            result = (x << 1) & 0xFF;
        },
        5 => {
            carry = (x & 0x01) != 0;
            result = (x >> 1) | (x & 0x80);
        },
        6 => {
            carry = false;
            result = ((x & 0x0F) << 4) | ((x & 0xF0) >> 4);
        },
        7 => {
            carry = (x & 0x01) != 0;
            result = (x >> 1) & 0xFF;
        },
        else => unreachable,
    }
    out_result.* = @intCast(u8, result & 0xFF);
    out_z.* = (result & 0xFF) == 0;
    out_c.* = carry;
}

fn testCbRotates() void {
    const vals = [5]u8{ 0x00, 0x01, 0x80, 0xFF, 0x81 };
    var kind: u8 = 0;
    while (kind < 8) : (kind += 1) {
        var vi: usize = 0;
        while (vi < vals.len) : (vi += 1) {
            var ci: usize = 0;
            while (ci < 2) : (ci += 1) {
                const carry_in: bool = ci == 1;
                const in_flags: u8 = if (carry_in) FLAG_C else 0;
                var want_result: u8 = 0;
                var want_z: bool = false;
                var want_c: bool = false;
                cbExpectShift(kind, vals[vi], carry_in, &want_result, &want_z, &want_c);

                reset();
                g_cpu.b = vals[vi];
                g_cpu.f = in_flags;
                const reg_cycles: u32 = runCbC(CODE, @intCast(u8, (@intCast(u16, kind) << 3) & 0x38));
                checkByte("cb rot reg result", g_cpu.b, want_result);
                checkFlags("cb rot reg flags", want_z, false, false, want_c);
                checkCycles("cb rot reg cycles", reg_cycles, 8);

                reset();
                g_cpu.h = 0xC1;
                g_cpu.l = 0x00;
                mmumod.write8(&g_bus, 0xC100, vals[vi]);
                g_cpu.f = in_flags;
                const hl_cycles: u32 = runCbC(CODE, @intCast(u8, ((@intCast(u16, kind) << 3) & 0x38) | 0x06));
                checkByte("cb rot hl result", mmumod.read8(&g_bus, 0xC100), want_result);
                checkFlags("cb rot hl flags", want_z, false, false, want_c);
                checkCycles("cb rot hl cycles", hl_cycles, 16);
            }
        }
    }
}

fn testCbAllRegs() void {
    var idx: u8 = 0;
    while (idx < 8) : (idx += 1) {
        reset();
        g_cpu.h = 0xC1;
        g_cpu.l = 0x00;
        regSet(idx, 0x81);
        const cycles: u32 = runCbC(CODE, idx);
        checkByte("cb rlc all regs", regGet(idx), 0x03);
        checkFlags("cb rlc all regs flags", false, false, false, true);
        checkCycles("cb rlc all regs cycles", cycles, if (idx == 6) 16 else 8);
    }
}

fn testCbBit() void {
    var bit: u8 = 0;
    while (bit < 8) : (bit += 1) {
        const sh: u8 = @intCast(u8, (@intCast(u16, bit) << 3) & 0x38);
        const mask: u8 = @intCast(u8, cbMask(bit));

        reset();
        g_cpu.b = mask;
        g_cpu.f = FLAG_Z | FLAG_N | FLAG_H | FLAG_C;
        const reg_cycles: u32 = runCbC(CODE, @intCast(u8, 0x40 | @intCast(u16, sh)));
        checkByte("cb bit set keeps b", g_cpu.b, mask);
        checkFlags("cb bit set flags", false, false, false, true);
        checkCycles("cb bit reg cycles", reg_cycles, 8);

        reset();
        g_cpu.b = 0;
        g_cpu.f = FLAG_N | FLAG_H | FLAG_C;
        _ = runCbC(CODE, @intCast(u8, 0x40 | @intCast(u16, sh)));
        checkFlags("cb bit clear flags", true, false, false, true);

        reset();
        g_cpu.h = 0xC1;
        g_cpu.l = 0x10;
        mmumod.write8(&g_bus, 0xC110, mask);
        g_cpu.f = FLAG_N | FLAG_H | FLAG_C;
        const hl_cycles: u32 = runCbC(CODE, @intCast(u8, 0x40 | @intCast(u16, sh) | 0x06));
        checkByte("cb bit hl keeps", mmumod.read8(&g_bus, 0xC110), mask);
        checkFlags("cb bit hl set flags", false, false, false, true);
        checkCycles("cb bit hl cycles", hl_cycles, 12);

        reset();
        g_cpu.h = 0xC1;
        g_cpu.l = 0x10;
        mmumod.write8(&g_bus, 0xC110, 0);
        g_cpu.f = FLAG_N | FLAG_H | FLAG_C;
        _ = runCbC(CODE, @intCast(u8, 0x40 | @intCast(u16, sh) | 0x06));
        checkFlags("cb bit hl clear flags", true, false, false, true);
    }
}

fn testCbResSet() void {
    var bit: u8 = 0;
    while (bit < 8) : (bit += 1) {
        const sh: u8 = @intCast(u8, (@intCast(u16, bit) << 3) & 0x38);
        const mask: u16 = cbMask(bit);
        const mask8: u8 = @intCast(u8, mask);
        const cleared: u8 = @intCast(u8, @intCast(u16, 0xFF) & ~mask);

        reset();
        g_cpu.b = 0xFF;
        g_cpu.f = 0xF0;
        const res_reg_cycles: u32 = runCbC(CODE, @intCast(u8, 0x80 | @intCast(u16, sh)));
        checkByte("cb res reg", g_cpu.b, cleared);
        checkFlags("cb res reg flags", true, true, true, true);
        checkCycles("cb res reg cycles", res_reg_cycles, 8);

        reset();
        g_cpu.h = 0xC1;
        g_cpu.l = 0x20;
        mmumod.write8(&g_bus, 0xC120, 0xFF);
        g_cpu.f = 0xF0;
        const res_hl_cycles: u32 = runCbC(CODE, @intCast(u8, 0x80 | @intCast(u16, sh) | 0x06));
        checkByte("cb res hl", mmumod.read8(&g_bus, 0xC120), cleared);
        checkFlags("cb res hl flags", true, true, true, true);
        checkCycles("cb res hl cycles", res_hl_cycles, 16);

        reset();
        g_cpu.b = 0x00;
        g_cpu.f = 0xF0;
        const set_reg_cycles: u32 = runCbC(CODE, @intCast(u8, 0xC0 | @intCast(u16, sh)));
        checkByte("cb set reg", g_cpu.b, mask8);
        checkFlags("cb set reg flags", true, true, true, true);
        checkCycles("cb set reg cycles", set_reg_cycles, 8);

        reset();
        g_cpu.h = 0xC1;
        g_cpu.l = 0x20;
        mmumod.write8(&g_bus, 0xC120, 0x00);
        g_cpu.f = 0xF0;
        const set_hl_cycles: u32 = runCbC(CODE, @intCast(u8, 0xC0 | @intCast(u16, sh) | 0x06));
        checkByte("cb set hl", mmumod.read8(&g_bus, 0xC120), mask8);
        checkFlags("cb set hl flags", true, true, true, true);
        checkCycles("cb set hl cycles", set_hl_cycles, 16);
    }
}

fn testCbBoundaries() void {
    reset();
    g_cpu.b = 0x80;
    g_cpu.f = 0;
    const c00: u32 = runCbC(CODE, 0x00);
    checkByte("cb 0x00 result", g_cpu.b, 0x01);
    checkFlags("cb 0x00 flags", false, false, false, true);
    checkCycles("cb 0x00 cycles", c00, 8);
    checkWord("cb 0x00 prefix pc", g_cpu.pc, CODE +% 2);

    reset();
    g_cpu.a = 0x01;
    g_cpu.f = 0;
    const c3f: u32 = runCbC(CODE, 0x3F);
    checkByte("cb 0x3F result", g_cpu.a, 0x00);
    checkFlags("cb 0x3F flags", true, false, false, true);
    checkCycles("cb 0x3F cycles", c3f, 8);

    reset();
    g_cpu.a = 0x80;
    g_cpu.f = FLAG_C;
    const c7f: u32 = runCbC(CODE, 0x7F);
    checkByte("cb 0x7F keeps a", g_cpu.a, 0x80);
    checkFlags("cb 0x7F flags", false, false, false, true);
    checkCycles("cb 0x7F cycles", c7f, 8);

    reset();
    g_cpu.b = 0xFF;
    g_cpu.f = 0xF0;
    const c80: u32 = runCbC(CODE, 0x80);
    checkByte("cb 0x80 result", g_cpu.b, 0xFE);
    checkFlags("cb 0x80 flags", true, true, true, true);
    checkCycles("cb 0x80 cycles", c80, 8);

    reset();
    g_cpu.a = 0x00;
    g_cpu.f = 0xF0;
    const cff: u32 = runCbC(CODE, 0xFF);
    checkByte("cb 0xFF result", g_cpu.a, 0x80);
    checkFlags("cb 0xFF flags", true, true, true, true);
    checkCycles("cb 0xFF cycles", cff, 8);
    checkWord("cb 0xFF prefix pc", g_cpu.pc, CODE +% 2);
}

pub fn main() void {
    testAlu();
    testIncDec();
    testDaa();
    testRotates();
    testCbRotates();
    testCbAllRegs();
    testCbBit();
    testCbResSet();
    testCbBoundaries();
    testMisc();
    testSpOffset();
    testLoads();
    testImmediateAlu();
    testStack();
    testJumps();
    testCalls();

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
