// apu_test.zig — DMG APU register, channel, quirk, mixer, and ring tests.
//
// Run as a normal executable under both -ffast and -fsafe. Every check is
// counted; the process exits 0 only when all checks pass.

const std = @import("std");
const apumod = @import("../apu.zig");

var g_apu: apumod.Apu = undefined;
var g_pass: u32 = 0;
var g_fail: u32 = 0;
var g_out: [4096]i16 = undefined;

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

fn checkWord(label: []const u8, got: u16, want: u16) void {
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

fn checkBool(label: []const u8, got: bool, want: bool) void {
    checkByte(label, if (got) 1 else 0, if (want) 1 else 0);
}

fn reset() void {
    apumod.apuReset(&g_apu, 44100);
    apumod.apuWrite(&g_apu, 0xFF26, 0x80);
}

fn wr(addr: u16, value: u8) void {
    apumod.apuWrite(&g_apu, addr, value);
}

fn rd(addr: u16) u8 {
    return apumod.apuRead(&g_apu, addr);
}

fn testRegisterMasks() void {
    reset();
    wr(0xFF10, 0x00);
    checkByte("NR10 mask", rd(0xFF10), 0x80);
    wr(0xFF11, 0x00);
    checkByte("NR11 mask", rd(0xFF11), 0x3F);
    wr(0xFF12, 0x00);
    checkByte("NR12 mask", rd(0xFF12), 0x00);
    checkByte("NR13 write-only", rd(0xFF13), 0xFF);
    wr(0xFF14, 0x00);
    checkByte("NR14 mask", rd(0xFF14), 0xBF);
    checkByte("NR15 unused", rd(0xFF15), 0xFF);
    wr(0xFF16, 0x00);
    checkByte("NR21 mask", rd(0xFF16), 0x3F);
    wr(0xFF1A, 0x00);
    checkByte("NR30 mask", rd(0xFF1A), 0x7F);
    wr(0xFF1C, 0x00);
    checkByte("NR32 mask", rd(0xFF1C), 0x9F);
    wr(0xFF20, 0x00);
    checkByte("NR41 write-only", rd(0xFF20), 0xFF);
    wr(0xFF23, 0x00);
    checkByte("NR44 mask", rd(0xFF23), 0xBF);
    wr(0xFF24, 0x00);
    checkByte("NR50 mask", rd(0xFF24), 0x00);
    wr(0xFF25, 0x00);
    checkByte("NR51 mask", rd(0xFF25), 0x00);
}

fn testPower() void {
    reset();
    wr(0xFF26, 0x00);
    checkByte("NR52 off reads 70", rd(0xFF26), 0x70);
    wr(0xFF26, 0xFF);
    checkByte("NR52 on reads F0", rd(0xFF26), 0xF0);

    wr(0xFF10, 0x12);
    wr(0xFF26, 0x00);
    checkByte("register cleared by power off", rd(0xFF10), 0x80);

    wr(0xFF20, 0x3E);
    checkWord("NR41 write while off", g_apu.ch4.length, 2);
    wr(0xFF26, 0x80);
    checkWord("length survives power on", g_apu.ch4.length, 2);
    checkByte("NR52 off status", rd(0xFF26), 0xF0);
}

fn testSquare() void {
    reset();
    wr(0xFF11, 0x80);
    wr(0xFF12, 0xF0);
    wr(0xFF13, 0x00);
    wr(0xFF14, 0x87);
    checkBool("ch1 enabled", g_apu.ch1.enabled, true);
    checkByte("ch1 duty decoded", g_apu.ch1.duty, 2);
    checkWord("ch1 frequency", g_apu.ch1.freq, 0x700);
    const before: u8 = g_apu.ch1.duty_pos;
    apumod.apuTick(&g_apu, 1024);
    checkByte("ch1 duty step at 1024 cycles", g_apu.ch1.duty_pos, @intCast(u8, (@as(u16, before) + 1) & 7));

    wr(0xFF16, 0x40);
    wr(0xFF17, 0xF0);
    wr(0xFF18, 0x11);
    wr(0xFF19, 0x86);
    checkBool("ch2 enabled", g_apu.ch2.enabled, true);
    checkByte("ch2 duty decoded", g_apu.ch2.duty, 1);
    checkWord("ch2 frequency", g_apu.ch2.freq, 0x611);
}

fn testEnvelopeHold() void {
    reset();
    wr(0xFF11, 0x80);
    wr(0xFF12, 0x50);
    wr(0xFF13, 0x00);
    wr(0xFF14, 0x87);
    checkByte("envelope trigger volume", g_apu.ch1.vol, 5);
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        g_apu.fs_step = 7;
        g_apu.fs_cycles = 0;
        apumod.apuTick(&g_apu, 8192);
    }
    checkByte("envelope period 0 holds volume", g_apu.ch1.vol, 5);
}

fn testLengthClockQuirk() void {
    reset();
    wr(0xFF12, 0x08);
    wr(0xFF11, 0x3E);
    wr(0xFF14, 0x80);
    g_apu.fs_step = 1;
    g_apu.fs_cycles = 0;
    wr(0xFF14, 0x40);
    checkWord("extra length clock first half", g_apu.ch1.length, 1);

    wr(0xFF11, 0x3E);
    wr(0xFF14, 0x00);
    g_apu.fs_step = 2;
    g_apu.fs_cycles = 0;
    wr(0xFF14, 0x40);
    checkWord("no extra length clock second half", g_apu.ch1.length, 2);

    wr(0xFF11, 0x3E);
    wr(0xFF14, 0x00);
    g_apu.fs_step = 1;
    g_apu.fs_cycles = 0;
    wr(0xFF14, 0x40);
    wr(0xFF14, 0x40);
    checkWord("enabled-to-enabled does not clock", g_apu.ch1.length, 1);
}

fn testSweepQuirks() void {
    reset();
    wr(0xFF12, 0x08);
    wr(0xFF10, 0x09);
    wr(0xFF13, 0x00);
    wr(0xFF14, 0xC0);
    checkBool("sweep trigger calculation used negate", g_apu.sweep_negate_used, true);
    wr(0xFF10, 0x10);
    checkBool("negate-after-enable disables", g_apu.ch1.enabled, false);
    checkByte("NR52 ch1 off", @intCast(u8, rd(0xFF26) & 0x01), 0);

    reset();
    wr(0xFF12, 0x08);
    wr(0xFF10, 0x11);
    wr(0xFF13, 0x00);
    wr(0xFF14, 0xC5);
    checkWord("sweep shadow copies frequency", g_apu.sweep_shadow, 0x500);
    apumod.apuTick(&g_apu, 32768);
    checkWord("sweep updates frequency", g_apu.ch1.freq, 0x780);
}

fn testWaveRam() void {
    reset();
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        wr(@intCast(u16, 0xFF30 + i), @intCast(u8, i * 0x11));
    }
    i = 0;
    while (i < 16) : (i += 1) {
        checkByte("wave RAM readback", rd(@intCast(u16, 0xFF30 + i)), @intCast(u8, i * 0x11));
    }

    wr(0xFF30, 0x12);
    wr(0xFF26, 0x00);
    checkByte("wave RAM survives power off", rd(0xFF30), 0x12);
    wr(0xFF26, 0x80);

    wr(0xFF30, 0x37);
    wr(0xFF30 + 1, 0x48);
    wr(0xFF30, 0xAB);
    wr(0xFF1A, 0x80);
    wr(0xFF1C, 0x20);
    wr(0xFF1D, 0xFE);
    wr(0xFF1E, 0x87);
    g_apu.ch3.timer = 1;
    apumod.apuTick(&g_apu, 1);
    checkByte("wave read during fetch", rd(0xFF30), g_apu.wave_ram[0]);
    apumod.apuTick(&g_apu, 1);
    checkByte("wave read during playback garbage", rd(0xFF30), 0xFF);
}

fn testNoiseLfsr() void {
    reset();
    wr(0xFF21, 0x08);
    wr(0xFF22, 0x08);
    wr(0xFF23, 0x80);
    g_apu.ch4.lfsr = 0x7F7E;
    g_apu.ch4.timer = 1;
    apumod.apuTick(&g_apu, 1);
    checkWord("width-7 feedback into bit 6", g_apu.ch4.lfsr, 0x7FFF);

    g_apu.ch4.width7 = false;
    g_apu.ch4.lfsr = 0x7F7E;
    g_apu.ch4.timer = 1;
    apumod.apuTick(&g_apu, 1);
    checkWord("width-15 leaves bit 6 clear", g_apu.ch4.lfsr, 0x7FBF);
}

fn drainAll() i32 {
    var last: i32 = 0;
    while (true) {
        const n: usize = apumod.apuSamples(&g_apu, g_out[0..]);
        if (n == 0) break;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const v: i32 = @intCast(i32, g_out[i]);
            if (v < 0) last = -v else last = v;
        }
    }
    return last;
}

fn testMixer() void {
    reset();
    wr(0xFF26, 0x80);
    wr(0xFF24, 0x77);
    wr(0xFF25, 0xFF);
    var i: usize = 0;
    while (i < 16) : (i += 1) wr(@intCast(u16, 0xFF30 + i), 0x99);
    wr(0xFF1A, 0x80);
    wr(0xFF1C, 0x20);
    wr(0xFF1D, 0xFF);
    wr(0xFF1E, 0x87);
    apumod.apuTick(&g_apu, 20000);
    const first: usize = apumod.apuSamples(&g_apu, g_out[0..]);
    checkBool("mixer produced samples", first > 0, true);
    var first_amp: i32 = 0;
    if (first > 0) {
        first_amp = @intCast(i32, g_out[0]);
        if (first_amp < 0) first_amp = -first_amp;
    }
    checkBool("mixer initial signal nonzero", first_amp > 100, true);
    _ = drainAll();

    var k: usize = 0;
    while (k < 40) : (k += 1) {
        apumod.apuTick(&g_apu, 10000);
        _ = drainAll();
    }
    apumod.apuTick(&g_apu, 10000);
    const settled: i32 = drainAll();
    checkBool("mixer DC blocker settles", settled < 128, true);
}

fn testRingDrain() void {
    reset();
    _ = drainAll();
    apumod.apuTick(&g_apu, 1000);
    const produced: u32 = g_apu.ring_count;
    checkBool("ring produced samples", produced > 0, true);
    const got: usize = apumod.apuSamples(&g_apu, g_out[0..]);
    checkU32("apuSamples drains exact count", @intCast(u32, got), produced);
    checkU32("ring empty after drain", g_apu.ring_count, 0);
    checkU32("second drain returns zero", @intCast(u32, apumod.apuSamples(&g_apu, g_out[0..])), 0);
}

fn testBootDefaults() void {
    apumod.apuReset(&g_apu, 44100);
    checkByte("boot NR10", rd(0xFF10), 0x80);
    checkByte("boot NR11", rd(0xFF11), 0xBF);
    checkByte("boot NR12", rd(0xFF12), 0xF3);
    checkByte("boot NR13", rd(0xFF13), 0xFF);
    checkByte("boot NR14", rd(0xFF14), 0xBF);
    checkByte("boot NR16", rd(0xFF16), 0x3F);
    checkByte("boot NR17", rd(0xFF17), 0x00);
    checkByte("boot NR18", rd(0xFF18), 0xFF);
    checkByte("boot NR19", rd(0xFF19), 0xBF);
    checkByte("boot NR1A", rd(0xFF1A), 0x7F);
    checkByte("boot NR1B", rd(0xFF1B), 0xFF);
    checkByte("boot NR1C", rd(0xFF1C), 0x9F);
    checkByte("boot NR1D", rd(0xFF1D), 0xFF);
    checkByte("boot NR1E", rd(0xFF1E), 0xBF);
    checkByte("boot NR20", rd(0xFF20), 0xFF);
    checkByte("boot NR21", rd(0xFF21), 0x00);
    checkByte("boot NR22", rd(0xFF22), 0x00);
    checkByte("boot NR23", rd(0xFF23), 0xBF);
    checkByte("boot NR24", rd(0xFF24), 0x77);
    checkByte("boot NR25", rd(0xFF25), 0xF3);
    checkByte("boot NR26", rd(0xFF26), 0xF1);
    checkBool("boot channel 1 enabled", g_apu.ch1.enabled, true);
    checkByte("boot channel 1 duty", g_apu.ch1.duty, 2);
    checkWord("boot channel 1 length", g_apu.ch1.length, 64);
    checkByte("boot channel 1 volume", g_apu.ch1.vol, 15);
    checkByte("boot NR50 raw", g_apu.nr50, 0x77);
    checkByte("boot NR51 raw", g_apu.nr51, 0xF3);
}

fn testOffStateRaw() void {
    apumod.apuReset(&g_apu, 44100);
    wr(0xFF11, 0x05);
    wr(0xFF16, 0x45);
    wr(0xFF1B, 0x5A);
    wr(0xFF20, 0x33);
    wr(0xFF26, 0x00);
    checkByte("off NR11 keeps raw", rd(0xFF11), 0x3F);
    checkByte("off NR21 keeps raw", rd(0xFF16), 0x7F);
    checkByte("off NR31 mask", rd(0xFF1B), 0xFF);
    checkByte("off NR41 mask", rd(0xFF20), 0xFF);
}

fn testNonSilentRing() void {
    apumod.apuReset(&g_apu, 44100);
    _ = drainAll();
    wr(0xFF24, 0x77);
    wr(0xFF25, 0x11);
    wr(0xFF11, 0x80);
    wr(0xFF12, 0xF0);
    wr(0xFF13, 0x00);
    wr(0xFF14, 0x87);
    checkBool("non-silent ch1 enabled", g_apu.ch1.enabled, true);
    apumod.apuTick(&g_apu, 8192);
    const got: usize = apumod.apuSamples(&g_apu, g_out[0..]);
    checkBool("non-silent ring produced", got > 0, true);
    var nonzero: bool = false;
    var i: usize = 0;
    while (i < got) : (i += 1) {
        if (g_out[i] != 0) nonzero = true;
    }
    checkBool("non-silent sample nonzero", nonzero, true);
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;
    testRegisterMasks();
    testPower();
    testSquare();
    testEnvelopeHold();
    testLengthClockQuirk();
    testSweepQuirks();
    testWaveRam();
    testNoiseLfsr();
    testMixer();
    testRingDrain();
    testBootDefaults();
    testOffStateRaw();
    testNonSilentRing();

    if (g_fail == 0) {
        std.io.write("apu ok ");
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
