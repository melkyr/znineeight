const cachemod = @import("cache.zig");
const blockmod = @import("block.zig");
const x86mod = @import("x86.zig");
const ctxmod = @import("ctx.zig");
const cpumod = @import("../cpu.zig");
const cartmod = @import("../cart.zig");

const Cart = cartmod.Cart;

pub const Dynarec = cachemod.Dynarec;
pub const Entry = cachemod.Entry;
pub const Stats = cachemod.Stats;
pub const Cpu = ctxmod.Cpu;
pub const Bus = ctxmod.Bus;
pub const Ppu = ctxmod.Ppu;
pub const DynCtx = ctxmod.DynCtx;
pub const Block = blockmod.Block;
pub const BlockInsn = blockmod.BlockInsn;
pub const BlockOp = blockmod.BlockOp;

pub const CODE_CACHE_BYTES: usize = cachemod.CODE_CACHE_BYTES;
pub const BLOCK_MAX_BYTES: usize = cachemod.BLOCK_MAX_BYTES;
pub const ENTRY_COUNT: usize = cachemod.ENTRY_COUNT;
pub const CHAIN_BUDGET: u32 = 64;

const GLUE_MAX: usize = 224;
const GLUE_BODY_OFF: usize = 9;
const ROM_END: u16 = cachemod.ROM_END;

const PC_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "pc"));
const IME_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "ime"));
const CART_OFF: u32 = @intCast(u32, @offsetOf(Bus, "cart"));
const IO_OFF: u32 = @intCast(u32, @offsetOf(Bus, "io"));
const IE_OFF: u32 = @intCast(u32, @offsetOf(Bus, "ie"));
const ROM0_OFF: u32 = @intCast(u32, @offsetOf(Cart, "rom0_off"));
const ROMX_OFF: u32 = @intCast(u32, @offsetOf(Cart, "romx_off"));

const Buf = struct { b: [GLUE_MAX]u8, n: usize };

const GlueInfo = struct {
    size: u32,
    pc_imm_off: u32,
    bank_imm_off: u32,
    chain_inc_off: u32,
    jmp_disp_off: u32,
    exit_off: u32,
};

const Succ = struct { has: bool, bank: u16, pc: u16, is_ret: bool };
const Want = struct { has: bool, bank: u16, pc: u16 };

fn put8(buf: *Buf, v: u8) void {
    buf.b[buf.n] = v;
    buf.n += 1;
}

fn put32(buf: *Buf, v: u32) void {
    buf.b[buf.n] = @intCast(u8, v & 0xFF);
    buf.b[buf.n + 1] = @intCast(u8, (v >> 8) & 0xFF);
    buf.b[buf.n + 2] = @intCast(u8, (v >> 16) & 0xFF);
    buf.b[buf.n + 3] = @intCast(u8, (v >> 24) & 0xFF);
    buf.n += 4;
}

fn put32At(buf: *Buf, at: usize, v: u32) void {
    buf.b[at] = @intCast(u8, v & 0xFF);
    buf.b[at + 1] = @intCast(u8, (v >> 8) & 0xFF);
    buf.b[at + 2] = @intCast(u8, (v >> 16) & 0xFF);
    buf.b[at + 3] = @intCast(u8, (v >> 24) & 0xFF);
}

fn patchRelTo(buf: *Buf, at: usize, target: usize) void {
    put32At(buf, at, @intCast(u32, target -% (at + 4)));
}

fn writeMem32(d: *Dynarec, at: usize, v: u32) void {
    d.mem[at] = @intCast(u8, v & 0xFF);
    d.mem[at + 1] = @intCast(u8, (v >> 8) & 0xFF);
    d.mem[at + 2] = @intCast(u8, (v >> 16) & 0xFF);
    d.mem[at + 3] = @intCast(u8, (v >> 24) & 0xFF);
}

fn statAddr(d: *Dynarec, which: u8) u32 {
    if (which == 0) return @intCast(u32, @ptrToInt(&d.stats.chained));
    return @intCast(u32, @ptrToInt(&d.last_entry));
}

fn buildGlue(d: *Dynarec, entry_idx: u32, block_addr: u32, insn_count: u32, glue: []u8) GlueInfo {
    var buf: Buf = undefined;
    buf.n = 0;

    put8(&buf, 0x53);
    put8(&buf, 0x57);
    put8(&buf, 0x31);
    put8(&buf, 0xDB);
    put8(&buf, 0xBF);
    put32(&buf, CHAIN_BUDGET);

    put8(&buf, 0xC7);
    put8(&buf, 0x05);
    put32(&buf, statAddr(d, 1));
    put32(&buf, entry_idx);

    put8(&buf, 0x83);
    put8(&buf, 0x05);
    put32(&buf, @intCast(u32, @ptrToInt(&d.stats.tinstr)));
    put8(&buf, @intCast(u8, insn_count));

    put8(&buf, 0xFF);
    put8(&buf, 0x74);
    put8(&buf, 0x24);
    put8(&buf, 0x0C);
    put8(&buf, 0xB8);
    put32(&buf, block_addr);
    put8(&buf, 0xFF);
    put8(&buf, 0xD0);
    put8(&buf, 0x83);
    put8(&buf, 0xC4);
    put8(&buf, 0x04);
    put8(&buf, 0x01);
    put8(&buf, 0xC3);
    put8(&buf, 0x4F);

    put8(&buf, 0x0F);
    put8(&buf, 0x84);
    const jz_at: usize = buf.n;
    put32(&buf, 0);

    put8(&buf, 0x8B);
    put8(&buf, 0x54);
    put8(&buf, 0x24);
    put8(&buf, 0x0C);
    put8(&buf, 0x8B);
    put8(&buf, 0x12);
    put8(&buf, 0x0F);
    put8(&buf, 0xB7);
    put8(&buf, 0x42);
    put8(&buf, PC_OFF);

    put8(&buf, 0x3D);
    const pc_imm_off: u32 = @intCast(u32, buf.n);
    put32(&buf, 0);

    put8(&buf, 0x0F);
    put8(&buf, 0x85);
    const jne_pc_at: usize = buf.n;
    put32(&buf, 0);

    put8(&buf, 0x8B);
    put8(&buf, 0x4C);
    put8(&buf, 0x24);
    put8(&buf, 0x0C);
    put8(&buf, 0x8B);
    put8(&buf, 0x49);
    put8(&buf, 0x04);
    put8(&buf, 0x8B);
    put8(&buf, 0x89);
    put32(&buf, CART_OFF);
    put8(&buf, 0x3D);
    put32(&buf, 0x00004000);

    put8(&buf, 0x0F);
    put8(&buf, 0x83);
    const jae_romx_at: usize = buf.n;
    put32(&buf, 0);

    put8(&buf, 0x8B);
    put8(&buf, 0x89);
    put32(&buf, ROM0_OFF);
    put8(&buf, 0xE9);
    const jmp_have_at: usize = buf.n;
    put32(&buf, 0);

    const romx_off: usize = buf.n;
    put8(&buf, 0x8B);
    put8(&buf, 0x89);
    put32(&buf, ROMX_OFF);
    const have_off: usize = buf.n;

    put8(&buf, 0xC1);
    put8(&buf, 0xE9);
    put8(&buf, 0x0E);
    put8(&buf, 0x81);
    put8(&buf, 0xF9);
    const bank_imm_off: u32 = @intCast(u32, buf.n);
    put32(&buf, 0);

    put8(&buf, 0x0F);
    put8(&buf, 0x85);
    const jne_bank_at: usize = buf.n;
    put32(&buf, 0);

    put8(&buf, 0x8B);
    put8(&buf, 0x4C);
    put8(&buf, 0x24);
    put8(&buf, 0x0C);
    put8(&buf, 0x8B);
    put8(&buf, 0x49);
    put8(&buf, 0x04);
    put8(&buf, 0x0F);
    put8(&buf, 0xB6);
    put8(&buf, 0x42);
    put8(&buf, IME_OFF);
    put8(&buf, 0x85);
    put8(&buf, 0xC0);
    put8(&buf, 0x0F);
    put8(&buf, 0x84);
    const ime_jz_at: usize = buf.n;
    put32(&buf, 0);

    put8(&buf, 0x0F);
    put8(&buf, 0xB6);
    put8(&buf, 0x81);
    put32(&buf, IO_OFF +% 0x0F);
    put8(&buf, 0x0F);
    put8(&buf, 0xB6);
    put8(&buf, 0x89);
    put32(&buf, IE_OFF);
    put8(&buf, 0x21);
    put8(&buf, 0xC8);
    put8(&buf, 0x83);
    put8(&buf, 0xE0);
    put8(&buf, 0x1F);
    put8(&buf, 0x85);
    put8(&buf, 0xC0);
    put8(&buf, 0x0F);
    put8(&buf, 0x85);
    const ime_jnz_at: usize = buf.n;
    put32(&buf, 0);

    const chain_inc_off: u32 = @intCast(u32, buf.n);
    put8(&buf, 0xFF);
    put8(&buf, 0x05);
    put32(&buf, statAddr(d, 0));

    put8(&buf, 0xE9);
    const jmp_disp_off: u32 = @intCast(u32, buf.n);
    put32(&buf, 0);

    const exit_off: usize = buf.n;
    put8(&buf, 0x89);
    put8(&buf, 0xD8);
    put8(&buf, 0x5F);
    put8(&buf, 0x5B);
    put8(&buf, 0xC3);

    patchRelTo(&buf, jz_at, exit_off);
    patchRelTo(&buf, jne_pc_at, exit_off);
    patchRelTo(&buf, jae_romx_at, romx_off);
    patchRelTo(&buf, jmp_have_at, have_off);
    patchRelTo(&buf, jne_bank_at, exit_off);
    patchRelTo(&buf, ime_jz_at, @intCast(usize, chain_inc_off));
    patchRelTo(&buf, ime_jnz_at, exit_off);
    patchRelTo(&buf, jmp_disp_off, exit_off);

    var i: usize = 0;
    while (i < buf.n) : (i += 1) glue[i] = buf.b[i];

    return GlueInfo{
        .size = @intCast(u32, buf.n),
        .pc_imm_off = pc_imm_off,
        .bank_imm_off = bank_imm_off,
        .chain_inc_off = chain_inc_off,
        .jmp_disp_off = jmp_disp_off,
        .exit_off = @intCast(u32, exit_off),
    };
}

fn setChainInc(d: *Dynarec, e: *Entry, on: bool) void {
    const at: usize = @intCast(usize, e.glue_off) + @intCast(usize, e.chain_inc_off);
    if (on) {
        d.mem[at] = 0xFF;
        d.mem[at + 1] = 0x05;
        writeMem32(d, at + 2, statAddr(d, 0));
        return;
    }
    var i: usize = 0;
    while (i < 6) : (i += 1) d.mem[at + i] = 0x90;
}

fn patchJump(d: *Dynarec, e: *Entry, target: usize) void {
    const at: usize = @intCast(usize, e.glue_off) + @intCast(usize, e.jmp_disp_off);
    writeMem32(d, at, @intCast(u32, target -% (at + 4)));
}

fn patchGuard(d: *Dynarec, e: *Entry, bank: u16, pc: u16) void {
    const p_at: usize = @intCast(usize, e.glue_off) + @intCast(usize, e.pc_imm_off);
    writeMem32(d, p_at, @intCast(u32, pc));
    const b_at: usize = @intCast(usize, e.glue_off) + @intCast(usize, e.bank_imm_off);
    writeMem32(d, b_at, @intCast(u32, bank));
}

fn desired(e: *const Entry) Want {
    if (e.is_ret and e.has_ret) return Want{ .has = true, .bank = e.ret_bank, .pc = e.ret_target };
    if (e.has_fixed_succ) return Want{ .has = true, .bank = e.succ_bank, .pc = e.succ_pc };
    return Want{ .has = false, .bank = 0, .pc = 0 };
}

fn linkEntry(d: *Dynarec, e: *Entry) void {
    const w: Want = desired(e);
    var target: usize = @intCast(usize, e.glue_off) + @intCast(usize, e.exit_off);
    var linked: bool = false;
    if (w.has) {
        if (cachemod.dynarecLookup(d, w.bank, w.pc)) |t| {
            target = @intCast(usize, t.glue_off) + GLUE_BODY_OFF;
            linked = true;
        }
    }
    const target32: u32 = @intCast(u32, target);
    if (e.link_valid == linked and e.link_bank == w.bank and e.link_pc == w.pc and e.link_target_off == target32) return;
    patchGuard(d, e, w.bank, w.pc);
    patchJump(d, e, target);
    setChainInc(d, e, linked);
    e.link_valid = linked;
    e.link_bank = w.bank;
    e.link_pc = w.pc;
    e.link_target_off = target32;
    cachemod.flushRange(d, @intCast(usize, e.glue_off), @intCast(usize, e.exit_off) + 5);
}

fn linkPredecessors(d: *Dynarec, bank: u16, pc: u16) void {
    var i: usize = 0;
    while (i < ENTRY_COUNT) : (i += 1) {
        const e: *Entry = &d.entries[i];
        if (!e.valid) continue;
        const w: Want = desired(e);
        if (w.has and w.bank == bank and w.pc == pc) linkEntry(d, e);
    }
}

fn insnBytes(insn: BlockInsn) u8 {
    switch (insn.op) {
        .nop => return 1,
        .ld_rr => return if (insn.b == 1) 1 else 3,
        .ld_rn => return 2,
        .ld_mem => {
            switch (insn.a) {
                0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 15, 16, 17 => return 1,
                12 => return 2,
                13, 14 => return 3,
                else => return 0,
            }
        },
        .alu_r => return 1,
        .alu_n => return 2,
        .incdec => return 1,
        .jump => {
            if (insn.b == 0) return 3;
            if (insn.b == 1) return 2;
            if (insn.b == 2) return 1;
            return 0;
        },
        .call => {
            if (insn.b == 1) return 1;
            return 3;
        },
        .ret => return 1,
        .cb => return 2,
        else => return 0,
    }
}

fn succAt(bus: *Bus, pc: u16) Succ {
    if (pc > ROM_END) return Succ{ .has = false, .bank = 0, .pc = 0, .is_ret = false };
    return Succ{ .has = true, .bank = cachemod.effectiveBank(bus, pc), .pc = pc, .is_ret = false };
}

fn blockSuccessor(bus: *Bus, blk: *const Block) Succ {
    var pc: u16 = blk.start_pc;
    var i: usize = 0;
    while (i < @intCast(usize, blk.len)) : (i += 1) {
        const insn: BlockInsn = blk.insns[i];
        const last: bool = (i + 1) == @intCast(usize, blk.len);
        if (last and blk.ends_block) {
            switch (insn.op) {
                .jump => {
                    if (insn.b == 2) return Succ{ .has = false, .bank = 0, .pc = 0, .is_ret = false };
                    return succAt(bus, insn.imm);
                },
                .call => return succAt(bus, insn.imm),
                .ret => return Succ{ .has = false, .bank = 0, .pc = 0, .is_ret = true },
                .unsupported => return Succ{ .has = false, .bank = 0, .pc = 0, .is_ret = false },
                else => return succAt(bus, pc +% @intCast(u16, insnBytes(insn))),
            }
        }
        pc +%= @intCast(u16, insnBytes(insn));
    }
    return succAt(bus, pc);
}

fn blockSpan(blk: *const Block) u16 {
    var bytes: u32 = 0;
    var i: usize = 0;
    while (i < @intCast(usize, blk.len)) : (i += 1) {
        bytes +%= @intCast(u32, insnBytes(blk.insns[i]));
    }
    return @intCast(u16, bytes);
}

fn translate(d: *Dynarec, cpu: *Cpu, bus: *Bus, bank: u16, pc: u16) ?*Entry {
    var tmp: Cpu = cpu.*;
    tmp.pc = pc;
    var blk: Block = undefined;
    if (!blockmod.blockBuild(&tmp, bus, &blk)) {
        d.stats.rejected += 1;
        return null;
    }
    if (blk.len == 0) {
        d.stats.rejected += 1;
        return null;
    }
    const end: u32 = @as(u32, blk.start_pc) + @as(u32, blockSpan(&blk));
    if (end > 0x00008000) {
        d.stats.rejected += 1;
        return null;
    }
    if (blk.start_pc < 0x4000 and end > 0x00004000) {
        d.stats.rejected += 1;
        return null;
    }
    const succ: Succ = blockSuccessor(bus, &blk);

    var tries: u8 = 0;
    while (tries < 2) : (tries += 1) {
        var start: usize = cachemod.align16(d.used);
        if (start + BLOCK_MAX_BYTES + GLUE_MAX > CODE_CACHE_BYTES) {
            d.stats.resets += 1;
            cachemod.dynarecFlush(d);
            start = 0;
        }
        var e = x86mod.Emit{ .code = d.mem + start, .len = 0, .cap = BLOCK_MAX_BYTES };
        if (!x86mod.emitBlock(&e, &blk)) {
            d.stats.rejected += 1;
            return null;
        }
        const blen: usize = e.len;
        const glue_off: usize = cachemod.align4(start + blen);
        if (glue_off + GLUE_MAX > CODE_CACHE_BYTES) {
            d.stats.resets += 1;
            cachemod.dynarecFlush(d);
            continue;
        }
        const idx: usize = cachemod.entryIndex(bank, pc);
        const ent: *Entry = &d.entries[idx];
        if (ent.valid) d.stats.collisions += 1;
        var glue_bytes: [GLUE_MAX]u8 = undefined;
        const gi: GlueInfo = buildGlue(d, @intCast(u32, idx), @intCast(u32, @ptrToInt(d.mem + start)), @intCast(u32, blk.len), glue_bytes[0..]);
        var gi2: usize = 0;
        while (gi2 < @intCast(usize, gi.size)) : (gi2 += 1) d.mem[glue_off + gi2] = glue_bytes[gi2];

        ent.valid = true;
        ent.bank = bank;
        ent.pc = pc;
        ent.code_off = @intCast(u32, start);
        ent.len = @intCast(u32, blen);
        ent.glue_off = @intCast(u32, glue_off);
        ent.pc_imm_off = gi.pc_imm_off;
        ent.bank_imm_off = gi.bank_imm_off;
        ent.chain_inc_off = gi.chain_inc_off;
        ent.jmp_disp_off = gi.jmp_disp_off;
        ent.exit_off = gi.exit_off;
        ent.is_ret = succ.is_ret;
        ent.has_fixed_succ = succ.has;
        ent.succ_bank = succ.bank;
        ent.succ_pc = succ.pc;
        ent.has_ret = false;
        ent.ret_bank = 0;
        ent.ret_target = 0;
        ent.link_valid = false;
        ent.link_bank = 0;
        ent.link_pc = 0;
        ent.link_target_off = 0;

        d.used = glue_off + @intCast(usize, gi.size);
        cachemod.flushRange(d, start, d.used - start);
        d.stats.blocks += 1;
        linkEntry(d, ent);
        linkPredecessors(d, bank, pc);
        return ent;
    }
    d.stats.rejected += 1;
    return null;
}

fn interpStep(d: *Dynarec, cpu: *Cpu, bus: *Bus) u32 {
    d.stats.fallback += 1;
    d.stats.minstr += 1;
    return cpumod.cpuStep(cpu, bus);
}

pub fn dynarecOpen(d: *Dynarec, bus: *Bus) bool {
    return cachemod.dynarecOpen(d, bus);
}

pub fn dynarecClose(d: *Dynarec) void {
    cachemod.dynarecClose(d);
}

pub fn dynarecFlush(d: *Dynarec) void {
    cachemod.dynarecFlush(d);
}

pub fn dynarecInvalidateBank(d: *Dynarec, bank: u16) void {
    cachemod.dynarecInvalidateBank(d, bank);
}

pub fn dynarecInvalidateRange(d: *Dynarec, lo: u16, hi: u16) void {
    cachemod.dynarecInvalidateRange(d, lo, hi);
}

pub fn dynarecInvalidateRom0(d: *Dynarec) void {
    cachemod.dynarecInvalidateRom0(d);
}

pub fn dynarecInvalidateRomx(d: *Dynarec) void {
    cachemod.dynarecInvalidateRomx(d);
}

pub fn dynarecEnabled(d: *const Dynarec) bool {
    return cachemod.dynarecEnabled(d);
}

pub fn dynarecLookup(d: *Dynarec, bank: u16, pc: u16) ?*Entry {
    return cachemod.dynarecLookup(d, bank, pc);
}

pub fn dynarecFlushRange(d: *Dynarec, off: usize, len: usize) void {
    cachemod.flushRange(d, off, len);
}

var g_ppu_advanced_dots: u32 = 0;

pub fn dynarecPpuAdvancedDots() u32 {
    return g_ppu_advanced_dots;
}

pub fn dynarecRunBlock(d: *Dynarec, cpu: *Cpu, bus: *Bus, ppu: *Ppu) u32 {
    g_ppu_advanced_dots = 0;
    if (!d.mapped) return interpStep(d, cpu, bus);
    if (cpu.halted) return interpStep(d, cpu, bus);
    if (bus.dma.active) return interpStep(d, cpu, bus);
    const pc: u16 = cpu.pc;
    if (pc > ROM_END) return interpStep(d, cpu, bus);

    const bank: u16 = cachemod.effectiveBank(bus, pc);
    var ent: ?*Entry = cachemod.dynarecLookup(d, bank, pc);
    if (ent == null) ent = translate(d, cpu, bus, bank, pc);
    if (ent == null) return interpStep(d, cpu, bus);

    const e: *Entry = ent orelse return interpStep(d, cpu, bus);
    linkEntry(d, e);
    const chain0: u32 = d.stats.chained;

    const f = @ptrCast(fn (*DynCtx) u32, d.mem + @intCast(usize, e.glue_off));
    var ctx = DynCtx{ .cpu = cpu, .bus = bus, .ppu = ppu, .cycles = 0, .instr_cycles = 0, .ppu_pending = 0, .ppu_advanced_dots = 0 };
    const cycles: u32 = f(&ctx);
    d.stats.executed +%= 1 +% (d.stats.chained -% chain0);

    const li: u32 = d.last_entry;
    if (li < ENTRY_COUNT) {
        const last: *Entry = &d.entries[@intCast(usize, li)];
        if (last.valid and last.is_ret) {
            if (cpu.pc <= ROM_END) {
                const rb: u16 = cachemod.effectiveBank(bus, cpu.pc);
                if (!last.has_ret or last.ret_bank != rb or last.ret_target != cpu.pc) {
                    last.has_ret = true;
                    last.ret_bank = rb;
                    last.ret_target = cpu.pc;
                    linkEntry(d, last);
                }
            }
        }
    }
    g_ppu_advanced_dots = ctx.ppu_advanced_dots;
    return cycles;
}
