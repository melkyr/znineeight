// helpers.zig — cdecl memory helpers for the z9gb dynarec.
//
// Generated blocks embed these addresses with @ptrToInt. Before any helper
// observes bus state it charges the cycles accumulated since the previous
// sync through busTick and zeroes DynCtx.cycles, so IO/timer/PPU/serial/RTC
// state is current at the helper boundary. Bus.read8/write8 keep the
// interpreter's RTC, cart-RAM stub, OAM/VRAM lockout, and OAM-DMA semantics.

const ctxmod = @import("ctx.zig");
const mmumod = @import("../mmu.zig");
const ppumod = @import("../ppu.zig");

pub const DynCtx = ctxmod.DynCtx;

fn syncCtx(ctx: *DynCtx) void {
    const n: u32 = ctx.cycles;
    ctx.cycles = 0;
    if (n != 0) mmumod.busTick(ctx.bus, n);
}

fn syncPpuIn(ctx: *DynCtx) void {
    const b = ctx.bus;
    const p = ctx.ppu;
    ppumod.ppuWrite(p, 0xFF40, b.io[0x40], b);
    ppumod.ppuWrite(p, 0xFF41, b.io[0x41], b);
    ppumod.ppuWrite(p, 0xFF42, b.io[0x42], b);
    ppumod.ppuWrite(p, 0xFF43, b.io[0x43], b);
    if (b.lyc_dirty or b.io[0x45] != p.lyc) {
        b.lyc_dirty = false;
        ppumod.ppuWrite(p, 0xFF45, b.io[0x45], b);
    }
    ppumod.ppuWrite(p, 0xFF46, b.io[0x46], b);
    ppumod.ppuWrite(p, 0xFF47, b.io[0x47], b);
    ppumod.ppuWrite(p, 0xFF48, b.io[0x48], b);
    ppumod.ppuWrite(p, 0xFF49, b.io[0x49], b);
    ppumod.ppuWrite(p, 0xFF4A, b.io[0x4A], b);
    ppumod.ppuWrite(p, 0xFF4B, b.io[0x4B], b);
}

fn syncPpuOut(ctx: *DynCtx) void {
    const b = ctx.bus;
    const p = ctx.ppu;
    b.io[0x41] = ppumod.ppuRead(p, 0xFF41);
    b.io[0x44] = ppumod.ppuRead(p, 0xFF44);
}

fn syncCtxPpu(ctx: *DynCtx) void {
    const n: u32 = ctx.cycles;
    ctx.cycles = 0;
    if (n != 0) mmumod.busTick(ctx.bus, n);

    const pre: u32 = if (ctx.ppu_pending > ctx.instr_cycles) ctx.ppu_pending - ctx.instr_cycles else 0;
    const dots: u32 = if (ctx.bus.double_speed) pre / 2 else pre;
    if (pre != 0) {
        syncPpuIn(ctx);
        ppumod.ppuTick(ctx.ppu, dots, ctx.bus);
        syncPpuOut(ctx);
        ctx.ppu_advanced_dots +%= dots;
    }
    ctx.ppu_pending = ctx.instr_cycles;
}

pub extern "c" fn helperRead8(ctx: *DynCtx, addr: u16) u8 {
    syncCtxPpu(ctx);
    return mmumod.read8(ctx.bus, addr);
}

pub extern "c" fn helperWrite8(ctx: *DynCtx, addr: u16, value: u8) void {
    syncCtxPpu(ctx);
    mmumod.write8(ctx.bus, addr, value);
}

pub extern "c" fn helperIoRead(ctx: *DynCtx, addr: u16) u8 {
    syncCtxPpu(ctx);
    return mmumod.read8(ctx.bus, addr);
}

pub extern "c" fn helperIoWrite(ctx: *DynCtx, addr: u16, value: u8) void {
    syncCtxPpu(ctx);
    mmumod.write8(ctx.bus, addr, value);
}

pub extern "c" fn helperSync(ctx: *DynCtx) void {
    syncCtx(ctx);
}
