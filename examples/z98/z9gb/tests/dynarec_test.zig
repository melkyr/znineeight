// dynarec_test.zig — block IR builder checks against the interpreter oracle.
//
// Run as a normal executable under both -ffast and -fsafe. Every check is
// counted; the process exits 0 only when all checks pass.

const std = @import("std");
const cartmod = @import("../cart.zig");
const mmumod = @import("../mmu.zig");
const cpumod = @import("../cpu.zig");
const blockmod = @import("../dynarec/block.zig");

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

fn checkU32(label: []const u8, got: u32, want: u32) void {
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

fn checkU16(label: []const u8, got: u16, want: u16) void {
    checkU32(label, @intCast(u32, got), @intCast(u32, want));
}

fn checkBool(label: []const u8, got: bool, want: bool) void {
    if (got == want) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    if (got) {
        std.io.write(" got=true want=false\n");
    } else {
        std.io.write(" got=false want=true\n");
    }
}

fn checkOp(label: []const u8, got: blockmod.BlockOp, want: blockmod.BlockOp) void {
    checkBool(label, got == want, true);
}

fn testStraightNops() void {
    reset();
    var i: u16 = 0;
    while (i < 70) : (i += 1) mmumod.write8(&g_bus, 0xC000 +% i, 0x00);
    g_cpu.pc = 0xC000;
    var blk: blockmod.Block = undefined;
    checkBool("nops build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("nops len", @intCast(u32, blk.len), 64);
    checkU32("nops cycles", blk.cycles, 256);
    checkBool("nops cap is not a terminal insn", blk.ends_block, false);
    checkOp("nops last op", blk.insns[63].op, blockmod.BlockOp.nop);
    var sum: u32 = 0;
    i = 0;
    while (i < 64) : (i += 1) sum +%= cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("nops interp cycles", sum, blk.cycles);
    checkU16("nops interp pc", g_cpu.pc, 0xC040);
}

fn testJump() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0xC3);
    mmumod.write8(&g_bus, 0xC001, 0x34);
    mmumod.write8(&g_bus, 0xC002, 0x12);
    g_cpu.pc = 0xC000;
    var blk: blockmod.Block = undefined;
    checkBool("jp build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("jp len", @intCast(u32, blk.len), 1);
    checkOp("jp op", blk.insns[0].op, blockmod.BlockOp.jump);
    checkU32("jp a", @intCast(u32, blk.insns[0].a), 4);
    checkU32("jp b", @intCast(u32, blk.insns[0].b), 0);
    checkU16("jp target", blk.insns[0].imm, 0x1234);
    checkU32("jp cycles", blk.cycles, 16);
    checkBool("jp ends", blk.ends_block, true);
    const used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("jp interp cycles", used, blk.cycles);
    checkU16("jp interp pc", g_cpu.pc, 0x1234);
}

fn testConditionalJr() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0x20);
    mmumod.write8(&g_bus, 0xC001, 0x05);
    g_cpu.pc = 0xC000;
    g_cpu.f = 0x80;
    var blk: blockmod.Block = undefined;
    checkBool("jr nz build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("jr nz len", @intCast(u32, blk.len), 1);
    checkOp("jr nz op", blk.insns[0].op, blockmod.BlockOp.jump);
    checkU32("jr nz a", @intCast(u32, blk.insns[0].a), 0);
    checkU32("jr nz b", @intCast(u32, blk.insns[0].b), 1);
    checkU16("jr nz target", blk.insns[0].imm, 0xC007);
    checkU32("jr nz base cycles", blk.cycles, 8);
    checkBool("jr nz ends", blk.ends_block, true);
    var used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("jr not-taken interp cycles", used, 8);
    checkU16("jr not-taken interp pc", g_cpu.pc, 0xC002);

    g_cpu.pc = 0xC000;
    g_cpu.f = 0;
    checkBool("jr taken build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU16("jr taken target", blk.insns[0].imm, 0xC007);
    checkU32("jr taken base cycles", blk.cycles, 8);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("jr taken interp cycles", used, 12);
    checkU32("jr taken adds four", used, blk.cycles + 4);
    checkU16("jr taken interp pc", g_cpu.pc, 0xC007);
}

fn testConditionalJp() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0xCA);
    mmumod.write8(&g_bus, 0xC001, 0x34);
    mmumod.write8(&g_bus, 0xC002, 0x12);
    g_cpu.pc = 0xC000;
    g_cpu.f = 0x80;
    var blk: blockmod.Block = undefined;
    checkBool("jp z build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("jp z a", @intCast(u32, blk.insns[0].a), 1);
    checkU16("jp z target", blk.insns[0].imm, 0x1234);
    checkU32("jp z base cycles", blk.cycles, 12);
    var used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("jp z taken interp cycles", used, 16);
    checkU16("jp z taken interp pc", g_cpu.pc, 0x1234);

    g_cpu.pc = 0xC000;
    g_cpu.f = 0;
    checkBool("jp nz build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("jp z not-taken interp cycles", used, 12);
    checkU16("jp z not-taken interp pc", g_cpu.pc, 0xC003);
}

fn testCall() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0xCD);
    mmumod.write8(&g_bus, 0xC001, 0x34);
    mmumod.write8(&g_bus, 0xC002, 0x12);
    g_cpu.pc = 0xC000;
    g_cpu.sp = 0xD000;
    var blk: blockmod.Block = undefined;
    checkBool("call build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("call len", @intCast(u32, blk.len), 1);
    checkOp("call op", blk.insns[0].op, blockmod.BlockOp.call);
    checkU32("call a", @intCast(u32, blk.insns[0].a), 4);
    checkU32("call b", @intCast(u32, blk.insns[0].b), 0);
    checkU16("call target", blk.insns[0].imm, 0x1234);
    checkU32("call cycles", blk.cycles, 24);
    checkBool("call ends", blk.ends_block, true);
    const used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("call interp cycles", used, blk.cycles);
    checkU16("call interp pc", g_cpu.pc, 0x1234);
    checkU16("call interp sp", g_cpu.sp, 0xCFFE);
    checkU32("call return lo", @intCast(u32, mmumod.read8(&g_bus, 0xCFFE)), 0x03);
    checkU32("call return hi", @intCast(u32, mmumod.read8(&g_bus, 0xCFFF)), 0xC0);
}

fn testRet() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0xC9);
    mmumod.write8(&g_bus, 0xD000, 0x34);
    mmumod.write8(&g_bus, 0xD001, 0x12);
    g_cpu.pc = 0xC000;
    g_cpu.sp = 0xD000;
    var blk: blockmod.Block = undefined;
    checkBool("ret build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ret len", @intCast(u32, blk.len), 1);
    checkOp("ret op", blk.insns[0].op, blockmod.BlockOp.ret);
    checkU32("ret a", @intCast(u32, blk.insns[0].a), 4);
    checkU32("ret b", @intCast(u32, blk.insns[0].b), 0);
    checkU32("ret cycles", blk.cycles, 16);
    checkBool("ret ends", blk.ends_block, true);
    const used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("ret interp cycles", used, blk.cycles);
    checkU16("ret interp pc", g_cpu.pc, 0x1234);
    checkU16("ret interp sp", g_cpu.sp, 0xD002);
}

fn testHalt() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0x76);
    g_cpu.pc = 0xC000;
    var blk: blockmod.Block = undefined;
    checkBool("halt build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("halt len", @intCast(u32, blk.len), 1);
    checkOp("halt op", blk.insns[0].op, blockmod.BlockOp.unsupported);
    checkU32("halt raw op", @intCast(u32, blk.insns[0].a), 0x76);
    checkU32("halt cycles", blk.cycles, 4);
    checkBool("halt ends", blk.ends_block, true);
    const used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("halt interp cycles", used, blk.cycles);
    checkBool("halt interp halted", g_cpu.halted, true);
    checkU16("halt interp pc", g_cpu.pc, 0xC001);
}

fn testStop() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0x10);
    mmumod.write8(&g_bus, 0xC001, 0x00);
    g_cpu.pc = 0xC000;
    var blk: blockmod.Block = undefined;
    checkBool("stop build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("stop len", @intCast(u32, blk.len), 1);
    checkOp("stop op", blk.insns[0].op, blockmod.BlockOp.unsupported);
    checkU32("stop raw op", @intCast(u32, blk.insns[0].a), 0x10);
    checkU32("stop cycles", blk.cycles, 4);
    checkBool("stop ends", blk.ends_block, true);
    const used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("stop interp cycles", used, blk.cycles);
    checkBool("stop interp halted", g_cpu.halted, true);
    checkU16("stop interp pc", g_cpu.pc, 0xC002);
}

fn testCbBoundary() void {
    reset();
    var i: u16 = 0;
    while (i < 63) : (i += 1) mmumod.write8(&g_bus, 0xC000 +% i, 0x00);
    mmumod.write8(&g_bus, 0xC03F, 0xCB);
    mmumod.write8(&g_bus, 0xC040, 0x37);
    g_cpu.pc = 0xC000;
    var blk: blockmod.Block = undefined;
    checkBool("cb build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("cb len", @intCast(u32, blk.len), 64);
    checkU32("cb cycles", blk.cycles, 260);
    checkBool("cb cap is not a terminal insn", blk.ends_block, false);
    checkOp("cb last op", blk.insns[63].op, blockmod.BlockOp.cb);
    checkU32("cb second byte", @intCast(u32, blk.insns[63].a), 0x37);
    var sum: u32 = 0;
    i = 0;
    while (i < 64) : (i += 1) sum +%= cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("cb interp cycles", sum, blk.cycles);
    checkU16("cb interp pc", g_cpu.pc, 0xC041);
}

fn testInterruptBoundaries() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0xFB);
    g_cpu.pc = 0xC000;
    var blk: blockmod.Block = undefined;
    checkBool("ei build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkOp("ei op", blk.insns[0].op, blockmod.BlockOp.unsupported);
    checkU32("ei raw op", @intCast(u32, blk.insns[0].a), 0xFB);
    checkBool("ei ends", blk.ends_block, true);
    var used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("ei interp cycles", used, blk.cycles);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xF3);
    g_cpu.pc = 0xC000;
    checkBool("di build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkOp("di op", blk.insns[0].op, blockmod.BlockOp.unsupported);
    checkU32("di raw op", @intCast(u32, blk.insns[0].a), 0xF3);
    checkBool("di ends", blk.ends_block, true);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("di interp cycles", used, blk.cycles);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xD9);
    mmumod.write8(&g_bus, 0xD000, 0x34);
    mmumod.write8(&g_bus, 0xD001, 0x12);
    g_cpu.pc = 0xC000;
    g_cpu.sp = 0xD000;
    checkBool("reti build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkOp("reti op", blk.insns[0].op, blockmod.BlockOp.ret);
    checkU32("reti a", @intCast(u32, blk.insns[0].a), 4);
    checkU32("reti b", @intCast(u32, blk.insns[0].b), 1);
    checkBool("reti ends", blk.ends_block, true);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("reti interp cycles", used, blk.cycles);
    checkU16("reti interp pc", g_cpu.pc, 0x1234);
    checkBool("reti interp ime", g_cpu.ime, true);
}

fn testWriteBoundaries() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0xEA);
    mmumod.write8(&g_bus, 0xC001, 0x46);
    mmumod.write8(&g_bus, 0xC002, 0xFF);
    g_cpu.pc = 0xC000;
    var blk: blockmod.Block = undefined;
    checkBool("io write build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkOp("io write op", blk.insns[0].op, blockmod.BlockOp.ld_mem);
    checkU16("io write addr", blk.insns[0].imm, 0xFF46);
    checkU32("io write cycles", blk.cycles, 16);
    checkBool("io write ends", blk.ends_block, true);
    var used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("io write interp cycles", used, blk.cycles);
    checkBool("io write starts dma", g_bus.dma.active, true);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xE0);
    mmumod.write8(&g_bus, 0xC001, 0x40);
    g_cpu.pc = 0xC000;
    checkBool("ldh write build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ldh write a", @intCast(u32, blk.insns[0].a), 12);
    checkU32("ldh write b", @intCast(u32, blk.insns[0].b), 0);
    checkU16("ldh write addr", blk.insns[0].imm, 0x0040);
    checkU32("ldh write cycles", blk.cycles, 12);
    checkBool("ldh write ends", blk.ends_block, true);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("ldh write interp cycles", used, blk.cycles);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xEA);
    mmumod.write8(&g_bus, 0xC001, 0x00);
    mmumod.write8(&g_bus, 0xC002, 0x20);
    g_cpu.pc = 0xC000;
    checkBool("rom write build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU16("rom write addr", blk.insns[0].imm, 0x2000);
    checkBool("rom write ends", blk.ends_block, true);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("rom write interp cycles", used, blk.cycles);
}

fn testIndirectWriteBoundaries() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0x77);
    g_cpu.pc = 0xC000;
    g_cpu.a = 0x5A;
    g_cpu.h = 0xC1;
    g_cpu.l = 0x00;
    var blk: blockmod.Block = undefined;
    checkBool("ld hl,a write build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ld hl,a write len", @intCast(u32, blk.len), 1);
    checkOp("ld hl,a write op", blk.insns[0].op, blockmod.BlockOp.ld_mem);
    checkU32("ld hl,a write a", @intCast(u32, blk.insns[0].a), 6);
    checkU32("ld hl,a write b", @intCast(u32, blk.insns[0].b), 7);
    checkBool("ld hl,a write ends", blk.ends_block, true);
    var used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("ld hl,a write interp cycles", used, blk.cycles);
    checkU32("ld hl,a write stored", @intCast(u32, mmumod.read8(&g_bus, 0xC100)), 0x5A);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x02);
    g_cpu.pc = 0xC000;
    g_cpu.a = 0xA5;
    g_cpu.b = 0xC2;
    g_cpu.c = 0x00;
    checkBool("ld bc,a write build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ld bc,a write len", @intCast(u32, blk.len), 1);
    checkOp("ld bc,a write op", blk.insns[0].op, blockmod.BlockOp.ld_mem);
    checkU32("ld bc,a write a", @intCast(u32, blk.insns[0].a), 8);
    checkU32("ld bc,a write b", @intCast(u32, blk.insns[0].b), 0);
    checkBool("ld bc,a write ends", blk.ends_block, true);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("ld bc,a write interp cycles", used, blk.cycles);
    checkU32("ld bc,a write stored", @intCast(u32, mmumod.read8(&g_bus, 0xC200)), 0xA5);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x34);
    mmumod.write8(&g_bus, 0xC300, 0x05);
    g_cpu.pc = 0xC000;
    g_cpu.h = 0xC3;
    g_cpu.l = 0x00;
    checkBool("inc hl write build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("inc hl write len", @intCast(u32, blk.len), 1);
    checkOp("inc hl write op", blk.insns[0].op, blockmod.BlockOp.incdec);
    checkU32("inc hl write a", @intCast(u32, blk.insns[0].a), 6);
    checkU32("inc hl write b", @intCast(u32, blk.insns[0].b), 0);
    checkBool("inc hl write ends", blk.ends_block, true);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("inc hl write interp cycles", used, blk.cycles);
    checkU32("inc hl write stored", @intCast(u32, mmumod.read8(&g_bus, 0xC300)), 0x06);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x36);
    mmumod.write8(&g_bus, 0xC001, 0x7F);
    g_cpu.pc = 0xC000;
    g_cpu.h = 0xC4;
    g_cpu.l = 0x00;
    checkBool("ld hl,n write build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ld hl,n write len", @intCast(u32, blk.len), 1);
    checkOp("ld hl,n write op", blk.insns[0].op, blockmod.BlockOp.ld_rn);
    checkU32("ld hl,n write a", @intCast(u32, blk.insns[0].a), 6);
    checkU16("ld hl,n write imm", blk.insns[0].imm, 0x007F);
    checkBool("ld hl,n write ends", blk.ends_block, true);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("ld hl,n write interp cycles", used, blk.cycles);
    checkU32("ld hl,n write stored", @intCast(u32, mmumod.read8(&g_bus, 0xC400)), 0x7F);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x7E);
    g_cpu.pc = 0xC000;
    g_cpu.h = 0xC5;
    g_cpu.l = 0x00;
    checkBool("ld a,hl read build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ld a,hl read len", @intCast(u32, blk.len), 64);
    checkOp("ld a,hl read op", blk.insns[0].op, blockmod.BlockOp.ld_mem);
    checkU32("ld a,hl read a", @intCast(u32, blk.insns[0].a), 7);
    checkU32("ld a,hl read b", @intCast(u32, blk.insns[0].b), 6);
    checkBool("ld a,hl read continues", blk.ends_block, false);
}

pub fn main() void {
    testStraightNops();
    testJump();
    testConditionalJr();
    testConditionalJp();
    testCall();
    testRet();
    testHalt();
    testStop();
    testCbBoundary();
    testInterruptBoundaries();
    testWriteBoundaries();
    testIndirectWriteBoundaries();

    std.io.write("dynarec ");
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
