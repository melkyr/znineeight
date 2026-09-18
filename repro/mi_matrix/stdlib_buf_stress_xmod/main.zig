// stdlib_buf_stress_xmod — STDLIB std_buf (L2) hand-written stress table.
//
// No PRNG: every input is an explicit table. Stresses:
//   - many appends across many doublings: 1000 appendByte calls drive the
//     capacity through every doubling 1..1024; the content pattern and the
//     exact final capacity are asserted.
//   - a single append of a 600-byte written pattern (one reserve that doubles
//     0 -> 1024).
//   - every encoder (appendU16/32/64BE/LE) round-tripped by a byte-wise decode
//     over a written value table; the total byte length is pinned.
//   - the arena max-size boundary: an exact-fit buffer filled to capacity, then
//     appendByte and reserve both fail with OutOfMemory and leave the length
//     unchanged.
//
// GREEN (contract): deterministic byte-exact stdout `buf stress ok\n` (RUNRC=0).
const std = @import("std");
const buf = @import("std_buf.zig");

const ALL32: u32 = ~@intCast(u32, 0);
const ALL64: u64 = ~@intCast(u64, 0);

var g_back_a: [8192]u8 = undefined;
var g_arena_a = std.arena.init(g_back_a[0..]);
var g_back_b: [4096]u8 = undefined;
var g_arena_b = std.arena.init(g_back_b[0..]);
var g_back_c: [64]u8 = undefined;
var g_arena_c = std.arena.init(g_back_c[0..]);
var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn decU16BE(s: []const u8, o: usize) u16 {
    return (@intCast(u16, s[o]) << 8) | @intCast(u16, s[o + 1]);
}

fn decU16LE(s: []const u8, o: usize) u16 {
    return @intCast(u16, s[o]) | (@intCast(u16, s[o + 1]) << 8);
}

fn decU32BE(s: []const u8, o: usize) u32 {
    var v: u32 = @intCast(u32, s[o]);
    v = (v << 8) | @intCast(u32, s[o + 1]);
    v = (v << 8) | @intCast(u32, s[o + 2]);
    v = (v << 8) | @intCast(u32, s[o + 3]);
    return v;
}

fn decU32LE(s: []const u8, o: usize) u32 {
    var v: u32 = @intCast(u32, s[o + 3]);
    v = (v << 8) | @intCast(u32, s[o + 2]);
    v = (v << 8) | @intCast(u32, s[o + 1]);
    v = (v << 8) | @intCast(u32, s[o]);
    return v;
}

fn decU64BE(s: []const u8, o: usize) u64 {
    var v: u64 = @intCast(u64, s[o]);
    v = (v << 8) | @intCast(u64, s[o + 1]);
    v = (v << 8) | @intCast(u64, s[o + 2]);
    v = (v << 8) | @intCast(u64, s[o + 3]);
    v = (v << 8) | @intCast(u64, s[o + 4]);
    v = (v << 8) | @intCast(u64, s[o + 5]);
    v = (v << 8) | @intCast(u64, s[o + 6]);
    v = (v << 8) | @intCast(u64, s[o + 7]);
    return v;
}

fn decU64LE(s: []const u8, o: usize) u64 {
    var v: u64 = @intCast(u64, s[o + 7]);
    v = (v << 8) | @intCast(u64, s[o + 6]);
    v = (v << 8) | @intCast(u64, s[o + 5]);
    v = (v << 8) | @intCast(u64, s[o + 4]);
    v = (v << 8) | @intCast(u64, s[o + 3]);
    v = (v << 8) | @intCast(u64, s[o + 2]);
    v = (v << 8) | @intCast(u64, s[o + 1]);
    v = (v << 8) | @intCast(u64, s[o]);
    return v;
}

fn runByteDoublings() void {
    var b = std.buf.init(&g_arena_a);
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        std.buf.appendByte(&b, @intCast(u8, i % 251)) catch {
            g_fail += 1;
        };
    }
    ck(std.buf.slice(&b).len == 1000, "byte-append length");
    ck(std.buf.capacity(&b) == 1024, "capacity 1024 after doublings");
    var s = std.buf.slice(&b);
    i = 0;
    while (i < 1000) : (i += 1) {
        ck(s[i] == @intCast(u8, i % 251), "byte-append content");
    }

    var chunk: [600]u8 = undefined;
    var ci: usize = 0;
    while (ci < 600) : (ci += 1) {
        chunk[ci] = @intCast(u8, (ci * 7) % 256);
    }
    var b2 = std.buf.init(&g_arena_a);
    std.buf.append(&b2, chunk[0..]) catch {
        g_fail += 1;
    };
    ck(std.buf.capacity(&b2) == 1024, "single append doubling");
    ck(std.buf.slice(&b2).len == 600, "single append length");
    var s2 = std.buf.slice(&b2);
    ci = 0;
    while (ci < 600) : (ci += 1) {
        ck(s2[ci] == @intCast(u8, (ci * 7) % 256), "single append content");
    }
}

fn runEncoderRoundtrips() void {
    var eb = std.buf.init(&g_arena_b);
    var v16 = [_]u16{
        0, 1, @intCast(u16, 0x1234), @intCast(u16, 0xFFFF),
        @intCast(u16, 0x00FF), @intCast(u16, 0xFF00),
    };
    var o: usize = 0;
    var i: usize = 0;
    while (i < v16.len) : (i += 1) {
        std.buf.appendU16BE(&eb, v16[i]) catch {
            g_fail += 1;
        };
        std.buf.appendU16LE(&eb, v16[i]) catch {
            g_fail += 1;
        };
        var s = std.buf.slice(&eb);
        ck(decU16BE(s, o) == v16[i], "u16be roundtrip");
        ck(decU16LE(s, o + 2) == v16[i], "u16le roundtrip");
        o += 4;
    }

    var v32 = [_]u32{
        0, 1, @intCast(u32, 0x12345678), ALL32,
        @intCast(u32, 0x00FF00FF), @intCast(u32, 0xDEADBEEF),
    };
    i = 0;
    while (i < v32.len) : (i += 1) {
        std.buf.appendU32BE(&eb, v32[i]) catch {
            g_fail += 1;
        };
        std.buf.appendU32LE(&eb, v32[i]) catch {
            g_fail += 1;
        };
        var s = std.buf.slice(&eb);
        ck(decU32BE(s, o) == v32[i], "u32be roundtrip");
        ck(decU32LE(s, o + 4) == v32[i], "u32le roundtrip");
        o += 8;
    }

    var v64 = [_]u64{
        0, 1, @intCast(u64, 0x0102030405060708), ALL64,
        @intCast(u64, 0x00000000FFFFFFFF), @intCast(u64, 0xFFFFFFFF00000000),
    };
    i = 0;
    while (i < v64.len) : (i += 1) {
        std.buf.appendU64BE(&eb, v64[i]) catch {
            g_fail += 1;
        };
        std.buf.appendU64LE(&eb, v64[i]) catch {
            g_fail += 1;
        };
        var s = std.buf.slice(&eb);
        ck(decU64BE(s, o) == v64[i], "u64be roundtrip");
        ck(decU64LE(s, o + 8) == v64[i], "u64le roundtrip");
        o += 16;
    }

    ck(o == 168, "encoder total length");
}

fn runArenaMaxBoundary() void {
    var fb = std.buf.initCapacity(&g_arena_c, 64) catch {
        g_fail += 1;
        return;
    };
    ck(std.buf.capacity(&fb) == 64, "initCapacity 64");
    var k: usize = 0;
    while (k < 64) : (k += 1) {
        std.buf.appendByte(&fb, @intCast(u8, k)) catch {
            g_fail += 1;
        };
    }
    ck(std.buf.capacity(&fb) == 64, "exact-fit capacity unchanged");
    ck(std.buf.slice(&fb).len == 64, "exact-fit length");
    var oom = false;
    std.buf.appendByte(&fb, @intCast(u8, 0xEE)) catch {
        oom = true;
    };
    ck(oom, "appendByte OutOfMemory at arena max");
    ck(std.buf.slice(&fb).len == 64, "length unchanged after OOM");
    var oom2 = false;
    std.buf.reserve(&fb, 1) catch {
        oom2 = true;
    };
    ck(oom2, "reserve OutOfMemory at arena max");
}

pub fn main() void {
    runByteDoublings();
    runEncoderRoundtrips();
    runArenaMaxBoundary();

    if (g_fail == 0) {
        std.io.write("buf stress ok\n");
    } else {
        std.io.write("buf stress FAIL\n");
    }
}
