// cpu.zig — z9gb SM83 base, ALU, flags, DAA, loads, stack, and control flow.
//
// Flags live in F bits 7..4: Z=0x80, N=0x40, H=0x20, C=0x10. Bits 3..0 are
// always zero. Arithmetic widens to u16 before shifting/masking and narrows
// explicitly, so the module is clean under both -ffast and -fsafe.

const mmumod = @import("mmu.zig");

pub const Bus = mmumod.Bus;

const FLAG_Z: u8 = 0x80;
const FLAG_N: u8 = 0x40;
const FLAG_H: u8 = 0x20;
const FLAG_C: u8 = 0x10;

pub const Cpu = struct {
    a: u8,
    f: u8,
    b: u8,
    c: u8,
    d: u8,
    e: u8,
    h: u8,
    l: u8,
    sp: u16,
    pc: u16,
    ime: bool,
    halted: bool,
    halt_bug: bool,
    cycles: u64,
};

pub fn cpuInit(cpu: *Cpu) void {
    cpu.a = 0;
    cpu.f = 0;
    cpu.b = 0;
    cpu.c = 0;
    cpu.d = 0;
    cpu.e = 0;
    cpu.h = 0;
    cpu.l = 0;
    cpu.sp = 0;
    cpu.pc = 0;
    cpu.ime = false;
    cpu.halted = false;
    cpu.halt_bug = false;
    cpu.cycles = 0;
}

pub fn cpuSetBus(cpu: *Cpu, bus: *Bus) void {
    _ = cpu;
    _ = bus;
}

fn getFlag(cpu: *const Cpu, mask: u8) bool {
    return (cpu.f & mask) != 0;
}

fn setFlag(cpu: *Cpu, mask: u8, on: bool) void {
    if (on) {
        cpu.f |= mask;
    } else {
        cpu.f &= @intCast(u8, ~mask);
    }
}

fn setFlags(cpu: *Cpu, z: bool, n: bool, h: bool, c: bool) void {
    var f: u8 = 0;
    if (z) f |= FLAG_Z;
    if (n) f |= FLAG_N;
    if (h) f |= FLAG_H;
    if (c) f |= FLAG_C;
    cpu.f = f;
}

fn hlValue(cpu: *const Cpu) u16 {
    const h: u16 = @intCast(u16, cpu.h);
    const l: u16 = @intCast(u16, cpu.l);
    return (h << 8) | l;
}

fn setHl(cpu: *Cpu, value: u16) void {
    cpu.h = @intCast(u8, value >> 8);
    cpu.l = @intCast(u8, value & 0xFF);
}

fn readReg(cpu: *const Cpu, idx: u8) u8 {
    switch (idx) {
        0 => return cpu.b,
        1 => return cpu.c,
        2 => return cpu.d,
        3 => return cpu.e,
        4 => return cpu.h,
        5 => return cpu.l,
        7 => return cpu.a,
        else => unreachable,
    }
}

fn writeReg(cpu: *Cpu, idx: u8, value: u8) void {
    switch (idx) {
        0 => cpu.b = value,
        1 => cpu.c = value,
        2 => cpu.d = value,
        3 => cpu.e = value,
        4 => cpu.h = value,
        5 => cpu.l = value,
        7 => cpu.a = value,
        else => unreachable,
    }
}

fn add8(cpu: *Cpu, x: u8, y: u8, carry: u8) u8 {
    const ux: u16 = @intCast(u16, x);
    const uy: u16 = @intCast(u16, y);
    const uc: u16 = @intCast(u16, carry);
    const sum: u16 = ux + uy + uc;
    const r: u8 = @intCast(u8, sum & 0xFF);
    const h: bool = ((ux & 0x0F) + (uy & 0x0F) + uc) > 0x0F;
    const c: bool = sum > 0xFF;
    setFlags(cpu, r == 0, false, h, c);
    return r;
}

fn sub8(cpu: *Cpu, x: u8, y: u8, carry: u8) u8 {
    const ux: u16 = @intCast(u16, x);
    const uy: u16 = @intCast(u16, y);
    const uc: u16 = @intCast(u16, carry);
    const diff: u16 = (ux + 0x100) - uy - uc;
    const r: u8 = @intCast(u8, diff & 0xFF);
    const h: bool = (ux & 0x0F) < ((uy & 0x0F) + uc);
    const c: bool = ux < (uy + uc);
    setFlags(cpu, r == 0, true, h, c);
    return r;
}

fn and8(cpu: *Cpu, x: u8, y: u8) u8 {
    const r: u8 = x & y;
    setFlags(cpu, r == 0, false, true, false);
    return r;
}

fn xor8(cpu: *Cpu, x: u8, y: u8) u8 {
    const r: u8 = x ^ y;
    setFlags(cpu, r == 0, false, false, false);
    return r;
}

fn or8(cpu: *Cpu, x: u8, y: u8) u8 {
    const r: u8 = x | y;
    setFlags(cpu, r == 0, false, false, false);
    return r;
}

fn cp8(cpu: *Cpu, x: u8, y: u8) void {
    _ = sub8(cpu, x, y, 0);
}

fn inc8(cpu: *Cpu, x: u8) u8 {
    const c: bool = getFlag(cpu, FLAG_C);
    const ux: u16 = @intCast(u16, x);
    const r: u8 = @intCast(u8, (ux + 1) & 0xFF);
    const h: bool = ((ux & 0x0F) + 1) > 0x0F;
    setFlags(cpu, r == 0, false, h, c);
    return r;
}

fn dec8(cpu: *Cpu, x: u8) u8 {
    const c: bool = getFlag(cpu, FLAG_C);
    const ux: u16 = @intCast(u16, x);
    const r: u8 = @intCast(u8, (ux + 0xFF) & 0xFF);
    const h: bool = (ux & 0x0F) == 0;
    setFlags(cpu, r == 0, true, h, c);
    return r;
}

fn daa(cpu: *Cpu) void {
    const a: u16 = @intCast(u16, cpu.a);
    const n: bool = getFlag(cpu, FLAG_N);
    const h: bool = getFlag(cpu, FLAG_H);
    var carry: bool = getFlag(cpu, FLAG_C);
    var adjust: u16 = 0;

    if (h or (!n and (a & 0x0F) > 9)) adjust |= 0x06;
    if (carry or (!n and a > 0x99)) {
        adjust |= 0x60;
        carry = true;
    }

    const result: u16 = if (n) (a + 0x100) - adjust else a + adjust;
    const r: u8 = @intCast(u8, result & 0xFF);
    cpu.a = r;
    setFlags(cpu, r == 0, n, false, carry);
}

fn rlca(cpu: *Cpu) void {
    const a: u16 = @intCast(u16, cpu.a);
    const carry: bool = (a & 0x80) != 0;
    const bit: u16 = if (carry) 1 else 0;
    const r: u8 = @intCast(u8, ((a << 1) | bit) & 0xFF);
    cpu.a = r;
    setFlags(cpu, false, false, false, carry);
}

fn rrca(cpu: *Cpu) void {
    const a: u16 = @intCast(u16, cpu.a);
    const carry: bool = (a & 0x01) != 0;
    const bit: u16 = if (carry) 0x80 else 0;
    const r: u8 = @intCast(u8, ((a >> 1) | bit) & 0xFF);
    cpu.a = r;
    setFlags(cpu, false, false, false, carry);
}

fn rla(cpu: *Cpu) void {
    const a: u16 = @intCast(u16, cpu.a);
    const old_c: bool = getFlag(cpu, FLAG_C);
    const carry: bool = (a & 0x80) != 0;
    const bit: u16 = if (old_c) 1 else 0;
    const r: u8 = @intCast(u8, ((a << 1) | bit) & 0xFF);
    cpu.a = r;
    setFlags(cpu, false, false, false, carry);
}

fn rra(cpu: *Cpu) void {
    const a: u16 = @intCast(u16, cpu.a);
    const old_c: bool = getFlag(cpu, FLAG_C);
    const carry: bool = (a & 0x01) != 0;
    const bit: u16 = if (old_c) 0x80 else 0;
    const r: u8 = @intCast(u8, ((a >> 1) | bit) & 0xFF);
    cpu.a = r;
    setFlags(cpu, false, false, false, carry);
}

fn signedOffset(value: u8) u16 {
    if (value < 0x80) return @intCast(u16, value);
    return @intCast(u16, value) + 0xFF00;
}

fn spOffsetFlags(cpu: *Cpu, e: u8) void {
    const sp: u16 = cpu.sp;
    const low: u16 = (sp & 0x0F) + (@intCast(u16, e) & 0x0F);
    const byte: u16 = (sp & 0xFF) + @intCast(u16, e);
    setFlags(cpu, false, false, low > 0x0F, byte > 0xFF);
}

fn aluOperand(cpu: *const Cpu, bus: *Bus, idx: u8) u8 {
    if (idx == 6) return mmumod.read8(bus, hlValue(cpu));
    return readReg(cpu, idx);
}

fn aluStore(cpu: *Cpu, bus: *Bus, idx: u8, value: u8) void {
    if (idx == 6) {
        mmumod.write8(bus, hlValue(cpu), value);
    } else {
        writeReg(cpu, idx, value);
    }
}

fn incReg(cpu: *Cpu, bus: *Bus, idx: u8) void {
    const value: u8 = aluOperand(cpu, bus, idx);
    aluStore(cpu, bus, idx, inc8(cpu, value));
}

fn decReg(cpu: *Cpu, bus: *Bus, idx: u8) void {
    const value: u8 = aluOperand(cpu, bus, idx);
    aluStore(cpu, bus, idx, dec8(cpu, value));
}

fn readReg16(cpu: *const Cpu, idx: u8) u16 {
    switch (idx) {
        0 => {
            const b: u16 = @intCast(u16, cpu.b);
            const c: u16 = @intCast(u16, cpu.c);
            return (b << 8) | c;
        },
        1 => {
            const d: u16 = @intCast(u16, cpu.d);
            const e: u16 = @intCast(u16, cpu.e);
            return (d << 8) | e;
        },
        2 => return hlValue(cpu),
        3 => return cpu.sp,
        else => unreachable,
    }
}

fn writeReg16(cpu: *Cpu, idx: u8, value: u16) void {
    switch (idx) {
        0 => {
            cpu.b = @intCast(u8, value >> 8);
            cpu.c = @intCast(u8, value & 0xFF);
        },
        1 => {
            cpu.d = @intCast(u8, value >> 8);
            cpu.e = @intCast(u8, value & 0xFF);
        },
        2 => setHl(cpu, value),
        3 => cpu.sp = value,
        else => unreachable,
    }
}

fn ldReg16Imm(cpu: *Cpu, bus: *Bus, idx: u8) void {
    const value: u16 = mmumod.read16(bus, cpu.pc);
    cpu.pc = cpu.pc +% 2;
    writeReg16(cpu, idx, value);
}

fn incReg16(cpu: *Cpu, idx: u8) void {
    writeReg16(cpu, idx, readReg16(cpu, idx) +% 1);
}

fn decReg16(cpu: *Cpu, idx: u8) void {
    writeReg16(cpu, idx, readReg16(cpu, idx) -% 1);
}

fn addHl(cpu: *Cpu, value: u16) void {
    const x: u32 = @intCast(u32, hlValue(cpu));
    const y: u32 = @intCast(u32, value);
    const sum: u32 = x + y;
    const h: bool = ((x & 0xFFF) + (y & 0xFFF)) > 0xFFF;
    const c: bool = sum > 0xFFFF;
    setFlag(cpu, FLAG_N, false);
    setFlag(cpu, FLAG_H, h);
    setFlag(cpu, FLAG_C, c);
    setHl(cpu, @intCast(u16, sum & 0xFFFF));
}

fn push16(cpu: *Cpu, bus: *Bus, value: u16) void {
    cpu.sp = cpu.sp -% 2;
    mmumod.write16(bus, cpu.sp, value);
}

fn pop16(cpu: *Cpu, bus: *Bus) u16 {
    const value: u16 = mmumod.read16(bus, cpu.sp);
    cpu.sp = cpu.sp +% 2;
    return value;
}

fn condition(cpu: *const Cpu, cc: u8) bool {
    switch (cc) {
        0 => return !getFlag(cpu, FLAG_Z),
        1 => return getFlag(cpu, FLAG_Z),
        2 => return !getFlag(cpu, FLAG_C),
        3 => return getFlag(cpu, FLAG_C),
        else => unreachable,
    }
}

fn condCode(op: u8) u8 {
    return @intCast(u8, (@intCast(u16, op) >> 3) & 0x03);
}

fn ldRegImm(cpu: *Cpu, bus: *Bus, idx: u8) void {
    const value: u8 = mmumod.read8(bus, cpu.pc);
    cpu.pc = cpu.pc +% 1;
    aluStore(cpu, bus, idx, value);
}

fn aluGroup(cpu: *Cpu, bus: *Bus, group: u16, idx: u8) void {
    const value: u8 = aluOperand(cpu, bus, idx);
    switch (group) {
        0x00 => cpu.a = add8(cpu, cpu.a, value, 0),
        0x08 => {
            const carry: u8 = if (getFlag(cpu, FLAG_C)) 1 else 0;
            cpu.a = add8(cpu, cpu.a, value, carry);
        },
        0x10 => cpu.a = sub8(cpu, cpu.a, value, 0),
        0x18 => {
            const carry: u8 = if (getFlag(cpu, FLAG_C)) 1 else 0;
            cpu.a = sub8(cpu, cpu.a, value, carry);
        },
        0x20 => cpu.a = and8(cpu, cpu.a, value),
        0x28 => cpu.a = xor8(cpu, cpu.a, value),
        0x30 => cpu.a = or8(cpu, cpu.a, value),
        0x38 => cp8(cpu, cpu.a, value),
        else => unreachable,
    }
}

const OP_LEN: [256]u8 = [256]u8{
    1, 3, 1, 1, 1, 1, 2, 1, 3, 1, 1, 1, 1, 1, 2, 1,
    1, 3, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 2, 1,
    2, 3, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 2, 1,
    2, 3, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 2, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 3, 3, 3, 1, 2, 1, 1, 1, 3, 2, 3, 3, 2, 1,
    1, 1, 3, 1, 3, 1, 2, 1, 1, 1, 3, 1, 3, 1, 2, 1,
    2, 1, 1, 1, 1, 1, 2, 1, 2, 1, 3, 1, 1, 1, 2, 1,
    2, 1, 1, 1, 1, 1, 2, 1, 2, 1, 3, 1, 1, 1, 2, 1,
};

const OP_CYCLES: [256]u8 = [256]u8{
    4, 12, 8, 8, 4, 4, 8, 4, 20, 8, 8, 8, 4, 4, 8, 4,
    4, 12, 8, 8, 4, 4, 8, 4, 12, 8, 8, 8, 4, 4, 8, 4,
    8, 12, 8, 8, 4, 4, 8, 4, 8, 8, 8, 8, 4, 4, 8, 4,
    8, 12, 8, 8, 12, 12, 12, 4, 8, 8, 8, 8, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    8, 8, 8, 8, 8, 8, 4, 8, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    4, 4, 4, 4, 4, 4, 8, 4, 4, 4, 4, 4, 4, 4, 8, 4,
    8, 12, 12, 16, 12, 16, 8, 16, 8, 16, 12, 4, 12, 24, 8, 16,
    8, 12, 12, 4, 12, 16, 8, 16, 8, 16, 12, 4, 12, 4, 8, 16,
    12, 12, 8, 4, 4, 16, 8, 16, 16, 4, 16, 4, 4, 4, 8, 16,
    12, 12, 8, 4, 4, 16, 8, 16, 12, 8, 16, 4, 4, 4, 8, 16,
};

pub fn cpuStep(cpu: *Cpu, bus: *Bus) u32 {
    const op: u8 = mmumod.read8(bus, cpu.pc);
    cpu.pc = cpu.pc +% 1;
    const cycles: u32 = @intCast(u32, OP_CYCLES[@intCast(usize, op)]);

    switch (op) {
        0x00 => {},
        0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C => {
            const idx: u8 = @intCast(u8, (@intCast(u16, op) >> 3) & 0x07);
            incReg(cpu, bus, idx);
        },
        0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D => {
            const idx: u8 = @intCast(u8, (@intCast(u16, op) >> 3) & 0x07);
            decReg(cpu, bus, idx);
        },
        0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E => {
            const idx: u8 = @intCast(u8, (@intCast(u16, op) >> 3) & 0x07);
            ldRegImm(cpu, bus, idx);
        },
        0x07 => rlca(cpu),
        0x0F => rrca(cpu),
        0x17 => rla(cpu),
        0x1F => rra(cpu),
        0x27 => daa(cpu),
        0x2F => {
            cpu.a = @intCast(u8, ~cpu.a);
            setFlag(cpu, FLAG_N, true);
            setFlag(cpu, FLAG_H, true);
        },
        0x37 => {
            setFlag(cpu, FLAG_N, false);
            setFlag(cpu, FLAG_H, false);
            setFlag(cpu, FLAG_C, true);
        },
        0x3F => {
            const old_c: bool = getFlag(cpu, FLAG_C);
            setFlag(cpu, FLAG_N, false);
            setFlag(cpu, FLAG_H, false);
            setFlag(cpu, FLAG_C, !old_c);
        },
        0x80...0xBF => {
            const group: u16 = @intCast(u16, op) & 0x38;
            const idx: u8 = op & 0x07;
            aluGroup(cpu, bus, group, idx);
        },
        0x01, 0x11, 0x21, 0x31 => {
            const rr: u8 = @intCast(u8, (@intCast(u16, op) >> 4) & 0x03);
            ldReg16Imm(cpu, bus, rr);
        },
        0x02, 0x12, 0x22, 0x32 => {
            const which: u8 = @intCast(u8, (@intCast(u16, op) >> 4) & 0x03);
            const addr_hl: u16 = hlValue(cpu);
            var addr: u16 = addr_hl;
            if (which == 0) addr = readReg16(cpu, 0);
            if (which == 1) addr = readReg16(cpu, 1);
            mmumod.write8(bus, addr, cpu.a);
            if (which == 2) setHl(cpu, addr_hl +% 1);
            if (which == 3) setHl(cpu, addr_hl -% 1);
        },
        0x0A, 0x1A, 0x2A, 0x3A => {
            const which: u8 = @intCast(u8, (@intCast(u16, op) >> 4) & 0x03);
            const addr_hl: u16 = hlValue(cpu);
            var addr: u16 = addr_hl;
            if (which == 0) addr = readReg16(cpu, 0);
            if (which == 1) addr = readReg16(cpu, 1);
            cpu.a = mmumod.read8(bus, addr);
            if (which == 2) setHl(cpu, addr_hl +% 1);
            if (which == 3) setHl(cpu, addr_hl -% 1);
        },
        0x03, 0x13, 0x23, 0x33 => {
            const rr: u8 = @intCast(u8, (@intCast(u16, op) >> 4) & 0x03);
            incReg16(cpu, rr);
        },
        0x0B, 0x1B, 0x2B, 0x3B => {
            const rr: u8 = @intCast(u8, (@intCast(u16, op) >> 4) & 0x03);
            decReg16(cpu, rr);
        },
        0x08 => {
            const addr: u16 = mmumod.read16(bus, cpu.pc);
            cpu.pc = cpu.pc +% 2;
            mmumod.write16(bus, addr, cpu.sp);
        },
        0x09, 0x19, 0x29, 0x39 => {
            const rr: u8 = @intCast(u8, (@intCast(u16, op) >> 4) & 0x03);
            addHl(cpu, readReg16(cpu, rr));
        },
        0x18 => {
            const e: u8 = mmumod.read8(bus, cpu.pc);
            cpu.pc = cpu.pc +% 1;
            cpu.pc = cpu.pc +% signedOffset(e);
        },
        0x20, 0x28, 0x30, 0x38 => {
            const e: u8 = mmumod.read8(bus, cpu.pc);
            cpu.pc = cpu.pc +% 1;
            if (condition(cpu, condCode(op))) cpu.pc = cpu.pc +% signedOffset(e);
        },
        0x40...0x7F => {
            if (op != 0x76) {
                const dst: u8 = @intCast(u8, (@intCast(u16, op) >> 3) & 0x07);
                const src: u8 = op & 0x07;
                aluStore(cpu, bus, dst, aluOperand(cpu, bus, src));
            } else {
                unreachable;
            }
        },
        0xC0, 0xC8, 0xD0, 0xD8 => {
            if (condition(cpu, condCode(op))) cpu.pc = pop16(cpu, bus);
        },
        0xC1, 0xD1, 0xE1, 0xF1 => {
            const rr: u8 = @intCast(u8, (@intCast(u16, op) >> 4) & 0x03);
            const value: u16 = pop16(cpu, bus);
            if (rr == 3) {
                cpu.a = @intCast(u8, value >> 8);
                cpu.f = @intCast(u8, value & 0xF0);
            } else {
                writeReg16(cpu, rr, value);
            }
        },
        0xC2, 0xCA, 0xD2, 0xDA => {
            const dest: u16 = mmumod.read16(bus, cpu.pc);
            if (condition(cpu, condCode(op))) {
                cpu.pc = dest;
            } else {
                cpu.pc = cpu.pc +% 2;
            }
        },
        0xC3 => {
            cpu.pc = mmumod.read16(bus, cpu.pc);
        },
        0xC4, 0xCC, 0xD4, 0xDC => {
            const dest: u16 = mmumod.read16(bus, cpu.pc);
            cpu.pc = cpu.pc +% 2;
            if (condition(cpu, condCode(op))) {
                push16(cpu, bus, cpu.pc);
                cpu.pc = dest;
            }
        },
        0xC5, 0xD5, 0xE5, 0xF5 => {
            const rr: u8 = @intCast(u8, (@intCast(u16, op) >> 4) & 0x03);
            var value: u16 = 0;
            if (rr == 3) {
                const a: u16 = @intCast(u16, cpu.a);
                const f: u16 = @intCast(u16, cpu.f & 0xF0);
                value = (a << 8) | f;
            } else {
                value = readReg16(cpu, rr);
            }
            push16(cpu, bus, value);
        },
        0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF => {
            const vec: u16 = @intCast(u16, op) & 0x0038;
            push16(cpu, bus, cpu.pc);
            cpu.pc = vec;
        },
        0xC9 => {
            cpu.pc = pop16(cpu, bus);
        },
        0xCD => {
            const dest: u16 = mmumod.read16(bus, cpu.pc);
            cpu.pc = cpu.pc +% 2;
            push16(cpu, bus, cpu.pc);
            cpu.pc = dest;
        },
        0xD9 => {
            cpu.pc = pop16(cpu, bus);
            cpu.ime = true;
        },
        0xE0 => {
            const a8: u8 = mmumod.read8(bus, cpu.pc);
            cpu.pc = cpu.pc +% 1;
            mmumod.write8(bus, 0xFF00 +% @intCast(u16, a8), cpu.a);
        },
        0xE2 => {
            mmumod.write8(bus, 0xFF00 +% @intCast(u16, cpu.c), cpu.a);
        },
        0xE9 => {
            cpu.pc = hlValue(cpu);
        },
        0xEA => {
            const addr: u16 = mmumod.read16(bus, cpu.pc);
            cpu.pc = cpu.pc +% 2;
            mmumod.write8(bus, addr, cpu.a);
        },
        0xF0 => {
            const a8: u8 = mmumod.read8(bus, cpu.pc);
            cpu.pc = cpu.pc +% 1;
            cpu.a = mmumod.read8(bus, 0xFF00 +% @intCast(u16, a8));
        },
        0xF2 => {
            cpu.a = mmumod.read8(bus, 0xFF00 +% @intCast(u16, cpu.c));
        },
        0xFA => {
            const addr: u16 = mmumod.read16(bus, cpu.pc);
            cpu.pc = cpu.pc +% 2;
            cpu.a = mmumod.read8(bus, addr);
        },
        0xE8 => {
            const e: u8 = mmumod.read8(bus, cpu.pc);
            cpu.pc = cpu.pc +% 1;
            const result: u16 = cpu.sp +% signedOffset(e);
            spOffsetFlags(cpu, e);
            cpu.sp = result;
        },
        0xF8 => {
            const e: u8 = mmumod.read8(bus, cpu.pc);
            cpu.pc = cpu.pc +% 1;
            const result: u16 = cpu.sp +% signedOffset(e);
            spOffsetFlags(cpu, e);
            setHl(cpu, result);
        },
        else => unreachable,
    }

    cpu.cycles +%= @intCast(u64, cycles);
    return cycles;
}
