// x86.zig — pure-Z98 x86-32 emitter for the z9gb SM83 dynarec.
//
// Task 2 scope: ALU/loads with register-cached CPU pairs. The generated
// function is cdecl `fn (*DynCtx) u32`; BC/DE/HL/SP live in ebx/esi/edi/ebp
// for the whole block, A/F stay in Cpu memory, and PC is written back once in
// the epilogue. Cycles are returned in eax.
//
// Memory operands use an inline page-table fast path. ROM reads, WRAM, echo,
// and HRAM at FF80-FFFE are direct; cart RAM is direct only when its page base
// is not the disabled-RAM stub. Everything else tail-calls the Task 3 helper
// ABI (helperRead8/helperWrite8/helperIoRead/helperIoWrite), which keeps ROM
// writes on the MBC path and IO/OAM/VRAM/RTC on the interpreter path.

const ctxmod = @import("ctx.zig");
const blockmod = @import("block.zig");
const mmumod = @import("../mmu.zig");

pub const DynCtx = ctxmod.DynCtx;
pub const Cpu = ctxmod.Cpu;
pub const Bus = ctxmod.Bus;
pub const Page = ctxmod.Page;
pub const PageKind = ctxmod.PageKind;
pub const Block = blockmod.Block;
pub const BlockInsn = blockmod.BlockInsn;
pub const BlockOp = blockmod.BlockOp;

pub const Emit = struct { code: [*]u8, len: usize, cap: usize };

// Task 2 link shims for the Task 3 helper ABI. They keep the emitted block
// runnable in the emitter unit gate; Task 3 replaces them with the real
// cycle-charging helpers in helpers.zig.
fn helperRead8(ctx: *DynCtx, addr: u16) u8 {
    return mmumod.read8(ctx.bus, addr);
}

fn helperWrite8(ctx: *DynCtx, addr: u16, value: u8) void {
    mmumod.write8(ctx.bus, addr, value);
}

fn helperIoRead(ctx: *DynCtx, addr: u16) u8 {
    return mmumod.read8(ctx.bus, addr);
}

fn helperIoWrite(ctx: *DynCtx, addr: u16, value: u8) void {
    mmumod.write8(ctx.bus, addr, value);
}

const HELPER_READ_ADDR: u32 = @intCast(u32, @ptrToInt(helperRead8));
const HELPER_WRITE_ADDR: u32 = @intCast(u32, @ptrToInt(helperWrite8));
const HELPER_IO_READ_ADDR: u32 = @intCast(u32, @ptrToInt(helperIoRead));
const HELPER_IO_WRITE_ADDR: u32 = @intCast(u32, @ptrToInt(helperIoWrite));

const K_ROM0: u8 = @intCast(u8, @enumToInt(PageKind.rom0));
const K_ROMX: u8 = @intCast(u8, @enumToInt(PageKind.romx));
const K_CART: u8 = @intCast(u8, @enumToInt(PageKind.cart_ram));
const K_WRAM: u8 = @intCast(u8, @enumToInt(PageKind.wram));
const K_ECHO: u8 = @intCast(u8, @enumToInt(PageKind.echo));
const K_IO: u8 = @intCast(u8, @enumToInt(PageKind.io));
const K_HRAM: u8 = @intCast(u8, @enumToInt(PageKind.hram));

const A_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "a"));
const F_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "f"));
const B_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "b"));
const C_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "c"));
const D_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "d"));
const E_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "e"));
const H_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "h"));
const L_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "l"));
const SP_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "sp"));
const PC_OFF: u8 = @intCast(u8, @offsetOf(Cpu, "pc"));

const PAGES_OFF: u32 = @intCast(u32, @offsetOf(Bus, "pages"));
const STUB_OFF: u32 = @intCast(u32, @offsetOf(Bus, "stub"));
const KIND_OFF: u8 = @intCast(u8, @offsetOf(Page, "kind"));
const BASE_OFF: u8 = @intCast(u8, @offsetOf(Page, "base"));
const PAGE_SIZE: u32 = @intCast(u32, @sizeOf(Page));

const H_AF: u8 = 0;
const H_TRUE: u8 = 1;
const H_FALSE: u8 = 2;
const C_CF: u8 = 0;
const C_TRUE: u8 = 1;
const C_FALSE: u8 = 2;
const C_OLD: u8 = 3;

const Label = struct { at: [12]usize, n: usize };

pub fn emitByte(e: *Emit, b: u8) bool {
    if (e.len > e.cap) return false;
    if (e.len == e.cap) {
        e.len = e.cap + 1;
        return false;
    }
    e.code[e.len] = b;
    e.len += 1;
    return true;
}

pub fn emitU32(e: *Emit, v: u32) bool {
    var ok: bool = emitByte(e, @intCast(u8, v & 0xFF));
    ok = emitByte(e, @intCast(u8, (v >> 8) & 0xFF)) and ok;
    ok = emitByte(e, @intCast(u8, (v >> 16) & 0xFF)) and ok;
    ok = emitByte(e, @intCast(u8, (v >> 24) & 0xFF)) and ok;
    return ok;
}

fn emitU16(e: *Emit, v: u16) void {
    _ = emitByte(e, @intCast(u8, v & 0xFF));
    _ = emitByte(e, @intCast(u8, (v >> 8) & 0xFF));
}

fn emitImm32(e: *Emit, v: u32) void {
    _ = emitU32(e, v);
}

fn modrmDisp8(reg: u8, rm: u8) u8 {
    const r: u16 = @intCast(u16, reg & 7);
    const m: u16 = @intCast(u16, rm & 7);
    return @intCast(u8, 0x40 + (r << 3) + m);
}

fn modrmReg(reg: u8, rm: u8) u8 {
    const r: u16 = @intCast(u16, reg & 7);
    const m: u16 = @intCast(u16, rm & 7);
    return @intCast(u8, 0xC0 + (r << 3) + m);
}

fn labelReset(l: *Label) void {
    l.n = 0;
}

fn labelAdd(l: *Label, at: usize) void {
    if (l.n < l.at.len) {
        l.at[l.n] = at;
        l.n += 1;
    }
}

fn writeU32At(e: *Emit, at: usize, v: usize) void {
    if (at + 4 > e.cap) return;
    const x: u32 = @intCast(u32, v & 0xFFFFFFFF);
    e.code[at] = @intCast(u8, x & 0xFF);
    e.code[at + 1] = @intCast(u8, (x >> 8) & 0xFF);
    e.code[at + 2] = @intCast(u8, (x >> 16) & 0xFF);
    e.code[at + 3] = @intCast(u8, (x >> 24) & 0xFF);
}

fn labelPatch(e: *Emit, l: *Label) void {
    var i: usize = 0;
    while (i < l.n) : (i += 1) {
        const at: usize = l.at[i];
        const rel: usize = e.len - (at + 4);
        writeU32At(e, at, rel);
    }
    l.n = 0;
}

fn emitJcc(e: *Emit, cc: u8, l: *Label) void {
    _ = emitByte(e, 0x0F);
    _ = emitByte(e, @intCast(u8, 0x80 | (cc & 0x0F)));
    const at: usize = e.len;
    emitImm32(e, 0);
    labelAdd(l, at);
}

fn emitJmp(e: *Emit, l: *Label) void {
    _ = emitByte(e, 0xE9);
    const at: usize = e.len;
    emitImm32(e, 0);
    labelAdd(l, at);
}

fn emitMovRegImm32(e: *Emit, reg: u8, v: u32) void {
    _ = emitByte(e, @intCast(u8, 0xB8 + (reg & 7)));
    emitImm32(e, v);
}

fn emitSIB(e: *Emit, base: u8) void {
    if (base == 4) _ = emitByte(e, 0x24);
}

fn emitMovR32MemDisp(e: *Emit, reg: u8, base: u8, disp: u8) void {
    _ = emitByte(e, 0x8B);
    _ = emitByte(e, modrmDisp8(reg, base));
    emitSIB(e, base);
    _ = emitByte(e, disp);
}

fn emitMovMemDispR32(e: *Emit, base: u8, disp: u8, reg: u8) void {
    _ = emitByte(e, 0x89);
    _ = emitByte(e, modrmDisp8(reg, base));
    emitSIB(e, base);
    _ = emitByte(e, disp);
}

fn emitMovR8MemDisp(e: *Emit, reg: u8, base: u8, disp: u8) void {
    _ = emitByte(e, 0x8A);
    _ = emitByte(e, modrmDisp8(reg, base));
    emitSIB(e, base);
    _ = emitByte(e, disp);
}

fn emitMovMemDispR8(e: *Emit, base: u8, disp: u8, reg: u8) void {
    _ = emitByte(e, 0x88);
    _ = emitByte(e, modrmDisp8(reg, base));
    emitSIB(e, base);
    _ = emitByte(e, disp);
}

fn emitMovzxR32Mem8(e: *Emit, reg: u8, base: u8, disp: u8) void {
    _ = emitByte(e, 0x0F);
    _ = emitByte(e, 0xB6);
    _ = emitByte(e, modrmDisp8(reg, base));
    emitSIB(e, base);
    _ = emitByte(e, disp);
}

fn emitMovzxR32Mem16(e: *Emit, reg: u8, base: u8, disp: u8) void {
    _ = emitByte(e, 0x0F);
    _ = emitByte(e, 0xB7);
    _ = emitByte(e, modrmDisp8(reg, base));
    emitSIB(e, base);
    _ = emitByte(e, disp);
}

fn emitMovzxR32R8(e: *Emit, reg: u8, rm: u8) void {
    _ = emitByte(e, 0x0F);
    _ = emitByte(e, 0xB6);
    _ = emitByte(e, modrmReg(reg, rm));
}

fn emitMovzxR32R16(e: *Emit, reg: u8, rm: u8) void {
    _ = emitByte(e, 0x0F);
    _ = emitByte(e, 0xB7);
    _ = emitByte(e, modrmReg(reg, rm));
}

fn emitAluRegReg(e: *Emit, op: u8, reg: u8, rm: u8) void {
    _ = emitByte(e, op);
    _ = emitByte(e, modrmReg(reg, rm));
}

fn emitCmpRegImm8(e: *Emit, reg: u8, v: u8) void {
    _ = emitByte(e, 0x83);
    _ = emitByte(e, modrmReg(7, reg));
    _ = emitByte(e, v);
}

fn emitCmpRegImm32(e: *Emit, reg: u8, v: u32) void {
    _ = emitByte(e, 0x81);
    _ = emitByte(e, modrmReg(7, reg));
    emitImm32(e, v);
}

fn emitAddRegImm32(e: *Emit, reg: u8, v: u32) void {
    _ = emitByte(e, 0x81);
    _ = emitByte(e, modrmReg(0, reg));
    emitImm32(e, v);
}

fn emitAndRegImm32(e: *Emit, reg: u8, v: u32) void {
    _ = emitByte(e, 0x81);
    _ = emitByte(e, modrmReg(4, reg));
    emitImm32(e, v);
}

fn emitOrRegImm32(e: *Emit, reg: u8, v: u32) void {
    _ = emitByte(e, 0x81);
    _ = emitByte(e, modrmReg(1, reg));
    emitImm32(e, v);
}

fn emitMovRegReg(e: *Emit, dst: u8, src: u8) void {
    _ = emitByte(e, 0x89);
    _ = emitByte(e, modrmReg(src, dst));
}

fn emitShrRegImm8(e: *Emit, reg: u8, v: u8) void {
    _ = emitByte(e, 0xC1);
    _ = emitByte(e, modrmReg(5, reg));
    _ = emitByte(e, v);
}

fn emitShlRegImm8(e: *Emit, reg: u8, v: u8) void {
    _ = emitByte(e, 0xC1);
    _ = emitByte(e, modrmReg(4, reg));
    _ = emitByte(e, v);
}

fn emitOrRegReg32(e: *Emit, dst: u8, src: u8) void {
    _ = emitByte(e, 0x09);
    _ = emitByte(e, modrmReg(src, dst));
}

fn emitAddRegReg32(e: *Emit, dst: u8, src: u8) void {
    _ = emitByte(e, 0x01);
    _ = emitByte(e, modrmReg(src, dst));
}

fn emitMovEdxCpu(e: *Emit) void {
    _ = emitByte(e, 0x8B);
    _ = emitByte(e, 0x14);
    _ = emitByte(e, 0x24);
}

fn emitMovEdxBus(e: *Emit) void {
    _ = emitByte(e, 0x8B);
    _ = emitByte(e, 0x54);
    _ = emitByte(e, 0x24);
    _ = emitByte(e, 0x04);
}

fn emitLoadA(e: *Emit) void {
    emitMovEdxCpu(e);
    emitMovR8MemDisp(e, 0, 2, A_OFF);
}

fn emitStoreA(e: *Emit) void {
    emitMovEdxCpu(e);
    emitMovMemDispR8(e, 2, A_OFF, 0);
}

fn emitReadRegToAl(e: *Emit, idx: u8) void {
    switch (idx) {
        0 => {
            _ = emitByte(e, 0x8A);
            _ = emitByte(e, 0xC7);
        },
        1 => {
            _ = emitByte(e, 0x8A);
            _ = emitByte(e, 0xC3);
        },
        2 => {
            emitMovRegReg(e, 1, 6);
            emitShrRegImm8(e, 1, 8);
            emitAluRegReg(e, 0x88, 1, 0);
        },
        3 => {
            emitMovRegReg(e, 1, 6);
            emitAluRegReg(e, 0x88, 1, 0);
        },
        4 => {
            emitMovRegReg(e, 1, 7);
            emitShrRegImm8(e, 1, 8);
            emitAluRegReg(e, 0x88, 1, 0);
        },
        5 => {
            emitMovRegReg(e, 1, 7);
            emitAluRegReg(e, 0x88, 1, 0);
        },
        7 => emitLoadA(e),
        else => {},
    }
}

fn emitWriteAlToReg(e: *Emit, idx: u8) void {
    switch (idx) {
        0 => {
            _ = emitByte(e, 0x88);
            _ = emitByte(e, 0xC7);
        },
        1 => {
            _ = emitByte(e, 0x88);
            _ = emitByte(e, 0xC3);
        },
        2 => {
            emitAndRegImm32(e, 6, 0x000000FF);
            emitMovzxR32R8(e, 1, 0);
            emitShlRegImm8(e, 1, 8);
            emitOrRegReg32(e, 6, 1);
        },
        3 => {
            emitAndRegImm32(e, 6, 0xFFFFFF00);
            emitMovzxR32R8(e, 1, 0);
            emitOrRegReg32(e, 6, 1);
        },
        4 => {
            emitAndRegImm32(e, 7, 0x000000FF);
            emitMovzxR32R8(e, 1, 0);
            emitShlRegImm8(e, 1, 8);
            emitOrRegReg32(e, 7, 1);
        },
        5 => {
            emitAndRegImm32(e, 7, 0xFFFFFF00);
            emitMovzxR32R8(e, 1, 0);
            emitOrRegReg32(e, 7, 1);
        },
        7 => emitStoreA(e),
        else => {},
    }
}

fn emitAddrEcxHL(e: *Emit) void {
    emitMovzxR32R16(e, 1, 7);
}

fn emitAddrEcxBC(e: *Emit) void {
    emitMovzxR32R16(e, 1, 3);
}

fn emitAddrEcxDE(e: *Emit) void {
    emitMovzxR32R16(e, 1, 6);
}

fn emitAddrEcxC(e: *Emit) void {
    emitMovzxR32R8(e, 1, 3);
    emitOrRegImm32(e, 1, 0x0000FF00);
}

fn emitAddrEcxImm(e: *Emit, addr: u16) void {
    _ = emitByte(e, 0xB9);
    emitImm32(e, @intCast(u32, addr));
}

fn emitPagePtr(e: *Emit) void {
    emitMovRegReg(e, 0, 1);
    emitShrRegImm8(e, 0, 8);
    _ = emitByte(e, 0x69);
    _ = emitByte(e, 0xC0);
    emitImm32(e, PAGE_SIZE);
    emitMovEdxBus(e);
    emitAddRegReg32(e, 0, 2);
    emitAddRegImm32(e, 0, PAGES_OFF);
}

fn emitHelperRead(e: *Emit, io: bool) void {
    _ = emitByte(e, 0x51);
    _ = emitByte(e, 0xFF);
    _ = emitByte(e, 0x74);
    _ = emitByte(e, 0x24);
    _ = emitByte(e, 0x0C);
    _ = emitByte(e, 0xB8);
    const target: u32 = if (io) HELPER_IO_READ_ADDR else HELPER_READ_ADDR;
    emitImm32(e, target);
    _ = emitByte(e, 0xFF);
    _ = emitByte(e, 0xD0);
    _ = emitByte(e, 0x83);
    _ = emitByte(e, 0xC4);
    _ = emitByte(e, 0x08);
}

fn emitHelperWrite(e: *Emit, io: bool) void {
    emitMovzxR32Mem8(e, 0, 4, 0x0C);
    _ = emitByte(e, 0x50);
    _ = emitByte(e, 0x51);
    _ = emitByte(e, 0xFF);
    _ = emitByte(e, 0x74);
    _ = emitByte(e, 0x24);
    _ = emitByte(e, 0x10);
    _ = emitByte(e, 0xB8);
    const target: u32 = if (io) HELPER_IO_WRITE_ADDR else HELPER_WRITE_ADDR;
    emitImm32(e, target);
    _ = emitByte(e, 0xFF);
    _ = emitByte(e, 0xD0);
    _ = emitByte(e, 0x83);
    _ = emitByte(e, 0xC4);
    _ = emitByte(e, 0x0C);
}

fn emitMemReadAl(e: *Emit) void {
    var l_direct: Label = undefined;
    var l_cart: Label = undefined;
    var l_hram: Label = undefined;
    var l_io: Label = undefined;
    var l_helper: Label = undefined;
    var l_direct_base: Label = undefined;
    var l_done: Label = undefined;
    labelReset(&l_direct);
    labelReset(&l_cart);
    labelReset(&l_hram);
    labelReset(&l_io);
    labelReset(&l_helper);
    labelReset(&l_direct_base);
    labelReset(&l_done);

    emitPagePtr(e);
    emitMovzxR32Mem8(e, 2, 0, KIND_OFF);
    emitCmpRegImm8(e, 2, K_ROM0);
    emitJcc(e, 4, &l_direct);
    emitCmpRegImm8(e, 2, K_ROMX);
    emitJcc(e, 4, &l_direct);
    emitCmpRegImm8(e, 2, K_WRAM);
    emitJcc(e, 4, &l_direct);
    emitCmpRegImm8(e, 2, K_ECHO);
    emitJcc(e, 4, &l_direct);
    emitCmpRegImm8(e, 2, K_CART);
    emitJcc(e, 4, &l_cart);
    emitCmpRegImm8(e, 2, K_HRAM);
    emitJcc(e, 4, &l_hram);
    emitJmp(e, &l_helper);

    labelPatch(e, &l_cart);
    emitMovR32MemDisp(e, 2, 0, BASE_OFF);
    emitMovR32MemDisp(e, 0, 4, 0x04);
    emitAddRegImm32(e, 0, STUB_OFF);
    emitAluRegReg(e, 0x39, 0, 2);
    emitJcc(e, 5, &l_direct_base);
    emitJmp(e, &l_helper);

    labelPatch(e, &l_hram);
    emitCmpRegImm32(e, 1, 0x0000FF80);
    emitJcc(e, 2, &l_io);
    emitCmpRegImm32(e, 1, 0x0000FFFF);
    emitJcc(e, 4, &l_helper);

    labelPatch(e, &l_direct);
    emitMovR32MemDisp(e, 2, 0, BASE_OFF);
    labelPatch(e, &l_direct_base);
    emitMovRegReg(e, 0, 1);
    emitAndRegImm32(e, 0, 0x000000FF);
    _ = emitByte(e, 0x8A);
    _ = emitByte(e, 0x04);
    _ = emitByte(e, 0x02);
    emitJmp(e, &l_done);

    labelPatch(e, &l_io);
    emitHelperRead(e, true);
    emitJmp(e, &l_done);

    labelPatch(e, &l_helper);
    emitHelperRead(e, false);
    labelPatch(e, &l_done);
}

fn emitMemWrite(e: *Emit) void {
    var l_direct: Label = undefined;
    var l_cart: Label = undefined;
    var l_hram: Label = undefined;
    var l_io: Label = undefined;
    var l_helper: Label = undefined;
    var l_direct_base: Label = undefined;
    var l_done: Label = undefined;
    labelReset(&l_direct);
    labelReset(&l_cart);
    labelReset(&l_hram);
    labelReset(&l_io);
    labelReset(&l_helper);
    labelReset(&l_direct_base);
    labelReset(&l_done);

    emitPagePtr(e);
    emitMovzxR32Mem8(e, 2, 0, KIND_OFF);
    emitCmpRegImm8(e, 2, K_WRAM);
    emitJcc(e, 4, &l_direct);
    emitCmpRegImm8(e, 2, K_ECHO);
    emitJcc(e, 4, &l_direct);
    emitCmpRegImm8(e, 2, K_CART);
    emitJcc(e, 4, &l_cart);
    emitCmpRegImm8(e, 2, K_HRAM);
    emitJcc(e, 4, &l_hram);
    emitCmpRegImm8(e, 2, K_IO);
    emitJcc(e, 4, &l_io);
    emitJmp(e, &l_helper);

    labelPatch(e, &l_cart);
    emitMovR32MemDisp(e, 2, 0, BASE_OFF);
    emitMovR32MemDisp(e, 0, 4, 0x04);
    emitAddRegImm32(e, 0, STUB_OFF);
    emitAluRegReg(e, 0x39, 0, 2);
    emitJcc(e, 5, &l_direct_base);
    emitJmp(e, &l_helper);

    labelPatch(e, &l_hram);
    emitCmpRegImm32(e, 1, 0x0000FF80);
    emitJcc(e, 2, &l_io);
    emitCmpRegImm32(e, 1, 0x0000FFFF);
    emitJcc(e, 4, &l_helper);

    labelPatch(e, &l_direct);
    emitMovR32MemDisp(e, 2, 0, BASE_OFF);
    labelPatch(e, &l_direct_base);
    emitMovRegReg(e, 0, 1);
    emitAndRegImm32(e, 0, 0x000000FF);
    emitMovR8MemDisp(e, 5, 4, 0x0C);
    _ = emitByte(e, 0x88);
    _ = emitByte(e, 0x2C);
    _ = emitByte(e, 0x02);
    emitJmp(e, &l_done);

    labelPatch(e, &l_io);
    emitHelperWrite(e, true);
    emitJmp(e, &l_done);

    labelPatch(e, &l_helper);
    emitHelperWrite(e, false);
    labelPatch(e, &l_done);
}

fn emitBuildFlags(e: *Emit, n: bool, hmode: u8, cmode: u8) void {
    _ = emitByte(e, 0x9F);
    _ = emitByte(e, 0x88);
    _ = emitByte(e, 0xE1);
    _ = emitByte(e, 0x31);
    _ = emitByte(e, 0xC0);
    _ = emitByte(e, 0x88);
    _ = emitByte(e, 0xC8);
    _ = emitByte(e, 0x24);
    _ = emitByte(e, 0x40);
    _ = emitByte(e, 0xD0);
    _ = emitByte(e, 0xE0);

    if (hmode == H_AF) {
        emitAluRegReg(e, 0x88, 1, 5);
        _ = emitByte(e, 0x80);
        _ = emitByte(e, 0xE5);
        _ = emitByte(e, 0x10);
        _ = emitByte(e, 0xD0);
        _ = emitByte(e, 0xE5);
        _ = emitByte(e, 0x08);
        _ = emitByte(e, 0xE8);
    } else if (hmode == H_TRUE) {
        _ = emitByte(e, 0x0C);
        _ = emitByte(e, 0x20);
    }

    if (cmode == C_CF) {
        emitAluRegReg(e, 0x88, 1, 5);
        _ = emitByte(e, 0x80);
        _ = emitByte(e, 0xE5);
        _ = emitByte(e, 0x01);
        _ = emitByte(e, 0xC0);
        _ = emitByte(e, 0xE5);
        _ = emitByte(e, 0x04);
        _ = emitByte(e, 0x08);
        _ = emitByte(e, 0xE8);
    } else if (cmode == C_TRUE) {
        _ = emitByte(e, 0x0C);
        _ = emitByte(e, 0x10);
    } else if (cmode == C_OLD) {
        emitMovR8MemDisp(e, 5, 4, 0x0D);
        _ = emitByte(e, 0x80);
        _ = emitByte(e, 0xE5);
        _ = emitByte(e, 0x10);
        _ = emitByte(e, 0x08);
        _ = emitByte(e, 0xE8);
    }

    if (n) {
        _ = emitByte(e, 0x0C);
        _ = emitByte(e, 0x40);
    }
    emitStoreAFlags(e);
}

fn emitStoreAFlags(e: *Emit) void {
    emitMovEdxCpu(e);
    emitMovMemDispR8(e, 2, F_OFF, 0);
}

fn emitAluApply(e: *Emit, group: u8) void {
    switch (group) {
        0 => emitAluRegReg(e, 0x00, 1, 0),
        1 => emitAluRegReg(e, 0x10, 1, 0),
        2 => emitAluRegReg(e, 0x28, 1, 0),
        3 => emitAluRegReg(e, 0x18, 1, 0),
        4 => emitAluRegReg(e, 0x20, 1, 0),
        5 => emitAluRegReg(e, 0x30, 1, 0),
        6 => emitAluRegReg(e, 0x08, 1, 0),
        7 => emitAluRegReg(e, 0x38, 1, 0),
        else => {},
    }
}

fn emitAluFlags(e: *Emit, group: u8) void {
    switch (group) {
        0, 1 => emitBuildFlags(e, false, H_AF, C_CF),
        2, 3, 7 => emitBuildFlags(e, true, H_AF, C_CF),
        4 => emitBuildFlags(e, false, H_TRUE, C_FALSE),
        5, 6 => emitBuildFlags(e, false, H_FALSE, C_FALSE),
        else => {},
    }
}

fn emitLoadOldCarry(e: *Emit) void {
    emitMovEdxCpu(e);
    emitMovR8MemDisp(e, 2, 2, F_OFF);
    _ = emitByte(e, 0xC0);
    _ = emitByte(e, 0xE2);
    _ = emitByte(e, 0x04);
}

fn emitAluGroup(e: *Emit, group: u8, src: u8) void {
    if (src == 6) {
        emitAddrEcxHL(e);
        emitMemReadAl(e);
        emitAluRegReg(e, 0x88, 0, 1);
    } else {
        emitReadRegToAl(e, src);
        emitAluRegReg(e, 0x88, 0, 1);
    }
    emitLoadA(e);
    if (group == 1 or group == 3) emitLoadOldCarry(e);
    emitAluApply(e, group);
    if (group != 7) emitStoreA(e);
    emitAluFlags(e, group);
}

fn emitAddHl(e: *Emit, pair: u8) void {
    emitMovzxR32R16(e, 0, 7);
    switch (pair) {
        0 => emitMovzxR32R16(e, 1, 3),
        1 => emitMovzxR32R16(e, 1, 6),
        2 => emitMovzxR32R16(e, 1, 7),
        3 => emitMovzxR32R16(e, 1, 5),
        else => {},
    }
    emitMovMemDispR32(e, 4, 0x0C, 1);
    emitMovRegReg(e, 2, 0);
    emitAddRegReg32(e, 2, 1);
    emitMovMemDispR32(e, 4, 0x14, 2);
    emitAndRegImm32(e, 0, 0x00000FFF);
    emitAndRegImm32(e, 1, 0x00000FFF);
    emitAddRegReg32(e, 0, 1);
    emitCmpRegImm32(e, 0, 0x00000FFF);
    _ = emitByte(e, 0x0F);
    _ = emitByte(e, 0x97);
    _ = emitByte(e, 0xC1);
    emitMovzxR32R8(e, 1, 1);
    emitShlRegImm8(e, 1, 5);
    emitMovMemDispR32(e, 4, 0x10, 1);
    emitMovR32MemDisp(e, 0, 4, 0x14);
    _ = emitByte(e, 0x66);
    _ = emitByte(e, 0x89);
    _ = emitByte(e, 0xC7);
    emitShrRegImm8(e, 0, 16);
    emitAndRegImm32(e, 0, 1);
    emitShlRegImm8(e, 0, 4);
    emitMovMemDispR32(e, 4, 0x14, 0);
    emitMovEdxCpu(e);
    emitMovR8MemDisp(e, 0, 2, F_OFF);
    _ = emitByte(e, 0x24);
    _ = emitByte(e, 0x8F);
    emitMovR32MemDisp(e, 1, 4, 0x10);
    _ = emitByte(e, 0x08);
    _ = emitByte(e, 0xC8);
    emitMovR32MemDisp(e, 1, 4, 0x14);
    _ = emitByte(e, 0x08);
    _ = emitByte(e, 0xC8);
    emitStoreAFlags(e);
}

fn emitLdRr(e: *Emit, insn: BlockInsn) void {
    if (insn.b == 1) {
        emitMovRegReg(e, 5, 7);
        return;
    }
    switch (insn.a) {
        0 => emitMovRegImm32(e, 3, @intCast(u32, insn.imm)),
        1 => emitMovRegImm32(e, 6, @intCast(u32, insn.imm)),
        2 => emitMovRegImm32(e, 7, @intCast(u32, insn.imm)),
        3 => emitMovRegImm32(e, 5, @intCast(u32, insn.imm)),
        else => {},
    }
}

fn emitLdRn(e: *Emit, insn: BlockInsn) void {
    const value: u8 = @intCast(u8, insn.imm & 0xFF);
    if (insn.a == 6) {
        _ = emitByte(e, 0xB0);
        _ = emitByte(e, value);
        emitMovMemDispR8(e, 4, 0x0C, 0);
        emitAddrEcxHL(e);
        emitMemWrite(e);
        return;
    }
    _ = emitByte(e, 0xB0);
    _ = emitByte(e, value);
    emitWriteAlToReg(e, insn.a);
}

fn emitIncDec(e: *Emit, insn: BlockInsn) void {
    const dec: bool = (insn.b & 1) != 0;
    if ((insn.b & 0x80) != 0) {
        switch (insn.a) {
            0 => {
                _ = emitByte(e, 0x66);
                _ = emitByte(e, if (dec) 0x4B else 0x43);
            },
            1 => {
                _ = emitByte(e, 0x66);
                _ = emitByte(e, if (dec) 0x4E else 0x46);
            },
            2 => {
                _ = emitByte(e, 0x66);
                _ = emitByte(e, if (dec) 0x4F else 0x47);
            },
            3 => {
                _ = emitByte(e, 0x66);
                _ = emitByte(e, if (dec) 0x4D else 0x45);
            },
            else => {},
        }
        return;
    }

    if (insn.a == 6) {
        emitAddrEcxHL(e);
        emitMemReadAl(e);
    } else {
        emitReadRegToAl(e, insn.a);
    }
    emitMovEdxCpu(e);
    emitMovR8MemDisp(e, 2, 2, F_OFF);
    emitMovMemDispR8(e, 4, 0x0D, 2);
    _ = emitByte(e, 0xFE);
    _ = emitByte(e, if (dec) 0xC8 else 0xC0);
    emitMovMemDispR8(e, 4, 0x0C, 0);
    emitBuildFlags(e, dec, H_AF, C_OLD);
    if (insn.a == 6) {
        emitAddrEcxHL(e);
        emitMemWrite(e);
    } else {
        emitMovR8MemDisp(e, 0, 4, 0x0C);
        emitWriteAlToReg(e, insn.a);
    }
}

fn emitStoreAToAddrEcx(e: *Emit) void {
    emitLoadA(e);
    emitMovMemDispR8(e, 4, 0x0C, 0);
    emitMemWrite(e);
}

fn emitLoadAFromAddrEcx(e: *Emit) void {
    emitMemReadAl(e);
    emitStoreA(e);
}

fn emitLdMem(e: *Emit, insn: BlockInsn) void {
    const a: u8 = insn.a;
    if (a <= 7) {
        if (a == 6) {
            emitReadRegToAl(e, insn.b);
            emitMovMemDispR8(e, 4, 0x0C, 0);
            emitAddrEcxHL(e);
            emitMemWrite(e);
            return;
        }
        if (insn.b == 6) {
            emitAddrEcxHL(e);
            emitMemReadAl(e);
            emitWriteAlToReg(e, a);
            return;
        }
        emitReadRegToAl(e, insn.b);
        emitWriteAlToReg(e, a);
        return;
    }

    if (a >= 8 and a <= 11) {
        switch (a) {
            8 => emitAddrEcxBC(e),
            9 => emitAddrEcxDE(e),
            else => emitAddrEcxHL(e),
        }
        if (insn.b == 0) {
            emitLoadA(e);
            emitMovMemDispR8(e, 4, 0x0C, 0);
            emitMemWrite(e);
        } else {
            emitMemReadAl(e);
            emitStoreA(e);
        }
        if (a == 10) {
            _ = emitByte(e, 0x66);
            _ = emitByte(e, 0x47);
        } else if (a == 11) {
            _ = emitByte(e, 0x66);
            _ = emitByte(e, 0x4F);
        }
        return;
    }

    if (a == 12) {
        const addr: u16 = @intCast(u16, 0xFF00 | (@as(u16, insn.imm) & 0xFF));
        emitAddrEcxImm(e, addr);
        if (insn.b == 1) {
            emitLoadAFromAddrEcx(e);
        } else {
            emitStoreAToAddrEcx(e);
        }
        return;
    }

    if (a == 13) {
        emitAddrEcxImm(e, insn.imm);
        if (insn.b == 1) {
            emitLoadAFromAddrEcx(e);
        } else {
            emitStoreAToAddrEcx(e);
        }
        return;
    }

    if (a == 14) {
        emitAddrEcxImm(e, insn.imm);
        emitMovRegReg(e, 0, 5);
        emitMovMemDispR8(e, 4, 0x0C, 0);
        emitMemWrite(e);
        emitAddrEcxImm(e, insn.imm +% 1);
        emitMovRegReg(e, 0, 5);
        emitShrRegImm8(e, 0, 8);
        emitMovMemDispR8(e, 4, 0x0C, 0);
        emitMemWrite(e);
        return;
    }

    if (a == 15) {
        emitAddrEcxC(e);
        if (insn.b == 1) {
            emitLoadAFromAddrEcx(e);
        } else {
            emitStoreAToAddrEcx(e);
        }
        return;
    }
}

fn emitInsn(e: *Emit, insn: BlockInsn) void {
    switch (insn.op) {
        .nop => {},
        .ld_rr => emitLdRr(e, insn),
        .ld_rn => emitLdRn(e, insn),
        .ld_mem => emitLdMem(e, insn),
        .alu_r => {
            if (insn.a == 8) {
                emitAddHl(e, insn.b);
            } else {
                emitAluGroup(e, insn.a, insn.b);
            }
        },
        .alu_n => {
            _ = emitByte(e, 0xB1);
            _ = emitByte(e, @intCast(u8, insn.imm & 0xFF));
            emitLoadA(e);
            if (insn.a == 1 or insn.a == 3) emitLoadOldCarry(e);
            emitAluApply(e, insn.a);
            if (insn.a != 7) emitStoreA(e);
            emitAluFlags(e, insn.a);
        },
        .incdec => emitIncDec(e, insn),
        else => {},
    }
}

fn insnLen(insn: BlockInsn) u8 {
    switch (insn.op) {
        .nop => return 1,
        .ld_rr => return if (insn.b == 1) 1 else 3,
        .ld_rn => return 2,
        .ld_mem => {
            switch (insn.a) {
                0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 15 => return 1,
                12 => return 2,
                13, 14 => return 3,
                else => return 0,
            }
        },
        .alu_r => return 1,
        .alu_n => return 2,
        .incdec => return 1,
        else => return 0,
    }
}

fn insnValid(insn: BlockInsn) bool {
    switch (insn.op) {
        .nop => return true,
        .ld_rr => {
            if (insn.a > 3) return false;
            if (insn.b > 1) return false;
            return !(insn.b == 1 and insn.a != 3);
        },
        .ld_rn => return insn.a <= 7,
        .ld_mem => {
            if (insn.a <= 7) {
                if (insn.b > 7) return false;
                if (insn.a == 6 and insn.b == 6) return false;
                return true;
            }
            if (insn.a >= 8 and insn.a <= 11) return insn.b <= 1;
            if (insn.a == 12 or insn.a == 13 or insn.a == 15) return insn.b <= 1;
            if (insn.a == 14) return true;
            return false;
        },
        .alu_r => {
            if (insn.a == 8) return insn.b <= 3;
            if (insn.a > 7) return false;
            return insn.b <= 7;
        },
        .alu_n => return insn.a <= 7,
        .incdec => {
            if ((insn.b & 0x80) != 0) return insn.a <= 3;
            return insn.a <= 7;
        },
        else => return false,
    }
}

fn emitPrologue(e: *Emit) void {
    _ = emitByte(e, 0x8B);
    _ = emitByte(e, 0x44);
    _ = emitByte(e, 0x24);
    _ = emitByte(e, 0x04);
    _ = emitByte(e, 0x8B);
    _ = emitByte(e, 0x10);
    _ = emitByte(e, 0x8B);
    _ = emitByte(e, 0x48);
    _ = emitByte(e, 0x04);
    _ = emitByte(e, 0x53);
    _ = emitByte(e, 0x56);
    _ = emitByte(e, 0x57);
    _ = emitByte(e, 0x55);
    _ = emitByte(e, 0x83);
    _ = emitByte(e, 0xEC);
    _ = emitByte(e, 0x20);
    emitMovMemDispR32(e, 4, 0x00, 2);
    emitMovMemDispR32(e, 4, 0x04, 1);
    emitMovMemDispR32(e, 4, 0x08, 0);
    emitMovEdxCpu(e);
    emitMovzxR32Mem8(e, 3, 2, C_OFF);
    emitMovzxR32Mem8(e, 0, 2, B_OFF);
    emitShlRegImm8(e, 0, 8);
    emitOrRegReg32(e, 3, 0);
    emitMovzxR32Mem8(e, 6, 2, E_OFF);
    emitMovzxR32Mem8(e, 0, 2, D_OFF);
    emitShlRegImm8(e, 0, 8);
    emitOrRegReg32(e, 6, 0);
    emitMovzxR32Mem8(e, 7, 2, L_OFF);
    emitMovzxR32Mem8(e, 0, 2, H_OFF);
    emitShlRegImm8(e, 0, 8);
    emitOrRegReg32(e, 7, 0);
    emitMovzxR32Mem16(e, 5, 2, SP_OFF);
}

fn emitEpilogue(e: *Emit, next_pc: u16, cycles: u32) void {
    emitMovEdxCpu(e);
    emitMovMemDispR8(e, 2, C_OFF, 3);
    emitMovRegReg(e, 0, 3);
    emitShrRegImm8(e, 0, 8);
    emitMovMemDispR8(e, 2, B_OFF, 0);
    emitMovRegReg(e, 0, 6);
    emitMovMemDispR8(e, 2, E_OFF, 0);
    emitShrRegImm8(e, 0, 8);
    emitMovMemDispR8(e, 2, D_OFF, 0);
    emitMovRegReg(e, 0, 7);
    emitMovMemDispR8(e, 2, L_OFF, 0);
    emitShrRegImm8(e, 0, 8);
    emitMovMemDispR8(e, 2, H_OFF, 0);
    _ = emitByte(e, 0x66);
    _ = emitByte(e, 0x89);
    _ = emitByte(e, modrmDisp8(5, 2));
    _ = emitByte(e, SP_OFF);
    _ = emitByte(e, 0x66);
    _ = emitByte(e, 0xC7);
    _ = emitByte(e, modrmDisp8(0, 2));
    _ = emitByte(e, PC_OFF);
    emitU16(e, next_pc);
    _ = emitByte(e, 0xB8);
    emitImm32(e, cycles);
    _ = emitByte(e, 0x83);
    _ = emitByte(e, 0xC4);
    _ = emitByte(e, 0x20);
    _ = emitByte(e, 0x5D);
    _ = emitByte(e, 0x5F);
    _ = emitByte(e, 0x5E);
    _ = emitByte(e, 0x5B);
    _ = emitByte(e, 0xC3);
}

pub fn emitBlock(e: *Emit, block: *const Block) bool {
    var i: usize = 0;
    var pc: u16 = block.start_pc;
    while (i < @intCast(usize, block.len)) : (i += 1) {
        const insn: BlockInsn = block.insns[i];
        if (!insnValid(insn)) return false;
        const len: u8 = insnLen(insn);
        if (len == 0) return false;
        pc = pc +% @intCast(u16, len);
    }

    const start: usize = e.len;
    emitPrologue(e);
    i = 0;
    while (i < @intCast(usize, block.len)) : (i += 1) {
        emitInsn(e, block.insns[i]);
    }
    emitEpilogue(e, pc, block.cycles);
    if (e.len > e.cap) {
        if (start <= e.cap) e.len = start;
        return false;
    }
    return true;
}
