// dynarec_test.zig — block IR builder checks against the interpreter oracle.
//
// Run as a normal executable under both -ffast and -fsafe. Every check is
// counted; the process exits 0 only when all checks pass.

const std = @import("std");
const cartmod = @import("../cart.zig");
const mmumod = @import("../mmu.zig");
const ppumod = @import("../ppu.zig");
const cpumod = @import("../cpu.zig");
const blockmod = @import("../dynarec/block.zig");
const ctxmod = @import("../dynarec/ctx.zig");
const x86mod = @import("../dynarec/x86.zig");
const helpersmod = @import("../dynarec/helpers.zig");
const cachemod = @import("../dynarec/cache.zig");
const dynarecmod = @import("../dynarec/dynarec.zig");
const emumod = @import("../emu.zig");

const DynCtx = ctxmod.DynCtx;
const Block = blockmod.Block;
const BlockInsn = blockmod.BlockInsn;
const BlockOp = blockmod.BlockOp;
const Page = mmumod.Page;

const MAP_BYTES: usize = 65536;
const MAP_FAILED: usize = 0xFFFFFFFF;
const DYN_ROM_BYTES: usize = 131072;
const DYN_SAVE_BYTES: usize = 8192;
const DYN_FB_PIXELS: usize = 160 * 144;
const DYN_SERIAL_BYTES: usize = 4096;

extern "c" fn mmap(addr: *void, len: usize, prot: i32, flags: i32, fd: i32, off: i32) *void;
extern "c" fn munmap(addr: *void, len: usize) i32;

var g_cart: cartmod.Cart = undefined;
var g_bus: mmumod.Bus = undefined;
var g_cpu: cpumod.Cpu = undefined;
var g_ppu: ppumod.Ppu = undefined;
var g_pass: u32 = 0;
var g_fail: u32 = 0;
var g_code: [*]u8 = undefined;
var g_code_ready: bool = false;
var g_emit_cache: cachemod.Dynarec = undefined;
var g_emit_cache_ready: bool = false;
var g_dyn: cachemod.Dynarec = undefined;
var g_rom: [0x8000]u8 = undefined;
var g_emu: emumod.Emu = undefined;
var g_audio_buf: [4096]i16 = undefined;

const FrameSnap = struct {
    fb: [DYN_FB_PIXELS]u32,
    serial: [DYN_SERIAL_BYTES]u8,
    serial_len: usize,
    ram: [DYN_SAVE_BYTES]u8,
    audio: usize,
    cycles: u32,
};

var g_snap_off: FrameSnap = undefined;
var g_snap_on: FrameSnap = undefined;

fn printU(v: usize) void {
    const x: u32 = @intCast(u32, v & 0xffffffff);
    std.io.printInt(@intCast(i32, x & 0x7fffffff));
}

fn reset() void {
    cartmod.cartInit(&g_cart);
    mmumod.busInit(&g_bus, &g_cart);
    cpumod.cpuInit(&g_cpu);
    ppumod.ppuReset(&g_ppu);
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

const Snap = struct {
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
    cycles: u32,
};

fn snapTake(cpu: *cpumod.Cpu, ret: u32) Snap {
    return Snap{
        .a = cpu.a,
        .f = cpu.f,
        .b = cpu.b,
        .c = cpu.c,
        .d = cpu.d,
        .e = cpu.e,
        .h = cpu.h,
        .l = cpu.l,
        .sp = cpu.sp,
        .pc = cpu.pc,
        .cycles = ret,
    };
}

fn snapEq(x: Snap, y: Snap) bool {
    return x.a == y.a and x.f == y.f and x.b == y.b and x.c == y.c and
        x.d == y.d and x.e == y.e and x.h == y.h and x.l == y.l and
        x.sp == y.sp and x.pc == y.pc and x.cycles == y.cycles;
}

fn checkSnap(label: []const u8, tag: u32, got: Snap, want: Snap) void {
    if (snapEq(got, want)) {
        g_pass += 1;
        return;
    }
    g_fail += 1;
    std.io.write("FAIL ");
    std.io.write(label);
    std.io.write(" tag=");
    printU(@intCast(usize, tag));
    std.io.write(" got a/f/pc/cyc=");
    printU(@intCast(usize, got.a));
    std.io.write("/");
    printU(@intCast(usize, got.f));
    std.io.write("/");
    printU(@intCast(usize, got.pc));
    std.io.write("/");
    printU(@intCast(usize, got.cycles));
    std.io.write(" want=");
    printU(@intCast(usize, want.a));
    std.io.write("/");
    printU(@intCast(usize, want.f));
    std.io.write("/");
    printU(@intCast(usize, want.pc));
    std.io.write("/");
    printU(@intCast(usize, want.cycles));
    std.io.write(" got b/c/d/e/h/l/sp=");
    printU(@intCast(usize, got.b));
    std.io.write("/");
    printU(@intCast(usize, got.c));
    std.io.write("/");
    printU(@intCast(usize, got.d));
    std.io.write("/");
    printU(@intCast(usize, got.e));
    std.io.write("/");
    printU(@intCast(usize, got.h));
    std.io.write("/");
    printU(@intCast(usize, got.l));
    std.io.write("/");
    printU(@intCast(usize, got.sp));
    std.io.write("\n");
}

fn ensureCode() bool {
    if (g_code_ready) return true;
    if (@isWindows()) {
        if (!cachemod.dynarecOpen(&g_emit_cache, &g_bus)) return false;
        g_code = g_emit_cache.mem;
        g_emit_cache_ready = true;
        g_code_ready = true;
        return true;
    }
    const raw = mmap(@intToPtr(*void, 0), MAP_BYTES, 7, 0x22, -1, 0);
    if (@ptrToInt(raw) == MAP_FAILED) return false;
    g_code = @ptrCast([*]u8, raw);
    g_code_ready = true;
    return true;
}

fn releaseCode() void {
    if (!g_code_ready) return;
    if (@isWindows()) {
        if (g_emit_cache_ready) cachemod.dynarecClose(&g_emit_cache);
        g_emit_cache_ready = false;
    } else {
        _ = munmap(@ptrCast(*void, g_code), MAP_BYTES);
    }
    g_code_ready = false;
}

fn runEmitted(blk: *const Block) u32 {
    if (!ensureCode()) return 0xFFFFFFFF;
    const cap: usize = if (@isWindows()) cachemod.CODE_CACHE_BYTES else MAP_BYTES;
    var e = x86mod.Emit{ .code = g_code, .len = 0, .cap = cap };
    if (!x86mod.emitBlock(&e, blk)) return 0xFFFFFFFE;
    if (@isWindows()) cachemod.flushRange(&g_emit_cache, 0, e.len);
    var ctx = DynCtx{ .cpu = &g_cpu, .bus = &g_bus, .ppu = &g_ppu, .cycles = 0, .instr_cycles = 0, .ppu_pending = 0, .ppu_advanced_dots = 0 };
    const f = @ptrCast(fn (*DynCtx) u32, g_code);
    return f(&ctx);
}

fn makeBlock(op: BlockOp, a: u8, b: u8, imm: u16, cycles: u32) Block {
    var blk: Block = undefined;
    blk.insns[0] = BlockInsn{ .op = op, .a = a, .b = b, .imm = imm };
    blk.len = 1;
    blk.start_pc = 0xC000;
    blk.cycles = cycles;
    blk.ends_block = false;
    return blk;
}

fn setReg(cpu: *cpumod.Cpu, idx: u8, v: u8) void {
    switch (idx) {
        0 => cpu.b = v,
        1 => cpu.c = v,
        2 => cpu.d = v,
        3 => cpu.e = v,
        4 => cpu.h = v,
        5 => cpu.l = v,
        7 => cpu.a = v,
        else => {},
    }
}

fn setPair(cpu: *cpumod.Cpu, idx: u8, v: u16) void {
    const hi: u8 = @intCast(u8, v >> 8);
    const lo: u8 = @intCast(u8, v & 0xFF);
    switch (idx) {
        0 => {
            cpu.b = hi;
            cpu.c = lo;
        },
        1 => {
            cpu.d = hi;
            cpu.e = lo;
        },
        2 => {
            cpu.h = hi;
            cpu.l = lo;
        },
        3 => cpu.sp = v,
        else => {},
    }
}

fn beginAt(pc: u16) void {
    reset();
    g_cpu.pc = pc;
}

fn checkMem8(label: []const u8, tag: u32, addr: u16, want: u8) void {
    checkU32(label, tag * 256 + @intCast(u32, mmumod.read8(&g_bus, addr)), tag * 256 + @intCast(u32, want));
}

fn opLdRr(a: u8, b: u8) u8 {
    return @intCast(u8, 0x40 + ((@intCast(u16, a) & 7) << 3) + (@intCast(u16, b) & 7));
}

fn opLdRn(a: u8) u8 {
    return @intCast(u8, 0x06 + ((@intCast(u16, a) & 7) << 3));
}

fn opLdPairImm(a: u8) u8 {
    return @intCast(u8, 0x01 + ((@intCast(u16, a) & 3) << 4));
}

fn opIncByte(a: u8) u8 {
    return @intCast(u8, 0x04 + ((@intCast(u16, a) & 7) << 3));
}

fn opDecByte(a: u8) u8 {
    return @intCast(u8, 0x05 + ((@intCast(u16, a) & 7) << 3));
}

fn opIncPair(a: u8) u8 {
    return @intCast(u8, 0x03 + ((@intCast(u16, a) & 3) << 4));
}

fn opDecPair(a: u8) u8 {
    return @intCast(u8, 0x0B + ((@intCast(u16, a) & 3) << 4));
}

fn opAddHl(a: u8) u8 {
    return @intCast(u8, 0x09 + ((@intCast(u16, a) & 3) << 4));
}

fn opAluR(group: u8, src: u8) u8 {
    return @intCast(u8, 0x80 + ((@intCast(u16, group) & 7) << 3) + (@intCast(u16, src) & 7));
}

fn opAluN(group: u8) u8 {
    return @intCast(u8, 0xC6 + ((@intCast(u16, group) & 7) << 3));
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
    mmumod.write8(&g_bus, 0xC000, 0xE0);
    mmumod.write8(&g_bus, 0xC001, 0x46);
    g_cpu.pc = 0xC000;
    var blk: blockmod.Block = undefined;
    checkBool("io write build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkOp("io write op", blk.insns[0].op, blockmod.BlockOp.ld_mem);
    checkU16("io write addr", blk.insns[0].imm, 0x0046);
    checkU32("io write cycles", blk.cycles, 12);
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

fn testCbWriteBoundaries() void {
    reset();
    mmumod.write8(&g_bus, 0xC000, 0xCB);
    mmumod.write8(&g_bus, 0xC001, 0x06);
    mmumod.write8(&g_bus, 0xC100, 0x80);
    g_cpu.pc = 0xC000;
    g_cpu.h = 0xC1;
    g_cpu.l = 0x00;
    var blk: blockmod.Block = undefined;
    checkBool("cb rlc hl build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("cb rlc hl len", @intCast(u32, blk.len), 1);
    checkOp("cb rlc hl op", blk.insns[0].op, blockmod.BlockOp.cb);
    checkU32("cb rlc hl op2", @intCast(u32, blk.insns[0].a), 0x06);
    checkU32("cb rlc hl cycles", blk.cycles, 16);
    checkBool("cb rlc hl ends", blk.ends_block, true);
    var used: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("cb rlc hl interp cycles", used, blk.cycles);
    checkU32("cb rlc hl stored", @intCast(u32, mmumod.read8(&g_bus, 0xC100)), 0x01);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xCB);
    mmumod.write8(&g_bus, 0xC001, 0x86);
    mmumod.write8(&g_bus, 0xC200, 0xFF);
    g_cpu.pc = 0xC000;
    g_cpu.h = 0xC2;
    g_cpu.l = 0x00;
    checkBool("cb res hl build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("cb res hl len", @intCast(u32, blk.len), 1);
    checkOp("cb res hl op", blk.insns[0].op, blockmod.BlockOp.cb);
    checkU32("cb res hl op2", @intCast(u32, blk.insns[0].a), 0x86);
    checkU32("cb res hl cycles", blk.cycles, 16);
    checkBool("cb res hl ends", blk.ends_block, true);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("cb res hl interp cycles", used, blk.cycles);
    checkU32("cb res hl stored", @intCast(u32, mmumod.read8(&g_bus, 0xC200)), 0xFE);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xCB);
    mmumod.write8(&g_bus, 0xC001, 0xC6);
    mmumod.write8(&g_bus, 0xC300, 0x00);
    g_cpu.pc = 0xC000;
    g_cpu.h = 0xC3;
    g_cpu.l = 0x00;
    checkBool("cb set hl build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("cb set hl len", @intCast(u32, blk.len), 1);
    checkOp("cb set hl op", blk.insns[0].op, blockmod.BlockOp.cb);
    checkU32("cb set hl op2", @intCast(u32, blk.insns[0].a), 0xC6);
    checkU32("cb set hl cycles", blk.cycles, 16);
    checkBool("cb set hl ends", blk.ends_block, true);
    used = cpumod.cpuStep(&g_cpu, &g_bus);
    checkU32("cb set hl interp cycles", used, blk.cycles);
    checkU32("cb set hl stored", @intCast(u32, mmumod.read8(&g_bus, 0xC300)), 0x01);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xCB);
    mmumod.write8(&g_bus, 0xC001, 0x46);
    g_cpu.pc = 0xC000;
    g_cpu.h = 0xC4;
    g_cpu.l = 0x00;
    checkBool("cb bit hl build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("cb bit hl len", @intCast(u32, blk.len), 64);
    checkOp("cb bit hl op", blk.insns[0].op, blockmod.BlockOp.cb);
    checkU32("cb bit hl op2", @intCast(u32, blk.insns[0].a), 0x46);
    checkU32("cb bit hl cycles", blk.cycles, 264);
    checkBool("cb bit hl continues", blk.ends_block, false);
}

fn testPpuReadBoundaries() void {
    var blk: blockmod.Block = undefined;

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x40);
    g_cpu.pc = 0xC000;
    checkBool("ld b,b boundary start", blockmod.blockBuild(&g_cpu, &g_bus, &blk), false);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x00);
    mmumod.write8(&g_bus, 0xC001, 0x40);
    g_cpu.pc = 0xC000;
    checkBool("ld b,b boundary build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ld b,b boundary len", @intCast(u32, blk.len), 1);
    checkBool("ld b,b boundary not terminal", blk.ends_block, false);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x1A);
    g_cpu.pc = 0xC000;
    checkBool("ld a,de boundary start", blockmod.blockBuild(&g_cpu, &g_bus, &blk), false);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x00);
    mmumod.write8(&g_bus, 0xC001, 0x1A);
    g_cpu.pc = 0xC000;
    checkBool("ld a,de boundary build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ld a,de boundary len", @intCast(u32, blk.len), 1);
    checkBool("ld a,de boundary not terminal", blk.ends_block, false);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xF0);
    mmumod.write8(&g_bus, 0xC001, 0x44);
    g_cpu.pc = 0xC000;
    checkBool("ldh ppu boundary start", blockmod.blockBuild(&g_cpu, &g_bus, &blk), false);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x00);
    mmumod.write8(&g_bus, 0xC001, 0xF0);
    mmumod.write8(&g_bus, 0xC002, 0x44);
    g_cpu.pc = 0xC000;
    checkBool("ldh ppu boundary build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ldh ppu boundary len", @intCast(u32, blk.len), 1);
    checkBool("ldh ppu boundary not terminal", blk.ends_block, false);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xFA);
    mmumod.write8(&g_bus, 0xC001, 0x41);
    mmumod.write8(&g_bus, 0xC002, 0xFF);
    g_cpu.pc = 0xC000;
    checkBool("ld a,a16 ppu boundary start", blockmod.blockBuild(&g_cpu, &g_bus, &blk), false);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x00);
    mmumod.write8(&g_bus, 0xC001, 0xFA);
    mmumod.write8(&g_bus, 0xC002, 0x41);
    mmumod.write8(&g_bus, 0xC003, 0xFF);
    g_cpu.pc = 0xC000;
    checkBool("ld a,a16 ppu boundary build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ld a,a16 ppu boundary len", @intCast(u32, blk.len), 1);
    checkBool("ld a,a16 ppu boundary not terminal", blk.ends_block, false);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xEA);
    mmumod.write8(&g_bus, 0xC001, 0x40);
    mmumod.write8(&g_bus, 0xC002, 0xFF);
    g_cpu.pc = 0xC000;
    checkBool("ld a16,a ppu boundary start", blockmod.blockBuild(&g_cpu, &g_bus, &blk), false);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x00);
    mmumod.write8(&g_bus, 0xC001, 0xEA);
    mmumod.write8(&g_bus, 0xC002, 0x40);
    mmumod.write8(&g_bus, 0xC003, 0xFF);
    g_cpu.pc = 0xC000;
    checkBool("ld a16,a ppu boundary build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ld a16,a ppu boundary len", @intCast(u32, blk.len), 1);
    checkBool("ld a16,a ppu boundary not terminal", blk.ends_block, false);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xF0);
    mmumod.write8(&g_bus, 0xC001, 0x00);
    mmumod.write8(&g_bus, 0xC002, 0x76);
    g_cpu.pc = 0xC000;
    checkBool("ldh non-ppu build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ldh non-ppu len", @intCast(u32, blk.len), 2);
    checkOp("ldh non-ppu op", blk.insns[0].op, blockmod.BlockOp.ld_mem);
    checkBool("ldh non-ppu halts", blk.ends_block, true);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0x7E);
    mmumod.write8(&g_bus, 0xC001, 0x76);
    g_cpu.pc = 0xC000;
    checkBool("ld a,hl build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    checkU32("ld a,hl len", @intCast(u32, blk.len), 2);
    checkOp("ld a,hl op", blk.insns[0].op, blockmod.BlockOp.ld_mem);
    checkBool("ld a,hl halts", blk.ends_block, true);
}

fn setupAluR(group: u8, src: u8, carry: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, opAluR(group, src));
    const aVal: u8 = 0xA5;
    var srcVal: u8 = @intCast(u8, 0x3C + @intCast(u16, src) + @intCast(u16, carry));
    if (src == 7) srcVal = aVal;
    g_cpu.a = aVal;
    g_cpu.f = if (carry != 0) 0x10 else 0;
    if (src == 6) {
        g_cpu.h = 0xC1;
        g_cpu.l = 0x00;
        mmumod.write8(&g_bus, 0xC100, srcVal);
    } else {
        setReg(&g_cpu, src, srcVal);
    }
}

fn testAluRegisterMatrix() void {
    var group: u8 = 0;
    while (group < 8) : (group += 1) {
        var src: u8 = 0;
        while (src < 8) : (src += 1) {
            const carry_max: u8 = if (group == 1 or group == 3) 2 else 1;
            var carry: u8 = 0;
            while (carry < carry_max) : (carry += 1) {
                setupAluR(group, src, carry);
                const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
                const want: Snap = snapTake(&g_cpu, wantCyc);
                setupAluR(group, src, carry);
                var blk: Block = makeBlock(.alu_r, group, src, 0, wantCyc);
                const gotCyc: u32 = runEmitted(&blk);
                const got: Snap = snapTake(&g_cpu, gotCyc);
                checkSnap("alu r", @intCast(u32, group) * 1000 + @intCast(u32, src) * 10 + carry, got, want);
            }
        }
    }
}

fn setupAluN(group: u8, carry: u8, imm: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, opAluN(group));
    mmumod.write8(&g_bus, 0xC001, imm);
    g_cpu.a = 0x5A;
    g_cpu.f = if (carry != 0) 0x10 else 0;
}

fn testAluImmediate() void {
    const imms: [3]u8 = [3]u8{ 0x01, 0xFE, 0x00 };
    var group: u8 = 0;
    while (group < 8) : (group += 1) {
        const carry_max: u8 = if (group == 1 or group == 3) 2 else 1;
        var carry: u8 = 0;
        while (carry < carry_max) : (carry += 1) {
            var i: usize = 0;
            while (i < 3) : (i += 1) {
                setupAluN(group, carry, imms[i]);
                const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
                const want: Snap = snapTake(&g_cpu, wantCyc);
                setupAluN(group, carry, imms[i]);
                var blk: Block = makeBlock(.alu_n, group, 0, @intCast(u16, imms[i]), wantCyc);
                const gotCyc: u32 = runEmitted(&blk);
                const got: Snap = snapTake(&g_cpu, gotCyc);
                checkSnap("alu n", @intCast(u32, group) * 1000 + @intCast(u32, carry) * 100 + @intCast(u32, i), got, want);
            }
        }
    }
}

fn setupLdRr(a: u8, b: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, opLdRr(a, b));
    g_cpu.a = 0x11;
    g_cpu.f = 0xB0;
    g_cpu.b = 0x22;
    g_cpu.c = 0x33;
    g_cpu.d = 0x44;
    g_cpu.e = 0x55;
    g_cpu.h = 0x66;
    g_cpu.l = 0x77;
    g_cpu.sp = 0xD000;
    if (a == 6 or b == 6) {
        g_cpu.h = 0xC1;
        g_cpu.l = 0x00;
        mmumod.write8(&g_bus, 0xC100, 0x5A);
    }
}

fn testLdRr() void {
    var a: u8 = 0;
    while (a < 8) : (a += 1) {
        var b: u8 = 0;
        while (b < 8) : (b += 1) {
            if (a == 6 and b == 6) continue;
            setupLdRr(a, b);
            const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
            const want: Snap = snapTake(&g_cpu, wantCyc);
            const wantMem: u8 = mmumod.read8(&g_bus, 0xC100);
            setupLdRr(a, b);
            var blk: Block = makeBlock(.ld_mem, a, b, 0, wantCyc);
            const gotCyc: u32 = runEmitted(&blk);
            const got: Snap = snapTake(&g_cpu, gotCyc);
            checkSnap("ld r,r'", @intCast(u32, a) * 10 + @intCast(u32, b), got, want);
            if (a == 6) checkMem8("ld (hl),r'", @intCast(u32, a) * 10 + @intCast(u32, b), 0xC100, wantMem);
        }
    }
}

fn setupLdRn(a: u8, imm: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, opLdRn(a));
    mmumod.write8(&g_bus, 0xC001, imm);
    g_cpu.a = 0x11;
    g_cpu.f = 0xB0;
    g_cpu.b = 0x22;
    g_cpu.c = 0x33;
    g_cpu.d = 0x44;
    g_cpu.e = 0x55;
    g_cpu.h = 0x66;
    g_cpu.l = 0x77;
    if (a == 6) {
        g_cpu.h = 0xC2;
        g_cpu.l = 0x00;
    }
}

fn testLdRn() void {
    const imms: [2]u8 = [2]u8{ 0x9C, 0x00 };
    var a: u8 = 0;
    while (a < 8) : (a += 1) {
        var i: usize = 0;
        while (i < 2) : (i += 1) {
            setupLdRn(a, imms[i]);
            const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
            const want: Snap = snapTake(&g_cpu, wantCyc);
            const wantMem: u8 = mmumod.read8(&g_bus, 0xC200);
            setupLdRn(a, imms[i]);
            var blk: Block = makeBlock(.ld_rn, a, 0, @intCast(u16, imms[i]), wantCyc);
            const gotCyc: u32 = runEmitted(&blk);
            const got: Snap = snapTake(&g_cpu, gotCyc);
            checkSnap("ld r,n", @intCast(u32, a) * 10 + @intCast(u32, i), got, want);
            if (a == 6) checkMem8("ld (hl),n", @intCast(u32, a) * 10 + @intCast(u32, i), 0xC200, wantMem);
        }
    }
}

fn setupLdPair(a: u8, imm: u16) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, opLdPairImm(a));
    mmumod.write8(&g_bus, 0xC001, @intCast(u8, imm & 0xFF));
    mmumod.write8(&g_bus, 0xC002, @intCast(u8, imm >> 8));
    g_cpu.b = 0x11;
    g_cpu.c = 0x22;
    g_cpu.d = 0x33;
    g_cpu.e = 0x44;
    g_cpu.h = 0x55;
    g_cpu.l = 0x66;
    g_cpu.sp = 0x7788;
}

fn testLdPair() void {
    const imms: [3]u16 = [3]u16{ 0x0000, 0xBEEF, 0xFFFF };
    var a: u8 = 0;
    while (a < 4) : (a += 1) {
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            setupLdPair(a, imms[i]);
            const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
            const want: Snap = snapTake(&g_cpu, wantCyc);
            setupLdPair(a, imms[i]);
            var blk: Block = makeBlock(.ld_rr, a, 0, imms[i], wantCyc);
            const gotCyc: u32 = runEmitted(&blk);
            const got: Snap = snapTake(&g_cpu, gotCyc);
            checkSnap("ld rr,n", @intCast(u32, a) * 10 + @intCast(u32, i), got, want);
        }
    }

    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, 0xF9);
    g_cpu.h = 0x12;
    g_cpu.l = 0x34;
    g_cpu.sp = 0x0000;
    const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    const want: Snap = snapTake(&g_cpu, wantCyc);
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, 0xF9);
    g_cpu.h = 0x12;
    g_cpu.l = 0x34;
    g_cpu.sp = 0x0000;
    var blk: Block = makeBlock(.ld_rr, 3, 1, 0, wantCyc);
    const gotCyc: u32 = runEmitted(&blk);
    const got: Snap = snapTake(&g_cpu, gotCyc);
    checkSnap("ld sp,hl", 999, got, want);
}

fn setupIncDecByte(a: u8, dec: u8, carry: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, if (dec != 0) opDecByte(a) else opIncByte(a));
    const val: u8 = if (dec != 0) (if (carry != 0) 0x10 else 0x00) else (if (carry != 0) 0x0F else 0xFF);
    g_cpu.f = if (carry != 0) 0x10 else 0;
    g_cpu.a = 0x11;
    g_cpu.b = 0x22;
    g_cpu.c = 0x33;
    g_cpu.d = 0x44;
    g_cpu.e = 0x55;
    g_cpu.h = 0x66;
    g_cpu.l = 0x77;
    if (a == 6) {
        g_cpu.h = 0xC3;
        g_cpu.l = 0x00;
        mmumod.write8(&g_bus, 0xC300, val);
    } else {
        setReg(&g_cpu, a, val);
    }
}

fn testIncDecByte() void {
    var a: u8 = 0;
    while (a < 8) : (a += 1) {
        var dec: u8 = 0;
        while (dec < 2) : (dec += 1) {
            var carry: u8 = 0;
            while (carry < 2) : (carry += 1) {
                setupIncDecByte(a, dec, carry);
                const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
                const want: Snap = snapTake(&g_cpu, wantCyc);
                const wantMem: u8 = mmumod.read8(&g_bus, 0xC300);
                setupIncDecByte(a, dec, carry);
                var blk: Block = makeBlock(.incdec, a, dec, 0, wantCyc);
                const gotCyc: u32 = runEmitted(&blk);
                const got: Snap = snapTake(&g_cpu, gotCyc);
                checkSnap("inc/dec byte", @intCast(u32, a) * 100 + @intCast(u32, dec) * 10 + carry, got, want);
                if (a == 6) checkMem8("inc/dec (hl)", @intCast(u32, a) * 100 + @intCast(u32, dec) * 10 + carry, 0xC300, wantMem);
            }
        }
    }
}

fn setupIncDecPair(a: u8, dec: u8, case: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, if (dec != 0) opDecPair(a) else opIncPair(a));
    const val: u16 = if (case == 0) 0x00FF else if (case == 1) 0xFFFF else 0x0100;
    setPair(&g_cpu, a, val);
}

fn testIncDecPair() void {
    var a: u8 = 0;
    while (a < 4) : (a += 1) {
        var dec: u8 = 0;
        while (dec < 2) : (dec += 1) {
            var ci: u8 = 0;
            while (ci < 3) : (ci += 1) {
                setupIncDecPair(a, dec, ci);
                const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
                const want: Snap = snapTake(&g_cpu, wantCyc);
                setupIncDecPair(a, dec, ci);
                var blk: Block = makeBlock(.incdec, a, @intCast(u8, 0x80 + dec), 0, wantCyc);
                const gotCyc: u32 = runEmitted(&blk);
                const got: Snap = snapTake(&g_cpu, gotCyc);
                checkSnap("inc/dec pair", @intCast(u32, a) * 100 + @intCast(u32, dec) * 10 + ci, got, want);
            }
        }
    }
}

fn setupAddHl(pair: u8, case: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, opAddHl(pair));
    const hlVal: u16 = if (case == 0) 0x0FFF else if (case == 1) 0xFFFF else 0x1234;
    const other: u16 = if (case == 0) 0x0001 else if (case == 1) 0x0001 else 0x0FFF;
    g_cpu.f = 0x80;
    setPair(&g_cpu, 2, hlVal);
    if (pair != 2) setPair(&g_cpu, pair, other);
}

fn testAddHl() void {
    var pair: u8 = 0;
    while (pair < 4) : (pair += 1) {
        var ci: u8 = 0;
        while (ci < 3) : (ci += 1) {
            setupAddHl(pair, ci);
            const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
            const want: Snap = snapTake(&g_cpu, wantCyc);
            setupAddHl(pair, ci);
            var blk: Block = makeBlock(.alu_r, 8, pair, 0, wantCyc);
            const gotCyc: u32 = runEmitted(&blk);
            const got: Snap = snapTake(&g_cpu, gotCyc);
            checkSnap("add hl,rr", @intCast(u32, pair) * 10 + ci, got, want);
        }
    }
}

fn indirectAddr(a: u8) u16 {
    if (a == 8) return 0xC200;
    if (a == 9) return 0xC300;
    return 0xC100;
}

fn setupIndirect(a: u8, load: u8) void {
    beginAt(0xC000);
    const base: u16 = if (load != 0) 0x0A else 0x02;
    const opcode: u8 = @intCast(u8, base + ((@intCast(u16, a) - 8) << 4));
    mmumod.write8(&g_bus, 0xC000, opcode);
    g_cpu.a = 0xA5;
    g_cpu.b = 0xC2;
    g_cpu.c = 0x00;
    g_cpu.d = 0xC3;
    g_cpu.e = 0x00;
    g_cpu.h = 0xC1;
    g_cpu.l = 0x00;
    mmumod.write8(&g_bus, indirectAddr(a), 0x5A);
}

fn testIndirect() void {
    var a: u8 = 8;
    while (a < 12) : (a += 1) {
        var load: u8 = 0;
        while (load < 2) : (load += 1) {
            setupIndirect(a, load);
            const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
            const want: Snap = snapTake(&g_cpu, wantCyc);
            const wantMem: u8 = mmumod.read8(&g_bus, indirectAddr(a));
            setupIndirect(a, load);
            var blk: Block = makeBlock(.ld_mem, a, load, 0, wantCyc);
            const gotCyc: u32 = runEmitted(&blk);
            const got: Snap = snapTake(&g_cpu, gotCyc);
            checkSnap("ld (rr),a", @intCast(u32, a) * 10 + load, got, want);
            checkMem8("ld (rr),a mem", @intCast(u32, a) * 10 + load, indirectAddr(a), wantMem);
        }
    }
}

fn setupLdh(addr8: u8, load: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, if (load != 0) 0xF0 else 0xE0);
    mmumod.write8(&g_bus, 0xC001, addr8);
    g_cpu.a = 0xA5;
    const addr: u16 = @intCast(u16, 0xFF00 | @intCast(u16, addr8));
    if (load != 0) mmumod.write8(&g_bus, addr, 0x5A);
}

fn testLdh() void {
    const addrs: [4]u8 = [4]u8{ 0x80, 0xFE, 0x40, 0x00 };
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var load: u8 = 0;
        while (load < 2) : (load += 1) {
            setupLdh(addrs[i], load);
            const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
            const want: Snap = snapTake(&g_cpu, wantCyc);
            const addr: u16 = @intCast(u16, 0xFF00 | @intCast(u16, addrs[i]));
            const wantMem: u8 = mmumod.read8(&g_bus, addr);
            setupLdh(addrs[i], load);
            var blk: Block = makeBlock(.ld_mem, 12, load, @intCast(u16, addrs[i]), wantCyc);
            const gotCyc: u32 = runEmitted(&blk);
            const got: Snap = snapTake(&g_cpu, gotCyc);
            checkSnap("ldh", @intCast(u32, i) * 10 + load, got, want);
            checkMem8("ldh mem", @intCast(u32, i) * 10 + load, addr, wantMem);
        }
    }
}

fn setupA16(addr: u16, load: u8, cartMode: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, if (load != 0) 0xFA else 0xEA);
    mmumod.write8(&g_bus, 0xC001, @intCast(u8, addr & 0xFF));
    mmumod.write8(&g_bus, 0xC002, @intCast(u8, addr >> 8));
    g_cpu.a = 0xA5;
    if (cartMode != 0) {
        g_bus.pages[0xA0] = Page{ .kind = .cart_ram, .base = @ptrCast([*]u8, &g_cart.ram[0]) };
        g_cart.ram[0] = 0x11;
        return;
    }
    if (load != 0) {
        if (addr < 0x8000) return;
        mmumod.write8(&g_bus, addr, 0x5A);
    }
}

fn testLdA16() void {
    const addrs: [10]u16 = [10]u16{ 0xC500, 0xE100, 0x0000, 0x2000, 0xA000, 0x8000, 0xFE00, 0xFF80, 0xFFFF, 0xFF10 };
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var load: u8 = 0;
        while (load < 2) : (load += 1) {
            setupA16(addrs[i], load, 0);
            const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
            const want: Snap = snapTake(&g_cpu, wantCyc);
            const wantMem: u8 = mmumod.read8(&g_bus, addrs[i]);
            setupA16(addrs[i], load, 0);
            var blk: Block = makeBlock(.ld_mem, 13, load, addrs[i], wantCyc);
            const gotCyc: u32 = runEmitted(&blk);
            const got: Snap = snapTake(&g_cpu, gotCyc);
            checkSnap("ld (a16)", @intCast(u32, i) * 10 + load, got, want);
            checkMem8("ld (a16) mem", @intCast(u32, i) * 10 + load, addrs[i], wantMem);
        }
    }

    var load: u8 = 0;
    while (load < 2) : (load += 1) {
        setupA16(0xA000, load, 1);
        const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
        const want: Snap = snapTake(&g_cpu, wantCyc);
        const wantMem: u8 = mmumod.read8(&g_bus, 0xA000);
        setupA16(0xA000, load, 1);
        var blk: Block = makeBlock(.ld_mem, 13, load, 0xA000, wantCyc);
        const gotCyc: u32 = runEmitted(&blk);
        const got: Snap = snapTake(&g_cpu, gotCyc);
        checkSnap("ld cart ram", 500 + @intCast(u32, load), got, want);
        checkMem8("ld cart ram mem", 500 + @intCast(u32, load), 0xA000, wantMem);
    }
}

fn setupA16Sp(addr: u16) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, 0x08);
    mmumod.write8(&g_bus, 0xC001, @intCast(u8, addr & 0xFF));
    mmumod.write8(&g_bus, 0xC002, @intCast(u8, addr >> 8));
    g_cpu.sp = 0xBEEF;
}

fn testLdA16Sp() void {
    const addrs: [3]u16 = [3]u16{ 0xC600, 0xE100, 0xFF80 };
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        setupA16Sp(addrs[i]);
        const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
        const want: Snap = snapTake(&g_cpu, wantCyc);
        const wantLo: u8 = mmumod.read8(&g_bus, addrs[i]);
        const wantHi: u8 = mmumod.read8(&g_bus, addrs[i] +% 1);
        setupA16Sp(addrs[i]);
        var blk: Block = makeBlock(.ld_mem, 14, 0, addrs[i], wantCyc);
        const gotCyc: u32 = runEmitted(&blk);
        const got: Snap = snapTake(&g_cpu, gotCyc);
        checkSnap("ld (a16),sp", @intCast(u32, i), got, want);
        checkMem8("ld (a16),sp lo", @intCast(u32, i), addrs[i], wantLo);
        checkMem8("ld (a16),sp hi", @intCast(u32, i), addrs[i] +% 1, wantHi);
    }
}

fn setupLdC(cval: u8, load: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, if (load != 0) 0xF2 else 0xE2);
    g_cpu.a = 0xA5;
    g_cpu.c = cval;
    const addr: u16 = @intCast(u16, 0xFF00 | @intCast(u16, cval));
    if (load != 0) mmumod.write8(&g_bus, addr, 0x5A);
}

fn testLdC() void {
    const cvals: [4]u8 = [4]u8{ 0x80, 0xFE, 0x40, 0x00 };
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var load: u8 = 0;
        while (load < 2) : (load += 1) {
            setupLdC(cvals[i], load);
            const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
            const want: Snap = snapTake(&g_cpu, wantCyc);
            const addr: u16 = @intCast(u16, 0xFF00 | @intCast(u16, cvals[i]));
            const wantMem: u8 = mmumod.read8(&g_bus, addr);
            setupLdC(cvals[i], load);
            var blk: Block = makeBlock(.ld_mem, 15, load, 0, wantCyc);
            const gotCyc: u32 = runEmitted(&blk);
            const got: Snap = snapTake(&g_cpu, gotCyc);
            checkSnap("ld (c)", @intCast(u32, i) * 10 + load, got, want);
            checkMem8("ld (c) mem", @intCast(u32, i) * 10 + load, addr, wantMem);
        }
    }
}

fn testEmitterRejects() void {
    if (!ensureCode()) {
        checkBool("code mapping", false, true);
        return;
    }
    var e = x86mod.Emit{ .code = g_code, .len = 0, .cap = MAP_BYTES };
    var blk: Block = makeBlock(.jump, 4, 0, 0x1234, 16);
    checkBool("accept jump", x86mod.emitBlock(&e, &blk), true);
    blk = makeBlock(.call, 4, 0, 0x1234, 24);
    checkBool("accept call", x86mod.emitBlock(&e, &blk), true);
    blk = makeBlock(.ret, 4, 0, 0, 16);
    checkBool("accept ret", x86mod.emitBlock(&e, &blk), true);
    blk = makeBlock(.cb, 0x37, 0, 0, 8);
    checkBool("accept cb", x86mod.emitBlock(&e, &blk), true);
    blk = makeBlock(.unsupported, 0x76, 0, 0, 4);
    checkBool("reject unsupported", x86mod.emitBlock(&e, &blk), false);
    blk = makeBlock(.ld_mem, 6, 6, 0, 8);
    checkBool("reject invalid ld", x86mod.emitBlock(&e, &blk), false);
    blk = makeBlock(.nop, 0, 0, 0, 4);
    checkBool("accept nop", x86mod.emitBlock(&e, &blk), true);
}

fn testEmitMultiInsn() void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, 0x3E);
    mmumod.write8(&g_bus, 0xC001, 0x12);
    mmumod.write8(&g_bus, 0xC002, 0x06);
    mmumod.write8(&g_bus, 0xC003, 0x34);
    mmumod.write8(&g_bus, 0xC004, 0x80);
    mmumod.write8(&g_bus, 0xC005, 0x0C);
    mmumod.write8(&g_bus, 0xC006, 0x04);
    var wantCyc: u32 = 0;
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    const want: Snap = snapTake(&g_cpu, wantCyc);

    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, 0x3E);
    mmumod.write8(&g_bus, 0xC001, 0x12);
    mmumod.write8(&g_bus, 0xC002, 0x06);
    mmumod.write8(&g_bus, 0xC003, 0x34);
    mmumod.write8(&g_bus, 0xC004, 0x80);
    mmumod.write8(&g_bus, 0xC005, 0x0C);
    mmumod.write8(&g_bus, 0xC006, 0x04);
    var blk: Block = undefined;
    blk.insns[0] = BlockInsn{ .op = .ld_rn, .a = 7, .b = 0, .imm = 0x12 };
    blk.insns[1] = BlockInsn{ .op = .ld_rn, .a = 0, .b = 0, .imm = 0x34 };
    blk.insns[2] = BlockInsn{ .op = .alu_r, .a = 0, .b = 0, .imm = 0 };
    blk.insns[3] = BlockInsn{ .op = .incdec, .a = 1, .b = 0, .imm = 0 };
    blk.insns[4] = BlockInsn{ .op = .incdec, .a = 0, .b = 0, .imm = 0 };
    blk.len = 5;
    blk.start_pc = 0xC000;
    blk.cycles = wantCyc;
    blk.ends_block = false;
    const gotCyc: u32 = runEmitted(&blk);
    const got: Snap = snapTake(&g_cpu, gotCyc);
    checkSnap("multi insn", 1, got, want);
}

fn testEmitJumps() void {
    beginAt(0xC000);
    var blk: Block = makeBlock(.jump, 4, 0, 0x1234, 16);
    var cyc: u32 = runEmitted(&blk);
    checkU32("emit jp cycles", cyc, 16);
    checkU16("emit jp pc", g_cpu.pc, 0x1234);

    beginAt(0xC000);
    g_cpu.f = 0;
    blk = makeBlock(.jump, 0, 1, 0xC007, 8);
    cyc = runEmitted(&blk);
    checkU32("emit jr taken cycles", cyc, 12);
    checkU16("emit jr taken pc", g_cpu.pc, 0xC007);

    beginAt(0xC000);
    g_cpu.f = 0x80;
    blk = makeBlock(.jump, 0, 1, 0xC007, 8);
    cyc = runEmitted(&blk);
    checkU32("emit jr not-taken cycles", cyc, 8);
    checkU16("emit jr not-taken pc", g_cpu.pc, 0xC002);

    beginAt(0xC000);
    g_cpu.f = 0x80;
    blk = makeBlock(.jump, 1, 0, 0x1234, 12);
    cyc = runEmitted(&blk);
    checkU32("emit jp z taken cycles", cyc, 16);
    checkU16("emit jp z taken pc", g_cpu.pc, 0x1234);

    beginAt(0xC000);
    g_cpu.f = 0;
    blk = makeBlock(.jump, 1, 0, 0x1234, 12);
    cyc = runEmitted(&blk);
    checkU32("emit jp z not-taken cycles", cyc, 12);
    checkU16("emit jp z not-taken pc", g_cpu.pc, 0xC003);

    beginAt(0xC000);
    g_cpu.f = 0;
    blk = makeBlock(.jump, 2, 0, 0x1234, 12);
    cyc = runEmitted(&blk);
    checkU32("emit jp nc taken cycles", cyc, 16);
    checkU16("emit jp nc taken pc", g_cpu.pc, 0x1234);

    beginAt(0xC000);
    g_cpu.f = 0x10;
    blk = makeBlock(.jump, 3, 0, 0x1234, 12);
    cyc = runEmitted(&blk);
    checkU32("emit jp c taken cycles", cyc, 16);
    checkU16("emit jp c taken pc", g_cpu.pc, 0x1234);

    beginAt(0xC000);
    g_cpu.f = 0x10;
    blk = makeBlock(.jump, 2, 0, 0x1234, 12);
    cyc = runEmitted(&blk);
    checkU32("emit jp nc not-taken cycles", cyc, 12);
    checkU16("emit jp nc not-taken pc", g_cpu.pc, 0xC003);

    beginAt(0xC000);
    g_cpu.f = 0;
    blk = makeBlock(.jump, 3, 0, 0x1234, 12);
    cyc = runEmitted(&blk);
    checkU32("emit jp c not-taken cycles", cyc, 12);
    checkU16("emit jp c not-taken pc", g_cpu.pc, 0xC003);

    beginAt(0xC000);
    g_cpu.h = 0x12;
    g_cpu.l = 0x34;
    blk = makeBlock(.jump, 5, 2, 0, 4);
    cyc = runEmitted(&blk);
    checkU32("emit jp hl cycles", cyc, 4);
    checkU16("emit jp hl pc", g_cpu.pc, 0x1234);
}

fn testEmitCallRet() void {
    beginAt(0xC000);
    g_cpu.sp = 0xD000;
    var blk: Block = makeBlock(.call, 4, 0, 0x1234, 24);
    var cyc: u32 = runEmitted(&blk);
    checkU32("emit call cycles", cyc, 24);
    checkU16("emit call pc", g_cpu.pc, 0x1234);
    checkU16("emit call sp", g_cpu.sp, 0xCFFE);
    checkMem8("emit call ret lo", 1, 0xCFFE, 0x03);
    checkMem8("emit call ret hi", 1, 0xCFFF, 0xC0);

    beginAt(0xC000);
    g_cpu.sp = 0xD000;
    g_cpu.f = 0x80;
    blk = makeBlock(.call, 1, 0, 0x1234, 12);
    cyc = runEmitted(&blk);
    checkU32("emit call z taken cycles", cyc, 24);
    checkU16("emit call z taken pc", g_cpu.pc, 0x1234);
    checkU16("emit call z taken sp", g_cpu.sp, 0xCFFE);
    checkMem8("emit call z ret lo", 2, 0xCFFE, 0x03);

    beginAt(0xC000);
    g_cpu.sp = 0xD000;
    g_cpu.f = 0;
    blk = makeBlock(.call, 1, 0, 0x1234, 12);
    cyc = runEmitted(&blk);
    checkU32("emit call z not-taken cycles", cyc, 12);
    checkU16("emit call z not-taken pc", g_cpu.pc, 0xC003);
    checkU16("emit call z not-taken sp", g_cpu.sp, 0xD000);

    beginAt(0xC000);
    g_cpu.sp = 0xD000;
    mmumod.write8(&g_bus, 0xD000, 0x34);
    mmumod.write8(&g_bus, 0xD001, 0x12);
    blk = makeBlock(.ret, 4, 0, 0, 16);
    cyc = runEmitted(&blk);
    checkU32("emit ret cycles", cyc, 16);
    checkU16("emit ret pc", g_cpu.pc, 0x1234);
    checkU16("emit ret sp", g_cpu.sp, 0xD002);

    beginAt(0xC000);
    g_cpu.sp = 0xD000;
    g_cpu.ime = false;
    g_cpu.ei_delay = 2;
    mmumod.write8(&g_bus, 0xD000, 0x34);
    mmumod.write8(&g_bus, 0xD001, 0x12);
    blk = makeBlock(.ret, 4, 1, 0, 16);
    cyc = runEmitted(&blk);
    checkU32("emit reti cycles", cyc, 16);
    checkU16("emit reti pc", g_cpu.pc, 0x1234);
    checkBool("emit reti ime", g_cpu.ime, true);
    checkU32("emit reti ei_delay", @intCast(u32, g_cpu.ei_delay), 0);

    beginAt(0xC000);
    g_cpu.sp = 0xD000;
    g_cpu.f = 0;
    mmumod.write8(&g_bus, 0xD000, 0x34);
    mmumod.write8(&g_bus, 0xD001, 0x12);
    blk = makeBlock(.ret, 0, 0, 0, 8);
    cyc = runEmitted(&blk);
    checkU32("emit ret nz taken cycles", cyc, 20);
    checkU16("emit ret nz taken pc", g_cpu.pc, 0x1234);
    checkU16("emit ret nz taken sp", g_cpu.sp, 0xD002);

    beginAt(0xC000);
    g_cpu.sp = 0xD000;
    g_cpu.f = 0x80;
    blk = makeBlock(.ret, 0, 0, 0, 8);
    cyc = runEmitted(&blk);
    checkU32("emit ret nz not-taken cycles", cyc, 8);
    checkU16("emit ret nz not-taken pc", g_cpu.pc, 0xC001);
    checkU16("emit ret nz not-taken sp", g_cpu.sp, 0xD000);
}

fn testEmitPushPop() void {
    beginAt(0xC000);
    g_cpu.sp = 0xFFF0;
    g_cpu.b = 0x34;
    g_cpu.c = 0x12;
    var blk: Block = makeBlock(.ld_mem, 16, 0, 0, 16);
    var cyc: u32 = runEmitted(&blk);
    checkU32("emit push bc cycles", cyc, 16);
    checkU16("emit push bc sp", g_cpu.sp, 0xFFEE);
    checkMem8("emit push bc lo", 1, 0xFFEE, 0x12);
    checkMem8("emit push bc hi", 2, 0xFFEF, 0x34);

    beginAt(0xC000);
    g_cpu.sp = 0xFFF0;
    mmumod.write8(&g_bus, 0xFFF0, 0x78);
    mmumod.write8(&g_bus, 0xFFF1, 0x56);
    blk = makeBlock(.ld_mem, 17, 1, 0, 12);
    cyc = runEmitted(&blk);
    checkU32("emit pop de cycles", cyc, 12);
    checkU16("emit pop de sp", g_cpu.sp, 0xFFF2);
    checkU32("emit pop de d", @intCast(u32, g_cpu.d), 0x56);
    checkU32("emit pop de e", @intCast(u32, g_cpu.e), 0x78);

    beginAt(0xC000);
    g_cpu.sp = 0xFFF0;
    g_cpu.h = 0x12;
    g_cpu.l = 0x34;
    blk = makeBlock(.ld_mem, 16, 2, 0, 16);
    cyc = runEmitted(&blk);
    checkU32("emit push hl cycles", cyc, 16);
    checkU16("emit push hl sp", g_cpu.sp, 0xFFEE);
    checkMem8("emit push hl lo", 5, 0xFFEE, 0x34);
    checkMem8("emit push hl hi", 6, 0xFFEF, 0x12);

    beginAt(0xC000);
    g_cpu.sp = 0xFFF0;
    mmumod.write8(&g_bus, 0xFFF0, 0x78);
    mmumod.write8(&g_bus, 0xFFF1, 0x56);
    blk = makeBlock(.ld_mem, 17, 2, 0, 12);
    cyc = runEmitted(&blk);
    checkU32("emit pop hl cycles", cyc, 12);
    checkU16("emit pop hl sp", g_cpu.sp, 0xFFF2);
    checkU32("emit pop hl h", @intCast(u32, g_cpu.h), 0x56);
    checkU32("emit pop hl l", @intCast(u32, g_cpu.l), 0x78);

    beginAt(0xC000);
    g_cpu.sp = 0xFFF0;
    g_cpu.a = 0x12;
    g_cpu.f = 0xAB;
    blk = makeBlock(.ld_mem, 16, 3, 0, 16);
    cyc = runEmitted(&blk);
    checkU32("emit push af cycles", cyc, 16);
    checkU16("emit push af sp", g_cpu.sp, 0xFFEE);
    checkMem8("emit push af lo", 3, 0xFFEE, 0xA0);
    checkMem8("emit push af hi", 4, 0xFFEF, 0x12);

    beginAt(0xC000);
    g_cpu.sp = 0xFFF0;
    mmumod.write8(&g_bus, 0xFFF0, 0x34);
    mmumod.write8(&g_bus, 0xFFF1, 0xCF);
    blk = makeBlock(.ld_mem, 17, 3, 0, 12);
    cyc = runEmitted(&blk);
    checkU32("emit pop af cycles", cyc, 12);
    checkU16("emit pop af sp", g_cpu.sp, 0xFFF2);
    checkU32("emit pop af a", @intCast(u32, g_cpu.a), 0xCF);
    checkU32("emit pop af f", @intCast(u32, g_cpu.f), 0x30);

    reset();
    mmumod.write8(&g_bus, 0xC000, 0xF5);
    mmumod.write8(&g_bus, 0xC001, 0xF1);
    mmumod.write8(&g_bus, 0xC002, 0x76);
    g_cpu.pc = 0xC000;
    var built: Block = undefined;
    checkBool("push/pop build", blockmod.blockBuild(&g_cpu, &g_bus, &built), true);
    checkU32("push/pop len", @intCast(u32, built.len), 3);
    checkOp("push op", built.insns[0].op, blockmod.BlockOp.ld_mem);
    checkU32("push kind", @intCast(u32, built.insns[0].a), 16);
    checkU32("push pair", @intCast(u32, built.insns[0].b), 3);
    checkOp("pop op", built.insns[1].op, blockmod.BlockOp.ld_mem);
    checkU32("pop kind", @intCast(u32, built.insns[1].a), 17);
    checkU32("pop pair", @intCast(u32, built.insns[1].b), 3);
    checkU32("push/pop cycles", built.cycles, 32);
}

fn setupCb(op2: u8) void {
    beginAt(0xC000);
    mmumod.write8(&g_bus, 0xC000, 0xCB);
    mmumod.write8(&g_bus, 0xC001, op2);
    g_cpu.a = 0x3C;
    g_cpu.f = 0x10;
    g_cpu.b = 0x81;
    g_cpu.c = 0x42;
    g_cpu.d = 0xA5;
    g_cpu.e = 0x18;
    g_cpu.h = 0xC1;
    g_cpu.l = 0x00;
    mmumod.write8(&g_bus, 0xC100, 0x96);
}

fn testEmitCb() void {
    var i: u16 = 0;
    while (i < 256) : (i += 1) {
        const op2: u8 = @intCast(u8, i);
        setupCb(op2);
        const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
        const want: Snap = snapTake(&g_cpu, wantCyc);
        const wantMem: u8 = mmumod.read8(&g_bus, 0xC100);
        setupCb(op2);
        var blk: Block = makeBlock(.cb, op2, 0, 0, wantCyc);
        blk.start_pc = 0xC000;
        const gotCyc: u32 = runEmitted(&blk);
        const got: Snap = snapTake(&g_cpu, gotCyc);
        checkSnap("emit cb", @intCast(u32, i), got, want);
        checkMem8("emit cb mem", @intCast(u32, i), 0xC100, wantMem);
    }
}

fn testHelpers() void {
    reset();
    var ctx = DynCtx{ .cpu = &g_cpu, .bus = &g_bus, .ppu = &g_ppu, .cycles = 8, .instr_cycles = 0, .ppu_pending = 0, .ppu_advanced_dots = 0 };
    const value: u8 = helpersmod.helperRead8(&ctx, 0xC000);
    checkU32("helper read cycles", ctx.cycles, 0);
    checkU32("helper read value", @intCast(u32, value), 0);

    reset();
    ctx = DynCtx{ .cpu = &g_cpu, .bus = &g_bus, .ppu = &g_ppu, .cycles = 0, .instr_cycles = 0, .ppu_pending = 0, .ppu_advanced_dots = 0 };
    g_bus.ppu_oam_blocked = true;
    g_bus.oam[0] = 0x12;
    helpersmod.helperWrite8(&ctx, 0xFE00, 0x99);
    checkU32("helper oam write blocked", @intCast(u32, g_bus.oam[0]), 0x12);
    checkU32("helper oam read blocked", @intCast(u32, helpersmod.helperRead8(&ctx, 0xFE00)), 0xFF);
    g_bus.ppu_oam_blocked = false;

    reset();
    ctx = DynCtx{ .cpu = &g_cpu, .bus = &g_bus, .ppu = &g_ppu, .cycles = 0, .instr_cycles = 0, .ppu_pending = 0, .ppu_advanced_dots = 0 };
    g_bus.stub[0] = 0x77;
    g_bus.pages[0xA0] = Page{ .kind = .cart_ram, .base = @ptrCast([*]u8, &g_bus.stub[0]) };
    helpersmod.helperWrite8(&ctx, 0xA000, 0x5A);
    checkU32("helper cart stub write", @intCast(u32, helpersmod.helperRead8(&ctx, 0xA000)), 0x77);

    reset();
    ctx = DynCtx{ .cpu = &g_cpu, .bus = &g_bus, .ppu = &g_ppu, .cycles = 0, .instr_cycles = 0, .ppu_pending = 0, .ppu_advanced_dots = 0 };
    g_bus.pages[0xA1] = Page{ .kind = .rtc, .base = @ptrCast([*]u8, &g_cart.ram[0]) };
    g_cart.ram_enable = false;
    checkU32("helper rtc disabled read", @intCast(u32, helpersmod.helperRead8(&ctx, 0xA100)), 0xFF);
    helpersmod.helperWrite8(&ctx, 0xA100, 0x12);
    checkU32("helper rtc disabled write", @intCast(u32, helpersmod.helperRead8(&ctx, 0xA100)), 0xFF);

    reset();
    ctx = DynCtx{ .cpu = &g_cpu, .bus = &g_bus, .ppu = &g_ppu, .cycles = 0, .instr_cycles = 0, .ppu_pending = 0, .ppu_advanced_dots = 0 };
    mmumod.write8(&g_bus, 0xC000, 0x42);
    g_bus.dma.active = true;
    checkU32("helper dma read blocked", @intCast(u32, helpersmod.helperRead8(&ctx, 0xC000)), 0xFF);
    helpersmod.helperWrite8(&ctx, 0xC000, 0x99);
    g_bus.dma.active = false;
    checkU32("helper dma write blocked", @intCast(u32, mmumod.read8(&g_bus, 0xC000)), 0x42);

    reset();
    ctx = DynCtx{ .cpu = &g_cpu, .bus = &g_bus, .ppu = &g_ppu, .cycles = 0, .instr_cycles = 0, .ppu_pending = 0, .ppu_advanced_dots = 0 };
    helpersmod.helperIoWrite(&ctx, 0xFF40, 0x91);
    checkU32("helper io write/read", @intCast(u32, helpersmod.helperIoRead(&ctx, 0xFF40)), 0x91);

    reset();
    g_cpu.a = 0x81;
    g_cpu.b = 0;
    g_cpu.ime = true;
    g_bus.ie = 0x01;
    g_bus.io[0x0F] = 0x01;
    var blk: Block = undefined;
    blk.insns[0] = BlockInsn{ .op = .ld_mem, .a = 13, .b = 0, .imm = 0xFF02 };
    blk.insns[1] = BlockInsn{ .op = .ld_rn, .a = 0, .b = 0, .imm = 0x55 };
    blk.len = 2;
    blk.start_pc = 0xC000;
    blk.cycles = 24;
    blk.ends_block = true;
    var cyc: u32 = runEmitted(&blk);
    checkU32("irq early cycles", cyc, 16);
    checkU16("irq early pc", g_cpu.pc, 0xC003);
    checkU32("irq early b", @intCast(u32, g_cpu.b), 0);

    reset();
    g_cpu.a = 0x81;
    g_cpu.b = 0;
    g_cpu.ime = false;
    g_bus.ie = 0;
    g_bus.io[0x0F] = 0;
    blk.insns[0] = BlockInsn{ .op = .ld_mem, .a = 13, .b = 0, .imm = 0xFF02 };
    blk.insns[1] = BlockInsn{ .op = .ld_rn, .a = 0, .b = 0, .imm = 0x55 };
    blk.len = 2;
    blk.start_pc = 0xC000;
    blk.cycles = 24;
    blk.ends_block = true;
    cyc = runEmitted(&blk);
    checkU32("no irq cycles", cyc, 24);
    checkU16("no irq pc", g_cpu.pc, 0xC005);
    checkU32("no irq b", @intCast(u32, g_cpu.b), 0x55);

    reset();
    g_cpu.a = 0x81;
    g_cpu.b = 0;
    g_cpu.ime = true;
    g_bus.ie = 0;
    g_bus.io[0x0F] = 0x01;
    blk.insns[0] = BlockInsn{ .op = .ld_mem, .a = 13, .b = 0, .imm = 0xFF02 };
    blk.insns[1] = BlockInsn{ .op = .ld_rn, .a = 0, .b = 0, .imm = 0x55 };
    blk.len = 2;
    blk.start_pc = 0xC000;
    blk.cycles = 24;
    blk.ends_block = true;
    cyc = runEmitted(&blk);
    checkU32("irq ie0 cycles", cyc, 24);
    checkU16("irq ie0 pc", g_cpu.pc, 0xC005);
    checkU32("irq ie0 b", @intCast(u32, g_cpu.b), 0x55);

    reset();
    g_cpu.a = 0x81;
    g_cpu.b = 0;
    g_cpu.ime = true;
    g_bus.ie = 0x02;
    g_bus.io[0x0F] = 0x01;
    blk.insns[0] = BlockInsn{ .op = .ld_mem, .a = 13, .b = 0, .imm = 0xFF02 };
    blk.insns[1] = BlockInsn{ .op = .ld_rn, .a = 0, .b = 0, .imm = 0x55 };
    blk.len = 2;
    blk.start_pc = 0xC000;
    blk.cycles = 24;
    blk.ends_block = true;
    cyc = runEmitted(&blk);
    checkU32("irq nonoverlap cycles", cyc, 24);
    checkU16("irq nonoverlap pc", g_cpu.pc, 0xC005);
    checkU32("irq nonoverlap b", @intCast(u32, g_cpu.b), 0x55);
}

fn installRom() void {
    var i: usize = 0;
    while (i < 0x40) : (i += 1) {
        g_bus.pages[i] = Page{ .kind = .rom0, .base = @ptrCast([*]u8, &g_rom[i * 256]) };
        g_bus.pages[0x40 + i] = Page{ .kind = .romx, .base = @ptrCast([*]u8, &g_rom[0x4000 + i * 256]) };
    }
    g_cart.rom0_off = 0;
    g_cart.romx_off = 0;
}

fn romClear() void {
    var i: usize = 0;
    while (i < 0x8000) : (i += 1) g_rom[i] = 0;
}

fn romWrite(addr: u16, value: u8) void {
    g_rom[@intCast(usize, addr)] = value;
}

fn resetRom() void {
    reset();
    installRom();
}

fn runDyn() u32 {
    return dynarecmod.dynarecRunBlock(&g_dyn, &g_cpu, &g_bus, &g_ppu);
}

fn testCacheMapping() void {
    resetRom();
    checkBool("cache open", dynarecmod.dynarecOpen(&g_dyn, &g_bus), true);
    checkBool("cache enabled", dynarecmod.dynarecEnabled(&g_dyn), true);
    checkU32("cache bytes", @intCast(u32, dynarecmod.CODE_CACHE_BYTES), 1048576);
    checkU32("cache block max", @intCast(u32, dynarecmod.BLOCK_MAX_BYTES), 4096);
    checkU32("cache entry count", @intCast(u32, dynarecmod.ENTRY_COUNT), 4096);
    checkU32("cache used empty", @intCast(u32, g_dyn.used), 0);
}

fn makeHelperReadBlock(count: u8, nops: u8) Block {
    var blk: Block = undefined;
    var i: usize = 0;
    while (i < @intCast(usize, count)) : (i += 1) {
        blk.insns[i] = BlockInsn{ .op = .ld_mem, .a = 7, .b = 6, .imm = 0 };
    }
    var j: usize = 0;
    while (j < @intCast(usize, nops)) : (j += 1) {
        blk.insns[i + j] = BlockInsn{ .op = .nop, .a = 0, .b = 0, .imm = 0 };
    }
    blk.len = count +% nops;
    blk.start_pc = 0xC000;
    var cyc: u32 = 0;
    var k: usize = 0;
    while (k < @intCast(usize, blk.len)) : (k += 1) {
        cyc +%= blockmod.insnCycles(blk.insns[k]);
    }
    blk.cycles = cyc;
    blk.ends_block = false;
    return blk;
}

fn setupHelperRom(count: u16) void {
    resetRom();
    romClear();
    var i: u16 = 0;
    while (i < count) : (i += 1) romWrite(0x0100 +% i, 0x7E);
    romWrite(0x0100 +% count, 0x76);
    g_cpu.pc = 0x0100;
    g_cpu.a = 0;
    g_cpu.f = 0;
    g_cpu.h = 0xC1;
    g_cpu.l = 0x00;
    g_cpu.sp = 0xD000;
}

fn testHelperHeavyBlockTranslates() void {
    if (!ensureCode()) {
        checkBool("helper heavy mapping", false, true);
        return;
    }
    setupHelperRom(48);
    var i: u16 = 0;
    var wantCyc: u32 = 0;
    while (i < 48) : (i += 1) wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    const want: Snap = snapTake(&g_cpu, wantCyc);

    setupHelperRom(48);
    var blk: Block = makeHelperReadBlock(48, 0);
    blk.start_pc = 0x0100;
    const gotCyc: u32 = runEmitted(&blk);
    const got: Snap = snapTake(&g_cpu, gotCyc);
    checkSnap("helper heavy parity", 32, got, want);
    checkU32("helper heavy cycles", gotCyc, wantCyc);
    checkU32("helper heavy cycle value", gotCyc, 384);
}

fn testEmitBufferOverflowRejected() void {
    if (!ensureCode()) {
        checkBool("emit buffer overflow mapping", false, true);
        return;
    }
    var blk: Block = makeHelperReadBlock(12, 52);
    var e = x86mod.Emit{ .code = g_code, .len = 0, .cap = 3500 };
    checkBool("emit buffer overflow rejected", x86mod.emitBlock(&e, &blk), false);

    setupHelperRom(64);
    dynarecmod.dynarecFlush(&g_dyn);
    const wantCyc: u32 = cpumod.cpuStep(&g_cpu, &g_bus);
    const want: Snap = snapTake(&g_cpu, wantCyc);

    setupHelperRom(64);
    const blocks0: u32 = g_dyn.stats.blocks;
    const fall0: u32 = g_dyn.stats.fallback;
    const gotCyc: u32 = runDyn();
    const got: Snap = snapTake(&g_cpu, gotCyc);
    checkSnap("emit buffer overflow parity", 33, got, want);
    checkU32("emit buffer overflow no blocks", g_dyn.stats.blocks -% blocks0, 0);
    checkU32("emit buffer overflow fallback", g_dyn.stats.fallback -% fall0, 1);
    checkBool("emit buffer overflow no entry", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0100) == null, true);
}

fn setupNormalRom() void {
    resetRom();
    romClear();
    romWrite(0x0100, 0x3E);
    romWrite(0x0101, 0x12);
    romWrite(0x0102, 0x3C);
    romWrite(0x0103, 0xC3);
    romWrite(0x0104, 0x06);
    romWrite(0x0105, 0x01);
    romWrite(0x0106, 0x76);
    g_cpu.pc = 0x0100;
    g_cpu.a = 0;
    g_cpu.f = 0;
    g_cpu.sp = 0xD000;
}

fn testNormalBlockTranslates() void {
    setupNormalRom();
    dynarecmod.dynarecFlush(&g_dyn);
    var wantCyc: u32 = 0;
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    const want: Snap = snapTake(&g_cpu, wantCyc);

    setupNormalRom();
    const blocks0: u32 = g_dyn.stats.blocks;
    const gotCyc: u32 = runDyn();
    const got: Snap = snapTake(&g_cpu, gotCyc);
    checkSnap("normal block parity", 34, got, want);
    checkU32("normal block translated", g_dyn.stats.blocks -% blocks0, 1);
    checkBool("normal block entry", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0100) != null, true);
}

fn testCacheDistinctAndBank() void {
    resetRom();
    dynarecmod.dynarecFlush(&g_dyn);
    romClear();
    g_cpu.pc = 0x0100;
    _ = runDyn();
    g_cpu.pc = 0x0101;
    _ = runDyn();
    checkBool("cache distinct pc 0100", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0100) != null, true);
    checkBool("cache distinct pc 0101", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0101) != null, true);

    g_cart.rom0_off = 0x4000;
    g_cpu.pc = 0x0100;
    _ = runDyn();
    checkBool("cache bank0 entry", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0100) != null, true);
    checkBool("cache bank1 entry", dynarecmod.dynarecLookup(&g_dyn, 1, 0x0100) != null, true);

    dynarecmod.dynarecInvalidateBank(&g_dyn, 0);
    checkBool("cache bank0 invalidated", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0100) == null, true);
    checkBool("cache bank1 kept", dynarecmod.dynarecLookup(&g_dyn, 1, 0x0100) != null, true);

    g_cart.rom0_off = 0;
    g_cart.romx_off = 0x4000;
    g_cpu.pc = 0x0200;
    _ = runDyn();
    g_cpu.pc = 0x4100;
    _ = runDyn();
    checkBool("cache rom0 range victim", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0200) != null, true);
    checkBool("cache romx range victim", dynarecmod.dynarecLookup(&g_dyn, 1, 0x4100) != null, true);
    dynarecmod.dynarecInvalidateRom0(&g_dyn);
    checkBool("cache rom0 range invalidated", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0200) == null, true);
    checkBool("cache rom0 keeps romx", dynarecmod.dynarecLookup(&g_dyn, 1, 0x4100) != null, true);

    g_cpu.pc = 0x0400;
    _ = runDyn();
    checkBool("cache romx invalidate victim", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0400) != null, true);
    dynarecmod.dynarecInvalidateRomx(&g_dyn);
    checkBool("cache romx invalidated", dynarecmod.dynarecLookup(&g_dyn, 1, 0x4100) == null, true);
    checkBool("cache romx keeps rom0", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0400) != null, true);
}

fn testCacheReset() void {
    resetRom();
    dynarecmod.dynarecFlush(&g_dyn);
    romClear();
    g_cpu.pc = 0x0200;
    _ = runDyn();
    checkBool("cache reset old entry", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0200) != null, true);
    g_dyn.used = cachemod.CODE_CACHE_BYTES - 8;
    g_cpu.pc = 0x0300;
    _ = runDyn();
    checkBool("cache reset dropped old", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0200) == null, true);
    checkBool("cache reset rewrote", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0300) != null, true);
    checkBool("cache reset used rewound", g_dyn.used < cachemod.CODE_CACHE_BYTES / 2, true);
}

fn setupTrampolineRom() void {
    resetRom();
    romClear();
    romWrite(0x0100, 0x3E);
    romWrite(0x0101, 0x12);
    romWrite(0x0102, 0x3C);
    romWrite(0x0103, 0x00);
    romWrite(0x0104, 0xC3);
    romWrite(0x0105, 0x00);
    romWrite(0x0106, 0x02);
    g_cpu.pc = 0x0100;
    g_cpu.a = 0;
    g_cpu.f = 0;
}

fn testCacheTrampoline() void {
    setupTrampolineRom();
    dynarecmod.dynarecFlush(&g_dyn);
    var wantCyc: u32 = 0;
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    const want: Snap = snapTake(&g_cpu, wantCyc);

    setupTrampolineRom();
    const blocks0: u32 = g_dyn.stats.blocks;
    const exec0: u32 = g_dyn.stats.executed;
    const gotCyc: u32 = runDyn();
    const got: Snap = snapTake(&g_cpu, gotCyc);
    checkSnap("cache trampoline", 1, got, want);
    checkU32("cache trampoline cycles", gotCyc, 32);
    checkBool("cache trampoline translated", g_dyn.stats.blocks > blocks0, true);
    checkBool("cache trampoline executed", g_dyn.stats.executed > exec0, true);
}

fn setupLoopRom() void {
    resetRom();
    romClear();
    romWrite(0x0100, 0xC3);
    romWrite(0x0101, 0x03);
    romWrite(0x0102, 0x01);
    romWrite(0x0103, 0xC3);
    romWrite(0x0104, 0x00);
    romWrite(0x0105, 0x01);
    g_cpu.pc = 0x0100;
    g_cpu.a = 0x11;
    g_cpu.f = 0;
    g_cpu.sp = 0xD000;
}

fn testCacheHotLoop() void {
    setupLoopRom();
    dynarecmod.dynarecFlush(&g_dyn);
    var warm: u8 = 0;
    while (warm < 4) : (warm += 1) _ = runDyn();

    setupLoopRom();
    var wantCyc: u32 = 0;
    var i: u8 = 0;
    while (i < 64) : (i += 1) wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    const want: Snap = snapTake(&g_cpu, wantCyc);

    setupLoopRom();
    const exec0: u32 = g_dyn.stats.executed;
    const chain0: u32 = g_dyn.stats.chained;
    const gotCyc: u32 = runDyn();
    const got: Snap = snapTake(&g_cpu, gotCyc);
    const ran: u32 = g_dyn.stats.executed -% exec0;
    const linked: u32 = g_dyn.stats.chained -% chain0;
    checkSnap("cache hot loop", 2, got, want);
    checkU32("cache hot loop cycles", gotCyc, 1024);
    checkU32("cache hot loop executed", ran, 64);
    checkU32("cache hot loop chained", linked, 63);
    checkBool("cache hot loop successor>=chained", ran >= linked, true);
}

fn setupCallRetRom() void {
    resetRom();
    romClear();
    romWrite(0x0200, 0xCD);
    romWrite(0x0201, 0x06);
    romWrite(0x0202, 0x02);
    romWrite(0x0203, 0xC3);
    romWrite(0x0204, 0x00);
    romWrite(0x0205, 0x02);
    romWrite(0x0206, 0xC9);
    g_cpu.pc = 0x0200;
    g_cpu.a = 0x33;
    g_cpu.f = 0;
    g_cpu.sp = 0xD000;
}

fn testCacheCallRet() void {
    setupCallRetRom();
    dynarecmod.dynarecFlush(&g_dyn);
    var warm: u8 = 0;
    while (warm < 8) : (warm += 1) _ = runDyn();

    setupCallRetRom();
    var wantCyc: u32 = 0;
    var i: u8 = 0;
    while (i < 64) : (i += 1) wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    const want: Snap = snapTake(&g_cpu, wantCyc);
    const wantLo: u8 = mmumod.read8(&g_bus, g_cpu.sp);
    const wantHi: u8 = mmumod.read8(&g_bus, g_cpu.sp +% 1);

    setupCallRetRom();
    const exec0: u32 = g_dyn.stats.executed;
    const chain0: u32 = g_dyn.stats.chained;
    const gotCyc: u32 = runDyn();
    const got: Snap = snapTake(&g_cpu, gotCyc);
    const ran: u32 = g_dyn.stats.executed -% exec0;
    const linked: u32 = g_dyn.stats.chained -% chain0;
    checkSnap("cache call/ret", 3, got, want);
    checkU32("cache call/ret cycles", gotCyc, 1200);
    checkU32("cache call/ret executed", ran, 64);
    checkU32("cache call/ret chained", linked, 63);
    checkBool("cache call/ret successor>=chained", ran >= linked, true);
    checkU32("cache call/ret stack lo", @intCast(u32, mmumod.read8(&g_bus, g_cpu.sp)), @intCast(u32, wantLo));
    checkU32("cache call/ret stack hi", @intCast(u32, mmumod.read8(&g_bus, g_cpu.sp +% 1)), @intCast(u32, wantHi));
}

fn testCachePendingInterruptChain() void {
    setupLoopRom();
    dynarecmod.dynarecFlush(&g_dyn);
    var warm: u8 = 0;
    while (warm < 4) : (warm += 1) _ = runDyn();

    setupLoopRom();
    g_cpu.ime = true;
    g_bus.ie = 0x01;
    g_bus.io[0x0F] = 0x01;
    const exec0: u32 = g_dyn.stats.executed;
    const chain0: u32 = g_dyn.stats.chained;
    const gotCyc: u32 = runDyn();
    const ran: u32 = g_dyn.stats.executed -% exec0;
    const linked: u32 = g_dyn.stats.chained -% chain0;
    checkU32("cache irq chain cycles", gotCyc, 16);
    checkU32("cache irq chain executed", ran, 1);
    checkU32("cache irq chain chained", linked, 0);
    checkU16("cache irq chain pc", g_cpu.pc, 0x0103);
}

fn testCacheRomBounds() void {
    resetRom();
    dynarecmod.dynarecFlush(&g_dyn);
    romClear();
    g_cpu.pc = 0x7FFE;
    const blocks0: u32 = g_dyn.stats.blocks;
    const fall0: u32 = g_dyn.stats.fallback;
    const endCyc: u32 = runDyn();
    checkU32("cache rom end fallback cycles", endCyc, 4);
    checkU16("cache rom end fallback pc", g_cpu.pc, 0x7FFF);
    checkBool("cache rom end no entry", dynarecmod.dynarecLookup(&g_dyn, 0, 0x7FFE) == null, true);
    checkU32("cache rom end blocked", g_dyn.stats.blocks -% blocks0, 0);
    checkU32("cache rom end fallback count", g_dyn.stats.fallback -% fall0, 1);

    resetRom();
    dynarecmod.dynarecFlush(&g_dyn);
    romClear();
    romWrite(0x3FFE, 0xC3);
    romWrite(0x3FFF, 0x34);
    romWrite(0x4000, 0x12);
    g_cpu.pc = 0x3FFE;
    const crossCyc: u32 = runDyn();
    checkU32("cache romx boundary fallback cycles", crossCyc, 16);
    checkU16("cache romx boundary fallback pc", g_cpu.pc, 0x1234);
    checkBool("cache romx boundary blocked", dynarecmod.dynarecLookup(&g_dyn, 0, 0x3FFE) == null, true);

    resetRom();
    dynarecmod.dynarecFlush(&g_dyn);
    romClear();
    romWrite(0x3FFD, 0xC3);
    romWrite(0x3FFE, 0x00);
    romWrite(0x3FFF, 0x02);
    g_cpu.pc = 0x3FFD;
    const fitCyc: u32 = runDyn();
    checkU32("cache romx boundary fit cycles", fitCyc, 16);
    checkU16("cache romx boundary fit pc", g_cpu.pc, 0x0200);
    checkBool("cache romx boundary fit entry", dynarecmod.dynarecLookup(&g_dyn, 0, 0x3FFD) != null, true);
}

fn setupLoopRomx() void {
    resetRom();
    romClear();
    g_cart.romx_off = 0x4000;
    romWrite(0x4100, 0xC3);
    romWrite(0x4101, 0x03);
    romWrite(0x4102, 0x41);
    romWrite(0x4103, 0xC3);
    romWrite(0x4104, 0x00);
    romWrite(0x4105, 0x41);
    g_cpu.pc = 0x4100;
    g_cpu.a = 0x44;
    g_cpu.f = 0;
    g_cpu.sp = 0xD000;
}

fn testCacheRomxChainAndMismatch() void {
    setupLoopRomx();
    dynarecmod.dynarecFlush(&g_dyn);
    var warm: u8 = 0;
    while (warm < 4) : (warm += 1) _ = runDyn();

    setupLoopRomx();
    var wantCyc: u32 = 0;
    var i: u8 = 0;
    while (i < 64) : (i += 1) wantCyc +%= cpumod.cpuStep(&g_cpu, &g_bus);
    const want: Snap = snapTake(&g_cpu, wantCyc);

    setupLoopRomx();
    const exec0: u32 = g_dyn.stats.executed;
    const chain0: u32 = g_dyn.stats.chained;
    const gotCyc: u32 = runDyn();
    const got: Snap = snapTake(&g_cpu, gotCyc);
    const ran: u32 = g_dyn.stats.executed -% exec0;
    const linked: u32 = g_dyn.stats.chained -% chain0;
    checkSnap("cache romx hot loop", 4, got, want);
    checkU32("cache romx hot loop cycles", gotCyc, 1024);
    checkU32("cache romx hot loop executed", ran, 64);
    checkU32("cache romx hot loop chained", linked, 63);

    resetRom();
    dynarecmod.dynarecFlush(&g_dyn);
    romClear();
    g_cart.romx_off = 0x4000;
    romWrite(0x4200, 0xC3);
    romWrite(0x4201, 0x00);
    romWrite(0x4202, 0x02);
    g_cpu.pc = 0x4200;
    _ = runDyn();
    g_cpu.pc = 0x0200;
    _ = runDyn();
    checkBool("cache bank mismatch target", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0200) != null, true);

    resetRom();
    g_cart.romx_off = 0x4000;
    g_cart.rom0_off = 0x4000;
    g_cpu.pc = 0x4200;
    const mismatchChain0: u32 = g_dyn.stats.chained;
    const mismatchCyc: u32 = runDyn();
    checkU32("cache bank mismatch cycles", mismatchCyc, 16);
    checkU32("cache bank mismatch chained", g_dyn.stats.chained -% mismatchChain0, 0);
    checkU16("cache bank mismatch pc", g_cpu.pc, 0x0200);
}

fn testCacheSamePcDifferentBank() void {
    resetRom();
    dynarecmod.dynarecFlush(&g_dyn);
    romClear();
    g_cart.romx_off = 0x4000;
    romWrite(0x4100, 0x3E);
    romWrite(0x4101, 0x11);
    g_cpu.pc = 0x4100;
    g_cpu.a = 0;
    _ = runDyn();
    checkU32("cache same pc bank1 value", @intCast(u32, g_cpu.a), 0x11);

    g_cart.romx_off = 0x8000;
    romWrite(0x4100, 0x3E);
    romWrite(0x4101, 0x22);
    g_cpu.pc = 0x4100;
    g_cpu.a = 0;
    _ = runDyn();
    checkU32("cache same pc bank2 value", @intCast(u32, g_cpu.a), 0x22);

    g_cart.romx_off = 0x4000;
    g_cpu.pc = 0x4100;
    g_cpu.a = 0;
    _ = runDyn();
    checkU32("cache same pc bank1 cached value", @intCast(u32, g_cpu.a), 0x11);
    checkBool("cache same pc bank1 entry", dynarecmod.dynarecLookup(&g_dyn, 1, 0x4100) != null, true);
    checkBool("cache same pc bank2 entry", dynarecmod.dynarecLookup(&g_dyn, 2, 0x4100) != null, true);
}

fn testCacheCollision() void {
    resetRom();
    dynarecmod.dynarecFlush(&g_dyn);
    romClear();
    g_cpu.pc = 0x0100;
    _ = runDyn();
    checkBool("cache collision first", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0100) != null, true);
    const used0: usize = g_dyn.used;
    const coll0: u32 = g_dyn.stats.collisions;
    g_cpu.pc = 0x1100;
    _ = runDyn();
    checkBool("cache collision old dropped", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0100) == null, true);
    checkBool("cache collision replaced", dynarecmod.dynarecLookup(&g_dyn, 0, 0x1100) != null, true);
    checkU32("cache collision counted", g_dyn.stats.collisions -% coll0, 1);
    checkBool("cache collision keeps bytes", g_dyn.used > used0, true);
}

fn coveragePermille(tin: u32, min: u32) u32 {
    const total: u32 = tin +% min;
    if (total == 0) return 0;
    return @intCast(u32, (@as(u64, tin) * 1000) / @as(u64, total));
}

fn testDynarecCoverage() void {
    setupNormalRom();
    var blk: Block = undefined;
    checkBool("coverage build", blockmod.blockBuild(&g_cpu, &g_bus, &blk), true);
    const block_insns: u32 = @intCast(u32, blk.len);

    setupNormalRom();
    dynarecmod.dynarecFlush(&g_dyn);
    const tin0: u32 = g_dyn.stats.tinstr;
    const min0: u32 = g_dyn.stats.minstr;
    const rej0: u32 = g_dyn.stats.rejected;
    _ = runDyn();
    const tin1: u32 = g_dyn.stats.tinstr -% tin0;
    const min1: u32 = g_dyn.stats.minstr -% min0;
    const rej1: u32 = g_dyn.stats.rejected -% rej0;
    checkU32("coverage cold tinstr", tin1, block_insns);
    checkU32("coverage cold minstr", min1, 0);
    checkU32("coverage cold rejected", rej1, 0);
    checkU32("coverage cold permille", coveragePermille(tin1, min1), 1000);

    g_cpu.pc = 0x0100;
    const tin1b: u32 = g_dyn.stats.tinstr;
    const blocks1: u32 = g_dyn.stats.blocks;
    _ = runDyn();
    checkU32("coverage cached tinstr", g_dyn.stats.tinstr -% tin1b, block_insns);
    checkU32("coverage cached no retranslate", g_dyn.stats.blocks -% blocks1, 0);

    resetRom();
    g_cpu.pc = 0xC000;
    const min2: u32 = g_dyn.stats.minstr;
    _ = runDyn();
    checkU32("coverage non-rom minstr", g_dyn.stats.minstr -% min2, 1);

    setupHelperRom(64);
    dynarecmod.dynarecFlush(&g_dyn);
    const rej2: u32 = g_dyn.stats.rejected;
    const min3: u32 = g_dyn.stats.minstr;
    _ = runDyn();
    checkU32("coverage reject rejected", g_dyn.stats.rejected -% rej2, 1);
    checkU32("coverage reject minstr", g_dyn.stats.minstr -% min3, 1);
    checkBool("coverage reject no entry", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0100) == null, true);
}

fn setupCoverageChainRom() void {
    resetRom();
    romClear();
    romWrite(0x0200, 0x3E);
    romWrite(0x0201, 0x11);
    romWrite(0x0202, 0xC3);
    romWrite(0x0203, 0x06);
    romWrite(0x0204, 0x02);
    romWrite(0x0206, 0xE9);
    g_cpu.pc = 0x0200;
    g_cpu.a = 0;
    g_cpu.f = 0;
    g_cpu.h = 0x12;
    g_cpu.l = 0x34;
    g_cpu.sp = 0xD000;
}

fn testDynarecCoverageChain() void {
    setupCoverageChainRom();
    dynarecmod.dynarecFlush(&g_dyn);
    _ = runDyn();
    _ = runDyn();
    checkBool("coverage chain A entry", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0200) != null, true);
    checkBool("coverage chain B entry", dynarecmod.dynarecLookup(&g_dyn, 0, 0x0206) != null, true);

    setupCoverageChainRom();
    const tin0: u32 = g_dyn.stats.tinstr;
    const chain0: u32 = g_dyn.stats.chained;
    const blocks0: u32 = g_dyn.stats.blocks;
    _ = runDyn();
    checkU32("coverage chain tinstr", g_dyn.stats.tinstr -% tin0, 3);
    checkU32("coverage chain chained", g_dyn.stats.chained -% chain0, 1);
    checkU32("coverage chain no retranslate", g_dyn.stats.blocks -% blocks0, 0);
    checkU16("coverage chain pc", g_cpu.pc, 0x1234);
}

fn testDynarecCounterWrapping() void {
    resetRom();
    g_cpu.pc = 0xC000;
    const min_saved: u32 = g_dyn.stats.minstr;
    g_dyn.stats.minstr = 0xFFFFFFFF;
    _ = runDyn();
    checkU32("coverage minstr wraps", g_dyn.stats.minstr, 0);
    g_dyn.stats.minstr = min_saved;

    setupHelperRom(64);
    dynarecmod.dynarecFlush(&g_dyn);
    const rej_saved: u32 = g_dyn.stats.rejected;
    g_dyn.stats.rejected = 0xFFFFFFFF;
    _ = runDyn();
    checkU32("coverage rejected wraps", g_dyn.stats.rejected, 0);
    g_dyn.stats.rejected = rej_saved;
}

fn testDynarecEmuMinstr() void {
    if (!setupDynarecEmu(true)) {
        checkBool("emu minstr setup", false, true);
        return;
    }
    if (!dynarecmod.dynarecEnabled(&g_emu.dynarec)) {
        checkBool("emu minstr direct open", dynarecmod.dynarecOpen(&g_emu.dynarec, &g_emu.bus), true);
    }
    checkBool("emu minstr enabled", emumod.emuDynarecEnabled(&g_emu), true);
    g_emu.cpu.pc = 0xC000;
    const min0: u32 = g_emu.dynarec.stats.minstr;
    _ = emumod.emuRunFrame(&g_emu);
    checkBool("emu minstr increments", g_emu.dynarec.stats.minstr > min0, true);
    _ = emumod.emuSetDynarec(&g_emu, false);
}

fn testCacheClose() void {
    dynarecmod.dynarecClose(&g_dyn);
    checkBool("cache close disabled", dynarecmod.dynarecEnabled(&g_dyn), false);
    dynarecmod.dynarecClose(&g_dyn);
    checkBool("cache double close", dynarecmod.dynarecEnabled(&g_dyn), false);
}

fn makeDynarecRom() void {
    var i: usize = 0;
    while (i < DYN_ROM_BYTES) : (i += 1) g_emu.rom[i] = 0;

    // ROM0 entry: jump into the initial switchable bank (bank 1).
    g_emu.rom[0x0100] = 0xC3;
    g_emu.rom[0x0101] = 0x00;
    g_emu.rom[0x0102] = 0x40;

    g_emu.rom[0x0147] = 0x03; // MBC1+RAM+BATTERY
    g_emu.rom[0x0148] = 0x02; // 128 KiB, four banks
    g_emu.rom[0x0149] = 0x02; // 8 KiB cart RAM

    // Bank 1 at 0x4000: emit serial 'A', then return to ROM0.
    var p: usize = 0x4000;
    g_emu.rom[p + 0] = 0x3E;
    g_emu.rom[p + 1] = 0x41;
    g_emu.rom[p + 2] = 0xE0;
    g_emu.rom[p + 3] = 0x01;
    g_emu.rom[p + 4] = 0x3E;
    g_emu.rom[p + 5] = 0x81;
    g_emu.rom[p + 6] = 0xE0;
    g_emu.rom[p + 7] = 0x02;
    g_emu.rom[p + 8] = 0xC3;
    g_emu.rom[p + 9] = 0x50;
    g_emu.rom[p + 10] = 0x01;

    // ROM0 at 0x150: enable RAM, write save RAM, switch ROMX to bank 2,
    // then jump to the remapped 0x4000 window.
    p = 0x0150;
    g_emu.rom[p + 0] = 0x31;
    g_emu.rom[p + 1] = 0xFE;
    g_emu.rom[p + 2] = 0xFF;
    g_emu.rom[p + 3] = 0x3E;
    g_emu.rom[p + 4] = 0x0A;
    g_emu.rom[p + 5] = 0xEA;
    g_emu.rom[p + 6] = 0x00;
    g_emu.rom[p + 7] = 0x00;
    g_emu.rom[p + 8] = 0x3E;
    g_emu.rom[p + 9] = 0x5A;
    g_emu.rom[p + 10] = 0xEA;
    g_emu.rom[p + 11] = 0x00;
    g_emu.rom[p + 12] = 0xA0;
    g_emu.rom[p + 13] = 0x3E;
    g_emu.rom[p + 14] = 0x02;
    g_emu.rom[p + 15] = 0xEA;
    g_emu.rom[p + 16] = 0x00;
    g_emu.rom[p + 17] = 0x20;
    g_emu.rom[p + 18] = 0xC3;
    g_emu.rom[p + 19] = 0x00;
    g_emu.rom[p + 20] = 0x40;

    // Bank 2 at 0x4000: emit serial 'B', then halt so both paths settle on the
    // interpreter's 4-cycle halted steps for the rest of the frame.
    p = 0x8000;
    g_emu.rom[p + 0] = 0x3E;
    g_emu.rom[p + 1] = 0x42;
    g_emu.rom[p + 2] = 0xE0;
    g_emu.rom[p + 3] = 0x01;
    g_emu.rom[p + 4] = 0x3E;
    g_emu.rom[p + 5] = 0x81;
    g_emu.rom[p + 6] = 0xE0;
    g_emu.rom[p + 7] = 0x02;
    g_emu.rom[p + 8] = 0x76;
}

fn setupDynarecEmu(on: bool) bool {
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = false, .serial_log = false, .turbo = true, .dynarec = false });
    makeDynarecRom();
    g_emu.rom_len = DYN_ROM_BYTES;
    cartmod.cartLoad(&g_emu.cart, g_emu.rom[0..DYN_ROM_BYTES]) catch return false;
    emumod.emuReset(&g_emu);
    g_emu.bus.ie = 0;
    g_emu.bus.io[0x0F] = 0;
    _ = emumod.emuSetDynarec(&g_emu, on);
    return true;
}

fn drainAudioCount() usize {
    var total: usize = 0;
    while (true) {
        const got: usize = emumod.emuAudioSamples(&g_emu, g_audio_buf[0..]);
        total += got;
        if (got == 0) break;
    }
    return total;
}

fn captureFrame(out: *FrameSnap) void {
    out.cycles = emumod.emuRunFrame(&g_emu);
    const fb: []const u32 = emumod.emuFramebuffer(&g_emu);
    var i: usize = 0;
    while (i < DYN_FB_PIXELS) : (i += 1) out.fb[i] = fb[i];
    out.serial_len = emumod.emuTakeSerial(&g_emu, out.serial[0..]);
    const cartp: *cartmod.Cart = &g_emu.cart;
    i = 0;
    while (i < DYN_SAVE_BYTES) : (i += 1) out.ram[i] = cartp.ram[i];
    out.audio = drainAudioCount();
}

fn snapFbEq(a: *const FrameSnap, b: *const FrameSnap) bool {
    var i: usize = 0;
    while (i < DYN_FB_PIXELS) : (i += 1) {
        if (a.fb[i] != b.fb[i]) return false;
    }
    return true;
}

fn snapSerialEq(a: *const FrameSnap, b: *const FrameSnap) bool {
    if (a.serial_len != b.serial_len) return false;
    var i: usize = 0;
    while (i < a.serial_len) : (i += 1) {
        if (a.serial[i] != b.serial[i]) return false;
    }
    return true;
}

fn snapRamEq(a: *const FrameSnap, b: *const FrameSnap) bool {
    var i: usize = 0;
    while (i < DYN_SAVE_BYTES) : (i += 1) {
        if (a.ram[i] != b.ram[i]) return false;
    }
    return true;
}

fn testDynarecFrameParity() void {
    if (!setupDynarecEmu(false)) {
        checkBool("dynarec parity rom off", false, true);
        return;
    }
    checkBool("dynarec parity off disabled", emumod.emuDynarecEnabled(&g_emu), false);
    captureFrame(&g_snap_off);
    _ = emumod.emuSetDynarec(&g_emu, false);

    if (!setupDynarecEmu(true)) {
        checkBool("dynarec parity rom on", false, true);
        return;
    }
    const dynp: *const cachemod.Dynarec = &g_emu.dynarec;
    const on: bool = emumod.emuDynarecEnabled(&g_emu);
    if (@isWindows()) {
        checkBool("dynarec parity host enabled", on, true);
    } else {
        // Non-Win32 must not expose the unit-test RWX mapping as enabled.
        checkBool("dynarec parity host hard gate", on, false);
    }

    if (!on) {
        captureFrame(&g_snap_on);
        checkBool("dynarec disabled framebuffer parity", snapFbEq(&g_snap_off, &g_snap_on), true);
        checkBool("dynarec disabled serial parity", snapSerialEq(&g_snap_off, &g_snap_on), true);
        checkBool("dynarec disabled save parity", snapRamEq(&g_snap_off, &g_snap_on), true);
        checkU32("dynarec disabled audio count", @intCast(u32, g_snap_on.audio), @intCast(u32, g_snap_off.audio));
        checkU32("dynarec disabled blocks", dynp.stats.blocks, 0);
        checkU32("dynarec disabled executed", dynp.stats.executed, 0);
        return;
    }

    captureFrame(&g_snap_on);
    const cartp: *cartmod.Cart = &g_emu.cart;
    checkBool("dynarec parity framebuffer", snapFbEq(&g_snap_off, &g_snap_on), true);
    checkBool("dynarec parity serial", snapSerialEq(&g_snap_off, &g_snap_on), true);
    checkBool("dynarec parity save", snapRamEq(&g_snap_off, &g_snap_on), true);
    checkU32("dynarec parity audio count", @intCast(u32, g_snap_on.audio), @intCast(u32, g_snap_off.audio));
    checkU32("dynarec parity cycles", g_snap_on.cycles, g_snap_off.cycles);
    checkBool("dynarec anti-vacuous blocks", dynp.stats.blocks > 0, true);
    checkBool("dynarec anti-vacuous executed", dynp.stats.executed > 0, true);
    checkBool("dynarec anti-vacuous fallback", dynp.stats.fallback > 0, true);
    checkU32("dynarec romx bank", @intCast(u32, cartp.romx_off), 0x8000);
    checkBool("dynarec romx invalidated", dynarecmod.dynarecLookup(&g_emu.dynarec, 1, 0x4000) == null, true);
    checkU32("dynarec save byte", @intCast(u32, cartp.ram[0]), 0x5A);
    _ = emumod.emuSetDynarec(&g_emu, false);
}

fn testDynarecReinitClose() void {
    if (!setupDynarecEmu(false)) {
        checkBool("dynarec reinit setup", false, true);
        return;
    }
    const dynp: *cachemod.Dynarec = &g_emu.dynarec;
    checkBool("dynarec reinit direct open", dynarecmod.dynarecOpen(dynp, &g_emu.bus), true);
    checkBool("dynarec reinit direct mapped", dynarecmod.dynarecEnabled(dynp), true);
    emumod.emuInit(&g_emu, emumod.EmuConfig{ .cgb = false, .serial_log = false, .turbo = true, .dynarec = false });
    checkBool("dynarec reinit released mapping", dynarecmod.dynarecEnabled(dynp), false);
    checkBool("dynarec reinit reopen after release", dynarecmod.dynarecOpen(dynp, &g_emu.bus), true);
    dynarecmod.dynarecClose(dynp);
    checkBool("dynarec reinit close idempotent", dynarecmod.dynarecEnabled(dynp), false);
    dynarecmod.dynarecClose(dynp);
    checkBool("dynarec reinit double close", dynarecmod.dynarecEnabled(dynp), false);
}

fn testDynarecDispatchFallbacks() void {
    // These assertions require a real enabled cache (Win32/Wine); the native
    // Linux hard gate is covered by testDynarecFrameParity.
    if (!@isWindows()) return;
    const dynp: *const cachemod.Dynarec = &g_emu.dynarec;

    // WRAM PC: interpreter-only and counted in fallback, no block execution.
    if (!setupDynarecEmu(true)) {
        checkBool("dynarec dispatch wram setup", false, true);
        return;
    }
    const busp: *mmumod.Bus = &g_emu.bus;
    checkBool("dynarec dispatch wram enabled", emumod.emuDynarecEnabled(&g_emu), true);
    mmumod.write8(busp, 0xC000, 0x18);
    mmumod.write8(busp, 0xC001, 0xFE);
    g_emu.cpu.pc = 0xC000;
    const wram_blocks: u32 = dynp.stats.blocks;
    const wram_exec: u32 = dynp.stats.executed;
    _ = emumod.emuRunFrame(&g_emu);
    checkU32("dynarec dispatch wram blocks unchanged", dynp.stats.blocks, wram_blocks);
    checkU32("dynarec dispatch wram executed unchanged", dynp.stats.executed, wram_exec);
    checkBool("dynarec dispatch wram fallback", dynp.stats.fallback > 0, true);

    // HRAM PC: same interpreter-only rule.
    if (!setupDynarecEmu(true)) {
        checkBool("dynarec dispatch hram setup", false, true);
        return;
    }
    const busp2: *mmumod.Bus = &g_emu.bus;
    mmumod.write8(busp2, 0xFF80, 0x18);
    mmumod.write8(busp2, 0xFF81, 0xFE);
    g_emu.cpu.pc = 0xFF80;
    const hram_blocks: u32 = dynp.stats.blocks;
    const hram_exec: u32 = dynp.stats.executed;
    _ = emumod.emuRunFrame(&g_emu);
    checkU32("dynarec dispatch hram blocks unchanged", dynp.stats.blocks, hram_blocks);
    checkU32("dynarec dispatch hram executed unchanged", dynp.stats.executed, hram_exec);
    checkBool("dynarec dispatch hram fallback", dynp.stats.fallback > 0, true);

    // Pending HDMA stall cycles must be consumed by cpuStep, not skipped by a
    // dynarec block. A stall larger than a frame makes this one step decisive.
    if (!setupDynarecEmu(true)) {
        checkBool("dynarec dispatch hdma setup", false, true);
        return;
    }
    const busp3: *mmumod.Bus = &g_emu.bus;
    g_emu.cpu.pc = 0x0100;
    busp3.hdma.cpu_halt_cycles = 80000;
    const hdma_blocks: u32 = dynp.stats.blocks;
    const hdma_exec: u32 = dynp.stats.executed;
    _ = emumod.emuRunFrame(&g_emu);
    checkU32("dynarec dispatch hdma blocks unchanged", dynp.stats.blocks, hdma_blocks);
    checkU32("dynarec dispatch hdma executed unchanged", dynp.stats.executed, hdma_exec);
    checkU32("dynarec dispatch hdma fallback", dynp.stats.fallback, 1);
    checkU32("dynarec dispatch hdma consumed", busp3.hdma.cpu_halt_cycles, 0);

    // --mooneye enables the LD B,B breakpoint but still dispatches dynarec for
    // the pre-breakpoint block.
    if (!setupDynarecEmu(true)) {
        checkBool("dynarec dispatch mooneye setup", false, true);
        return;
    }
    var p: usize = 0x0200;
    g_emu.rom[p + 0] = 0x06;
    g_emu.rom[p + 1] = 0x03;
    g_emu.rom[p + 2] = 0x0E;
    g_emu.rom[p + 3] = 0x05;
    g_emu.rom[p + 4] = 0x16;
    g_emu.rom[p + 5] = 0x08;
    g_emu.rom[p + 6] = 0x1E;
    g_emu.rom[p + 7] = 0x0D;
    g_emu.rom[p + 8] = 0x26;
    g_emu.rom[p + 9] = 0x15;
    g_emu.rom[p + 10] = 0x2E;
    g_emu.rom[p + 11] = 0x22;
    g_emu.rom[p + 12] = 0x40;
    g_emu.cpu.pc = 0x0200;
    emumod.emuSetMooneye(&g_emu, true);
    const moon_blocks: u32 = dynp.stats.blocks;
    const moon_exec: u32 = dynp.stats.executed;
    const moon_fallback: u32 = dynp.stats.fallback;
    _ = emumod.emuRunFrame(&g_emu);
    checkBool("dynarec dispatch mooneye stopped", emumod.emuMooneyeStopped(&g_emu), true);
    checkBool("dynarec dispatch mooneye pass", emumod.emuMooneyePass(&g_emu), true);
    checkBool("dynarec dispatch mooneye blocks grew", dynp.stats.blocks > moon_blocks, true);
    checkBool("dynarec dispatch mooneye executed grew", dynp.stats.executed > moon_exec, true);
    checkU32("dynarec dispatch mooneye fallback unchanged", dynp.stats.fallback, moon_fallback);
    _ = emumod.emuSetDynarec(&g_emu, false);
}

fn testDynarecPpuOrdering() void {
    resetRom();
    romClear();
    romWrite(0x0100, 0x31);
    romWrite(0x0101, 0xFE);
    romWrite(0x0102, 0xFF);
    romWrite(0x0103, 0x21);
    romWrite(0x0104, 0x40);
    romWrite(0x0105, 0xFF);
    romWrite(0x0106, 0xCB);
    romWrite(0x0107, 0x7E);
    romWrite(0x0108, 0xCB);
    romWrite(0x0109, 0xBE);
    romWrite(0x010A, 0x00);
    romWrite(0x010B, 0x00);
    romWrite(0x010C, 0x00);
    romWrite(0x010D, 0x00);
    romWrite(0x010E, 0x3E);
    romWrite(0x010F, 0x81);
    romWrite(0x0110, 0xE0);
    romWrite(0x0111, 0x40);
    romWrite(0x0112, 0x76);
    dynarecmod.dynarecFlush(&g_dyn);

    // Pre-translate the enable block so the disable block links to it and the
    // two execute in one dispatch. Without the link the frame loop would sync
    // the PPU at the block boundary and hide a missing helper-side sync.
    g_cpu.pc = 0x010A;
    g_cpu.h = 0xFF;
    g_cpu.l = 0x40;
    g_cpu.a = 0;
    _ = runDyn();
    checkBool("dynarec ppu ordering prewarm", dynarecmod.dynarecLookup(&g_dyn, 0, 0x010A) != null, true);

    resetRom();
    g_bus.io[0x40] = 0x81;
    g_bus.io[0x41] = 0x80;
    g_bus.io[0x44] = 0;
    g_bus.lyc_dirty = false;
    g_ppu.lcdc = 0x81;
    g_ppu.dot = 100;
    g_ppu.line = 0;
    g_ppu.ly = 0;
    g_ppu.mode = 2;
    g_cpu.pc = 0x0100;
    g_cpu.sp = 0xFFFE;
    g_cpu.h = 0xFF;
    g_cpu.l = 0x40;
    g_cpu.a = 0;
    const chain0: u32 = g_dyn.stats.chained;
    _ = runDyn();
    checkBool("dynarec ppu ordering chained", g_dyn.stats.chained > chain0, true);
    checkU16("dynarec ppu ordering pc", g_cpu.pc, 0x0112);
    checkU32("dynarec ppu ordering disabled", @intCast(u32, g_ppu.lcdc), 0x01);
    checkU32("dynarec ppu ordering enable pending", @intCast(u32, g_bus.io[0x40]), 0x81);
}

fn testDynarecPpuAdvancedDots() void {
    resetRom();
    romClear();
    romWrite(0x0100, 0x3E);
    romWrite(0x0101, 0x12);
    romWrite(0x0102, 0xE0);
    romWrite(0x0103, 0x02);
    g_cpu.pc = 0x0100;
    g_cpu.a = 0;
    dynarecmod.dynarecFlush(&g_dyn);
    const cyc: u32 = runDyn();
    const adv: u32 = dynarecmod.dynarecPpuAdvancedDots();
    const dot_delta: u32 = cyc;
    const remainder: u32 = if (dot_delta > adv) dot_delta - adv else 0;
    checkU32("dynarec ppu dots cycles", cyc, 20);
    checkU32("dynarec ppu dots advanced", adv, 8);
    checkU32("dynarec ppu dots remainder", remainder, 12);
    checkBool("dynarec ppu dots no overadvance", adv <= dot_delta, true);
    checkU32("dynarec ppu dots sum", adv + remainder, dot_delta);

    resetRom();
    romClear();
    romWrite(0x0100, 0x3E);
    romWrite(0x0101, 0x12);
    romWrite(0x0102, 0xE0);
    romWrite(0x0103, 0x02);
    g_cpu.pc = 0x0100;
    g_cpu.a = 0;
    g_bus.double_speed = true;
    dynarecmod.dynarecFlush(&g_dyn);
    const cyc2: u32 = runDyn();
    const adv2: u32 = dynarecmod.dynarecPpuAdvancedDots();
    const dot_delta2: u32 = cyc2 / 2;
    const remainder2: u32 = if (dot_delta2 > adv2) dot_delta2 - adv2 else 0;
    checkU32("dynarec ppu dots double cycles", cyc2, 20);
    checkU32("dynarec ppu dots double advanced", adv2, 4);
    checkU32("dynarec ppu dots double remainder", remainder2, 6);
    checkBool("dynarec ppu dots double no overadvance", adv2 <= dot_delta2, true);
    checkU32("dynarec ppu dots double sum", adv2 + remainder2, dot_delta2);
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
    testCbWriteBoundaries();
    testPpuReadBoundaries();
    testAluRegisterMatrix();
    testAluImmediate();
    testLdRr();
    testLdRn();
    testLdPair();
    testIncDecByte();
    testIncDecPair();
    testAddHl();
    testIndirect();
    testLdh();
    testLdA16();
    testLdA16Sp();
    testLdC();
    testEmitterRejects();
    testEmitMultiInsn();
    testEmitJumps();
    testEmitCallRet();
    testEmitPushPop();
    testEmitCb();
    testHelpers();
    testCacheMapping();
    testHelperHeavyBlockTranslates();
    testEmitBufferOverflowRejected();
    testNormalBlockTranslates();
    testDynarecPpuAdvancedDots();
    testDynarecPpuOrdering();
    testCacheDistinctAndBank();
    testCacheReset();
    testCacheTrampoline();
    testCacheHotLoop();
    testCacheCallRet();
    testCachePendingInterruptChain();
    testCacheRomBounds();
    testCacheRomxChainAndMismatch();
    testCacheSamePcDifferentBank();
    testCacheCollision();
    testDynarecCoverage();
    testDynarecCoverageChain();
    testDynarecCounterWrapping();
    testDynarecEmuMinstr();
    testCacheClose();
    testDynarecFrameParity();
    testDynarecReinitClose();
    testDynarecDispatchFallbacks();
    releaseCode();

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
