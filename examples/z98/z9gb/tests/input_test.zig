// input_test.zig — JOYP FF00 selection, active-low buttons, and write masks.
//
// Run as a normal executable under both -ffast and -fsafe. Every check is
// counted; the process exits 0 only when all checks pass.

const std = @import("std");
const emumod = @import("../emu.zig");
const mmumod = @import("../mmu.zig");

const D_SEL: u8 = 0x10;
const B_SEL: u8 = 0x20;

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

fn reset() void {
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = false, .serial_log = false, .turbo = true, .dynarec = false });
}

fn lowNibble() u8 {
    return @intCast(u8, mmumod.read8(&g_emu.bus, 0xFF00) & 0x0F);
}

fn select(sel: u8) void {
    mmumod.write8(&g_emu.bus, 0xFF00, sel);
}

fn testDirections() void {
    reset();
    emumod.emuSetButtons(&g_emu, 0x01);
    select(D_SEL);
    checkByte("right low", lowNibble(), 0x0E);
    emumod.emuSetButtons(&g_emu, 0x02);
    select(D_SEL);
    checkByte("left low", lowNibble(), 0x0D);
    emumod.emuSetButtons(&g_emu, 0x04);
    select(D_SEL);
    checkByte("up low", lowNibble(), 0x0B);
    emumod.emuSetButtons(&g_emu, 0x08);
    select(D_SEL);
    checkByte("down low", lowNibble(), 0x07);

    emumod.emuSetButtons(&g_emu, 0x00);
    select(D_SEL);
    checkByte("directions idle low", lowNibble(), 0x0F);
}

fn testButtons() void {
    reset();
    emumod.emuSetButtons(&g_emu, 0x10);
    select(B_SEL);
    checkByte("A low", lowNibble(), 0x0E);
    emumod.emuSetButtons(&g_emu, 0x20);
    select(B_SEL);
    checkByte("B low", lowNibble(), 0x0D);
    emumod.emuSetButtons(&g_emu, 0x40);
    select(B_SEL);
    checkByte("Select low", lowNibble(), 0x0B);
    emumod.emuSetButtons(&g_emu, 0x80);
    select(B_SEL);
    checkByte("Start low", lowNibble(), 0x07);

    emumod.emuSetButtons(&g_emu, 0x00);
    select(B_SEL);
    checkByte("buttons idle low", lowNibble(), 0x0F);
}

fn testUnselectedGroup() void {
    reset();
    emumod.emuSetButtons(&g_emu, 0x10);
    select(D_SEL);
    checkByte("button ignored while directions selected", lowNibble(), 0x0F);

    emumod.emuSetButtons(&g_emu, 0x01);
    select(B_SEL);
    checkByte("direction ignored while buttons selected", lowNibble(), 0x0F);
}

fn testBothGroups() void {
    reset();
    emumod.emuSetButtons(&g_emu, 0x21);
    select(0x00);
    checkByte("right plus B combine", lowNibble(), 0x0C);

    emumod.emuSetButtons(&g_emu, 0x00);
    select(0x00);
    checkByte("both selected idle low", lowNibble(), 0x0F);
}

fn testWriteMask() void {
    reset();
    emumod.emuSetButtons(&g_emu, 0x00);
    select(0x00);
    checkByte("write 0x00 readback", mmumod.read8(&g_emu.bus, 0xFF00), 0xCF);
    checkByte("write 0x00 keeps bits 7-6", @intCast(u8, g_emu.bus.io[0] & 0xC0), 0xC0);

    select(0x3F);
    checkByte("write updates bits 5-4", @intCast(u8, g_emu.bus.io[0] & 0x30), 0x30);
    checkByte("write 0x3F keeps bits 7-6", @intCast(u8, g_emu.bus.io[0] & 0xC0), 0xC0);
    checkByte("write keeps low reset", @intCast(u8, g_emu.bus.io[0] & 0x0F), 0x0F);
    checkByte("write 0x3F readback", mmumod.read8(&g_emu.bus, 0xFF00), 0xFF);

    select(0xCF);
    checkByte("write ignores low nibble", @intCast(u8, g_emu.bus.io[0] & 0x0F), 0x0F);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;
    testDirections();
    testButtons();
    testUnselectedGroup();
    testBothGroups();
    testWriteMask();

    if (g_fail == 0) {
        std.io.write("input ok ");
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
