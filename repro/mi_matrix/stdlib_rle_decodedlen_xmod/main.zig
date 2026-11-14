// stdlib_rle_decodedlen_xmod — std_rle (L4) `decodedLen` GREEN fixture.
//
// Contract (blueprint §3 L4 + §1 R1): `decodedLen(src) usize` returns the
// decoded length carried by a length-prefixed stream and allocates nothing.
// The prefix is the first 4 bytes, little-endian u32. A stream shorter than the
// prefix returns 0.
//
// Cases pinned: the prefix value for hand-built streams (0, 5, 0x1234, 0x0100);
// a stream shorter than 4 bytes (0); and for every round-tripped source
// `decodedLen(encode(src)) == src.len`.
//
// GREEN (contract): deterministic byte-exact stdout `rle decodedLen ok\n`
// (RUNRC=0).
const std = @import("std");
const rle = @import("std_rle.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn ckDecoded(src: []const u8, want: usize, what: []const u8) void {
    ck(rle.decodedLen(src) == want, what);
}

fn fillConst(dst: []u8, v: u8) void {
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        dst[i] = v;
    }
}

pub fn main() void {
    var backing: [65536]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    // hand-built prefixes
    var s0 = [_]u8{ 0, 0, 0, 0 };
    ckDecoded(s0[0..], 0, "decodedLen zero");

    var s1 = [_]u8{ 5, 0, 0, 0, 'A', 'B', 'C', 'D', 'E' };
    ckDecoded(s1[0..], 5, "decodedLen five");

    var s2 = [_]u8{ 0x34, 0x12, 0, 0 };
    ckDecoded(s2[0..], 0x1234, "decodedLen 0x1234");

    var s3 = [_]u8{ 0x00, 0x01, 0, 0 };
    ckDecoded(s3[0..], 256, "decodedLen 256");

    // shorter than the 4-byte prefix
    var s4 = [_]u8{ 0x34, 0x12, 0x00 };
    ckDecoded(s4[0..], 0, "decodedLen short");
    ckDecoded(s4[0..0], 0, "decodedLen empty src");

    // decodedLen(encode(src)) == src.len for several shapes
    var c1: [200]u8 = undefined;
    fillConst(c1[0..], 0x7A);
    var e1 = rle.encode(&ar, c1[0..]) catch {
        @panic("decodedLen const encode");
    };
    ckDecoded(e1, 200, "decodedLen const roundtrip");

    var a1: [201]u8 = undefined;
    var i: usize = 0;
    while (i < a1.len) : (i += 1) {
        if (i % 2 == 0) a1[i] = 0xAA else a1[i] = 0x55;
    }
    var e2 = rle.encode(&ar, a1[0..]) catch {
        @panic("decodedLen alt encode");
    };
    ckDecoded(e2, 201, "decodedLen alt roundtrip");

    var r1: [500]u8 = undefined;
    var st: u32 = 0xDEADBEEF;
    i = 0;
    while (i < r1.len) : (i += 1) {
        st = st *% 1103515245 +% 12345;
        r1[i] = @intCast(u8, (st >> 16) & 0xFF);
    }
    var e3 = rle.encode(&ar, r1[0..]) catch {
        @panic("decodedLen rnd encode");
    };
    ckDecoded(e3, 500, "decodedLen rnd roundtrip");

    var e4: [1]u8 = undefined;
    var e4enc = rle.encode(&ar, e4[0..0]) catch {
        @panic("decodedLen empty encode");
    };
    ckDecoded(e4enc, 0, "decodedLen empty roundtrip");

    if (g_fail == 0) {
        std.io.write("rle decodedLen ok\n");
    } else {
        std.io.write("rle decodedLen FAIL\n");
    }
}
