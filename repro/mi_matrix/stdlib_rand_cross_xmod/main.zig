// stdlib_rand_cross_xmod — std_rand (L5) crosscheck driver.
//
// Default mode (fixture gate): deterministic `rand cross ok\n`.
// `--crosscheck` reads `seed stream count` per line (decimal u64, u64, u32)
// and prints two lines per input: `count` space-separated lowercase hex u32
// PCG32 outputs, then `count` space-separated 16-digit lowercase hex
// xoshiro256** outputs. A `bounded seed stream bound count` line (decimal
// u64, u64, u32, u32) instead prints one line of `count` lowercase hex u32
// `pcg32Bounded` outputs. The C89 reference at
// scripts/stdlib/ref/std_rand/ref.c implements the same protocol.
const std = @import("std");
const os = @import("std_os.zig");
const stdin = @import("std_stdin.zig");
const parse = @import("std_parse.zig");
const rand = @import("std_rand.zig");

fn sliceEq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn isCrosscheck() bool {
    var i: usize = 1;
    while (i < os.argc()) : (i += 1) {
        if (sliceEq(os.argv(i), "--crosscheck")) return true;
    }
    return false;
}

fn isWs(c: u8) bool {
    return c == ' ' or c == '\t';
}

fn hexChar(v: u64) u8 {
    if (v < 10) return @intCast(u8, @intCast(u32, '0') + @intCast(u32, v));
    return @intCast(u8, @intCast(u32, 'a') + @intCast(u32, v - 10));
}

fn writeHexU32(v: u32) void {
    if (v == 0) {
        std.io.write("0");
        return;
    }
    var tmp: [8]u8 = undefined;
    var n: usize = 0;
    var x: u32 = v;
    while (x > 0) {
        tmp[n] = hexChar(@intCast(u64, x & 15));
        n += 1;
        x = x >> 4;
    }
    var buf: [8]u8 = undefined;
    var pos: usize = 0;
    while (n > 0) {
        n -= 1;
        buf[pos] = tmp[n];
        pos += 1;
    }
    std.io.write(buf[0..pos]);
}

fn writeHexPadded(v: u64, digits: usize) void {
    var buf: [16]u8 = undefined;
    var i: usize = 0;
    while (i < digits) : (i += 1) {
        var sh: u64 = @intCast(u64, (digits - 1 - i) * 4);
        buf[i] = hexChar((v >> sh) & 15);
    }
    std.io.write(buf[0..digits]);
}

fn nextToken(line: []const u8, pos: *usize) ?[]const u8 {
    var i: usize = pos.*;
    while (i < line.len and isWs(line[i])) : (i += 1) {}
    if (i >= line.len) {
        pos.* = i;
        return null;
    }
    var j: usize = i;
    while (j < line.len and !isWs(line[j])) : (j += 1) {}
    pos.* = j;
    return line[i..j];
}

fn crossMain() void {
    var buf: [512]u8 = undefined;
    while (true) {
        const line_opt = stdin.readLine(buf[0..]) catch @panic("crosscheck read");
        if (line_opt) |line| {
            var pos: usize = 0;
            const first = nextToken(line[0..], &pos) orelse @panic("crosscheck empty line");
            if (sliceEq(first, "bounded")) {
                const seed_s = nextToken(line[0..], &pos) orelse @panic("crosscheck seed");
                const stream_s = nextToken(line[0..], &pos) orelse @panic("crosscheck stream");
                const bound_s = nextToken(line[0..], &pos) orelse @panic("crosscheck bound");
                const count_s = nextToken(line[0..], &pos) orelse @panic("crosscheck count");
                const seed = parse.parseUint64(seed_s) orelse @panic("crosscheck seed");
                const stream = parse.parseUint64(stream_s) orelse @panic("crosscheck stream");
                const bound = parse.parseUint(bound_s) orelse @panic("crosscheck bound");
                const count = parse.parseUint(count_s) orelse @panic("crosscheck count");

                var bp = rand.pcg32Init(seed, stream);
                var bz: u32 = 0;
                while (bz < count) : (bz += 1) {
                    if (bz != 0) std.io.write(" ");
                    writeHexU32(rand.pcg32Bounded(&bp, bound));
                }
                std.io.write("\n");
            } else {
                const stream_s = nextToken(line[0..], &pos) orelse @panic("crosscheck stream");
                const count_s = nextToken(line[0..], &pos) orelse @panic("crosscheck count");
                const seed = parse.parseUint64(first) orelse @panic("crosscheck seed");
                const stream = parse.parseUint64(stream_s) orelse @panic("crosscheck stream");
                const count = parse.parseUint(count_s) orelse @panic("crosscheck count");

                var p = rand.pcg32Init(seed, stream);
                var z: u32 = 0;
                while (z < count) : (z += 1) {
                    if (z != 0) std.io.write(" ");
                    writeHexU32(rand.pcg32Next(&p));
                }
                std.io.write("\n");

                var x = rand.xoshiroInit(seed);
                z = 0;
                while (z < count) : (z += 1) {
                    if (z != 0) std.io.write(" ");
                    writeHexPadded(rand.xoshiroNext(&x), 16);
                }
                std.io.write("\n");
            }
        } else {
            break;
        }
    }
}

pub fn main(argc: i32, argv: [*]*const u8) void {
    os.initArgs(argc, argv);
    if (isCrosscheck()) {
        crossMain();
    } else {
        std.io.write("rand cross ok\n");
    }
}
