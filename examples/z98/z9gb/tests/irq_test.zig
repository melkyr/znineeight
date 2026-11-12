// irq_test.zig — VBlank and joypad interrupt requests plus IF read masks.
//
// Run as a normal executable under both -ffast and -fsafe. Every check is
// counted; the process exits 0 only when all checks pass.

const std = @import("std");
const cartmod = @import("../cart.zig");
const mmumod = @import("../mmu.zig");
const ppumod = @import("../ppu.zig");

const LINE_DOTS: u32 = 456;

var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_ppu: ppumod.Ppu = undefined;
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

fn reset() void {
    cartmod.cartInit(&g_cart);
    mmumod.busInit(&g_bus, &g_cart);
    ppumod.ppuReset(&g_ppu);
    g_bus.io[0x0F] = 0;
}

fn testVblankOnce() void {
    reset();
    ppumod.ppuTick(&g_ppu, 154 * LINE_DOTS, &g_bus);
    checkByte("vblank frame sets if", g_bus.io[0x0F] & 0x01, 0x01);

    g_bus.io[0x0F] = 0;
    ppumod.ppuTick(&g_ppu, 143 * LINE_DOTS, &g_bus);
    ppumod.ppuTick(&g_ppu, LINE_DOTS, &g_bus);
    checkByte("vblank entry raises", g_bus.io[0x0F] & 0x01, 0x01);

    g_bus.io[0x0F] = 0;
    ppumod.ppuTick(&g_ppu, LINE_DOTS, &g_bus);
    checkByte("vblank line quiet", g_bus.io[0x0F] & 0x01, 0x00);
    ppumod.ppuTick(&g_ppu, 9 * LINE_DOTS, &g_bus);
    checkByte("vblank frame remainder quiet", g_bus.io[0x0F] & 0x01, 0x00);
    ppumod.ppuTick(&g_ppu, 144 * LINE_DOTS, &g_bus);
    checkByte("vblank next frame raises", g_bus.io[0x0F] & 0x01, 0x01);
}

fn testVblankLcdOff() void {
    reset();
    ppumod.ppuWrite(&g_ppu, 0xFF40, 0x11, &g_bus);
    g_bus.io[0x0F] = 0;
    ppumod.ppuTick(&g_ppu, 155 * LINE_DOTS, &g_bus);
    checkByte("vblank lcd off quiet", g_bus.io[0x0F] & 0x01, 0x00);
    checkByte("vblank lcd off line", g_ppu.line, 0);
    checkByte("vblank lcd off dot", @intCast(u8, g_ppu.dot), 0);

    g_bus.io[0x0F] = 0;
    ppumod.ppuWrite(&g_ppu, 0xFF40, 0x91, &g_bus);
    ppumod.ppuTick(&g_ppu, 143 * LINE_DOTS, &g_bus);
    checkByte("vblank lcd off at 143 line", g_ppu.line, 143);
    ppumod.ppuWrite(&g_ppu, 0xFF40, 0x11, &g_bus);
    ppumod.ppuTick(&g_ppu, LINE_DOTS, &g_bus);
    checkByte("vblank lcd off disable quiet", g_bus.io[0x0F] & 0x01, 0x00);
}

fn testJoypadIrq() void {
    reset();
    g_bus.io[0x00] = 0x1F;
    mmumod.busApplyButtons(&g_bus, 0x01);
    checkByte("joypad direction raises", g_bus.io[0x0F] & 0x10, 0x10);

    g_bus.io[0x0F] = 0;
    mmumod.busApplyButtons(&g_bus, 0x01);
    checkByte("joypad held quiet", g_bus.io[0x0F] & 0x10, 0x00);

    mmumod.busApplyButtons(&g_bus, 0x00);
    checkByte("joypad release quiet", g_bus.io[0x0F] & 0x10, 0x00);
}

fn testJoypadUnselected() void {
    reset();
    g_bus.io[0x00] = 0x2F;
    mmumod.busApplyButtons(&g_bus, 0x01);
    checkByte("joypad unselected direction quiet", g_bus.io[0x0F] & 0x10, 0x00);

    mmumod.busApplyButtons(&g_bus, 0x10);
    checkByte("joypad selected button raises", g_bus.io[0x0F] & 0x10, 0x10);
}

fn testIfReadMask() void {
    reset();
    g_bus.io[0x0F] = 0x00;
    checkByte("if read mask zero", mmumod.ioRead(&g_bus, 0xFF0F), 0xE0);

    g_bus.io[0x0F] = 0x0F;
    checkByte("if read mask value", mmumod.ioRead(&g_bus, 0xFF0F), 0xEF);
}

pub fn main() void {
    testVblankOnce();
    testVblankLcdOff();
    testJoypadIrq();
    testJoypadUnselected();
    testIfReadMask();

    if (g_fail == 0) {
        std.io.write("irq ok ");
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
