// block.zig — SM83 basic-block IR builder for the z9gb dynarec.
//
// BlockInsn field contract:
//   nop        a/b/imm unused.
//   ld_rr      a=rr (0 BC, 1 DE, 2 HL, 3 SP), b=0 (imm16) or 1 (LD SP,HL).
//   ld_rn      a=dst r index 0..7, imm=imm8.
//   ld_mem     a=kind 0..7 (LD r,r'; b=src index), 8..11 (BC/DE/HL+/HL-;
//              b=0 store A, b=1 load A), 12 LDH(a8), 13 (a16), 14 (a16),SP,
//              15 (C); imm=address where present.
//   alu_r      a=group 0..7 (ADD/ADC/SUB/SBC/AND/XOR/OR/CP), b=src index;
//              a=8 is ADD HL,rr with b=rr.
//   alu_n      a=group 0..7, imm=imm8.
//   incdec     a=index (0..7 byte, 0..3 pair), b bit0=dec, bit7=16-bit.
//   jump       a=cc 0..3 or 4 unconditional or 5 JP HL, b=0 JP a16 / 1 JR e /
//              2 JP HL, imm=absolute target.
//   call       a=cc 0..3 or 4 unconditional or 5 RST, b=0 CALL a16 / 1 RST,
//              imm=absolute target.
//   ret        a=cc 0..3 or 4 unconditional, b=0 RET / 1 RETI.
//   cb         a=second opcode byte.
//   unsupported a=raw opcode; the instruction is a fallback boundary.

const mmumod = @import("../mmu.zig");
const cpumod = @import("../cpu.zig");

pub const Cpu = cpumod.Cpu;
pub const Bus = mmumod.Bus;

pub const BlockOp = enum(u8) { nop, ld_rr, ld_rn, ld_mem, alu_r, alu_n, incdec, jump, call, ret, cb, unsupported };

pub const BlockInsn = struct { op: BlockOp, a: u8, b: u8, imm: u16 };

pub const Block = struct { insns: [64]BlockInsn, len: u8, start_pc: u16, cycles: u32, ends_block: bool };

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

fn readU16(bus: *Bus, addr: u16) u16 {
    const lo: u16 = @intCast(u16, mmumod.read8(bus, addr));
    const hi: u16 = @intCast(u16, mmumod.read8(bus, addr +% 1));
    return lo | (hi << 8);
}

fn regIndex(op: u8) u8 {
    return @intCast(u8, (@intCast(u16, op) >> 3) & 0x07);
}

fn pairIndex(op: u8) u8 {
    return @intCast(u8, (@intCast(u16, op) >> 4) & 0x03);
}

fn condCode(op: u8) u8 {
    return @intCast(u8, (@intCast(u16, op) >> 3) & 0x03);
}

fn signedOffset(value: u8) u16 {
    if (value < 0x80) return @intCast(u16, value);
    return @intCast(u16, value) + 0xFF00;
}

fn jumpTarget(pc: u16, offset: u8) u16 {
    return (pc +% 2) +% signedOffset(offset);
}

fn opLength(op: u8) u8 {
    switch (op) {
        0x10, 0xCB => return 2,
        0x18, 0x20, 0x28, 0x30, 0x38 => return 2,
        0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E => return 2,
        0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE => return 2,
        0xE0, 0xF0, 0xE8, 0xF8 => return 2,
        0x01, 0x11, 0x21, 0x31 => return 3,
        0xC2, 0xC3, 0xCA, 0xD2, 0xDA => return 3,
        0xC4, 0xCC, 0xCD, 0xD4, 0xDC => return 3,
        0x08, 0xEA, 0xFA => return 3,
        else => return 1,
    }
}

fn cbCycles(op2: u8) u32 {
    const idx: u8 = op2 & 0x07;
    if (op2 <= 0x3F) return if (idx == 6) 16 else 8;
    if (op2 <= 0x7F) return if (idx == 6) 12 else 8;
    return if (idx == 6) 16 else 8;
}

fn writeEnds(op: u8, imm: u16) bool {
    switch (op) {
        0xE0, 0xE2 => return true,
        0x08, 0xEA => return imm < 0x8000 or imm >= 0xFF00,
        else => return false,
    }
}

pub fn blockBuild(cpu: *const Cpu, bus: *Bus, out: *Block) bool {
    out.start_pc = cpu.pc;
    out.len = 0;
    out.cycles = 0;
    out.ends_block = false;
    var pc: u16 = cpu.pc;
    var source: u32 = 0;
    while (out.len < 64 and source < 4096) {
        const op: u8 = mmumod.read8(bus, pc);
        const len: u8 = opLength(op);
        const add: u32 = @intCast(u32, len);
        if (source + add > 4096) break;

        var insn: BlockInsn = BlockInsn{ .op = .unsupported, .a = op, .b = 0, .imm = 0 };
        var cycles: u32 = @intCast(u32, OP_CYCLES[@intCast(usize, op)]);
        var terminal: bool = false;

        switch (op) {
            0x00 => {
                insn.op = .nop;
            },
            0x01, 0x11, 0x21, 0x31 => {
                insn.op = .ld_rr;
                insn.a = pairIndex(op);
                insn.b = 0;
                insn.imm = readU16(bus, pc +% 1);
            },
            0x02, 0x12, 0x22, 0x32 => {
                insn.op = .ld_mem;
                insn.a = @intCast(u8, 8 + ((@intCast(u16, op) >> 4) & 0x03));
                insn.b = 0;
                terminal = true;
            },
            0x03, 0x13, 0x23, 0x33 => {
                insn.op = .incdec;
                insn.a = pairIndex(op);
                insn.b = 0x80;
            },
            0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C => {
                insn.op = .incdec;
                insn.a = regIndex(op);
                insn.b = 0;
                if (insn.a == 6) terminal = true;
            },
            0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D => {
                insn.op = .incdec;
                insn.a = regIndex(op);
                insn.b = 1;
                if (insn.a == 6) terminal = true;
            },
            0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E => {
                insn.op = .ld_rn;
                insn.a = regIndex(op);
                insn.imm = @intCast(u16, mmumod.read8(bus, pc +% 1));
                if (insn.a == 6) terminal = true;
            },
            0x08 => {
                insn.op = .ld_mem;
                insn.a = 14;
                insn.b = 0;
                insn.imm = readU16(bus, pc +% 1);
                if (writeEnds(op, insn.imm)) terminal = true;
            },
            0x09, 0x19, 0x29, 0x39 => {
                insn.op = .alu_r;
                insn.a = 8;
                insn.b = pairIndex(op);
            },
            0x0A, 0x1A, 0x2A, 0x3A => {
                insn.op = .ld_mem;
                insn.a = @intCast(u8, 8 + ((@intCast(u16, op) >> 4) & 0x03));
                insn.b = 1;
            },
            0x0B, 0x1B, 0x2B, 0x3B => {
                insn.op = .incdec;
                insn.a = pairIndex(op);
                insn.b = 0x81;
            },
            0x18 => {
                const e: u8 = mmumod.read8(bus, pc +% 1);
                insn.op = .jump;
                insn.a = 4;
                insn.b = 1;
                insn.imm = jumpTarget(pc, e);
                terminal = true;
            },
            0x20, 0x28, 0x30, 0x38 => {
                const e: u8 = mmumod.read8(bus, pc +% 1);
                insn.op = .jump;
                insn.a = condCode(op);
                insn.b = 1;
                insn.imm = jumpTarget(pc, e);
                terminal = true;
            },
            0x40...0x7F => {
                if (op == 0x76) {
                    terminal = true;
                } else {
                    insn.op = .ld_mem;
                    insn.a = regIndex(op);
                    insn.b = op & 0x07;
                    if (insn.a == 6) terminal = true;
                }
            },
            0x80...0xBF => {
                insn.op = .alu_r;
                insn.a = @intCast(u8, (@intCast(u16, op) >> 3) & 0x07);
                insn.b = op & 0x07;
            },
            0xC0, 0xC8, 0xD0, 0xD8 => {
                insn.op = .ret;
                insn.a = condCode(op);
                insn.b = 0;
                terminal = true;
            },
            0xC2, 0xCA, 0xD2, 0xDA => {
                insn.op = .jump;
                insn.a = condCode(op);
                insn.b = 0;
                insn.imm = readU16(bus, pc +% 1);
                terminal = true;
            },
            0xC3 => {
                insn.op = .jump;
                insn.a = 4;
                insn.b = 0;
                insn.imm = readU16(bus, pc +% 1);
                terminal = true;
            },
            0xC4, 0xCC, 0xD4, 0xDC => {
                insn.op = .call;
                insn.a = condCode(op);
                insn.b = 0;
                insn.imm = readU16(bus, pc +% 1);
                terminal = true;
            },
            0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE => {
                insn.op = .alu_n;
                insn.a = @intCast(u8, (@intCast(u16, op) >> 3) & 0x07);
                insn.imm = @intCast(u16, mmumod.read8(bus, pc +% 1));
            },
            0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF => {
                insn.op = .call;
                insn.a = 5;
                insn.b = 1;
                insn.imm = @intCast(u16, op) & 0x38;
                terminal = true;
            },
            0xC9 => {
                insn.op = .ret;
                insn.a = 4;
                insn.b = 0;
                terminal = true;
            },
            0xCB => {
                const op2: u8 = mmumod.read8(bus, pc +% 1);
                insn.op = .cb;
                insn.a = op2;
                cycles = cbCycles(op2);
            },
            0xCD => {
                insn.op = .call;
                insn.a = 4;
                insn.b = 0;
                insn.imm = readU16(bus, pc +% 1);
                terminal = true;
            },
            0xD9 => {
                insn.op = .ret;
                insn.a = 4;
                insn.b = 1;
                terminal = true;
            },
            0xE0 => {
                insn.op = .ld_mem;
                insn.a = 12;
                insn.b = 0;
                insn.imm = @intCast(u16, mmumod.read8(bus, pc +% 1));
                terminal = true;
            },
            0xE2 => {
                insn.op = .ld_mem;
                insn.a = 15;
                insn.b = 0;
                terminal = true;
            },
            0xE9 => {
                insn.op = .jump;
                insn.a = 5;
                insn.b = 2;
                terminal = true;
            },
            0xEA => {
                insn.op = .ld_mem;
                insn.a = 13;
                insn.b = 0;
                insn.imm = readU16(bus, pc +% 1);
                if (writeEnds(op, insn.imm)) terminal = true;
            },
            0xF0 => {
                insn.op = .ld_mem;
                insn.a = 12;
                insn.b = 1;
                insn.imm = @intCast(u16, mmumod.read8(bus, pc +% 1));
            },
            0xF2 => {
                insn.op = .ld_mem;
                insn.a = 15;
                insn.b = 1;
            },
            0xF9 => {
                insn.op = .ld_rr;
                insn.a = 3;
                insn.b = 1;
            },
            0xFA => {
                insn.op = .ld_mem;
                insn.a = 13;
                insn.b = 1;
                insn.imm = readU16(bus, pc +% 1);
            },
            else => {
                terminal = true;
            },
        }

        out.insns[@intCast(usize, out.len)] = insn;
        out.len += 1;
        out.cycles +%= cycles;
        source += add;
        pc = pc +% @intCast(u16, len);
        if (terminal) {
            out.ends_block = true;
            break;
        }
    }
    return out.len != 0;
}
