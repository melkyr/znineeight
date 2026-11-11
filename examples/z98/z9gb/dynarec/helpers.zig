// helpers.zig — cdecl memory helpers for the z9gb dynarec.
//
// Generated blocks embed these addresses with @ptrToInt. Before any helper
// observes bus state it charges the cycles accumulated since the previous
// sync through busTick and zeroes DynCtx.cycles, so IO/timer/PPU/serial/RTC
// state is current at the helper boundary. Bus.read8/write8 keep the
// interpreter's RTC, cart-RAM stub, OAM/VRAM lockout, and OAM-DMA semantics.

const ctxmod = @import("ctx.zig");
const mmumod = @import("../mmu.zig");

pub const DynCtx = ctxmod.DynCtx;

fn syncCtx(ctx: *DynCtx) void {
    const n: u32 = ctx.cycles;
    ctx.cycles = 0;
    if (n != 0) mmumod.busTick(ctx.bus, n);
}

pub extern "c" fn helperRead8(ctx: *DynCtx, addr: u16) u8 {
    syncCtx(ctx);
    return mmumod.read8(ctx.bus, addr);
}

pub extern "c" fn helperWrite8(ctx: *DynCtx, addr: u16, value: u8) void {
    syncCtx(ctx);
    mmumod.write8(ctx.bus, addr, value);
}

pub extern "c" fn helperIoRead(ctx: *DynCtx, addr: u16) u8 {
    syncCtx(ctx);
    return mmumod.read8(ctx.bus, addr);
}

pub extern "c" fn helperIoWrite(ctx: *DynCtx, addr: u16, value: u8) void {
    syncCtx(ctx);
    mmumod.write8(ctx.bus, addr, value);
}

pub extern "c" fn helperSync(ctx: *DynCtx) void {
    syncCtx(ctx);
}
