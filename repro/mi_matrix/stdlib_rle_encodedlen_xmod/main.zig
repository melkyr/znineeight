// stdlib_rle_encodedlen_xmod — std_rle (L4) `encodedLen` GREEN fixture.
//
// Contract (blueprint §3 L4 + §1 R1): `encodedLen(src) usize` returns the exact
// encoded size (4-byte prefix + tokens) and allocates nothing.
//
// Wire format (pinned by stdlib_rle_encode_xmod): literal = 1 byte; run token =
// 2 bytes per 128-byte chunk; a maximal run of 1 with value < 0x80 is a literal.
//
// Cases pinned: exact sizes for empty (4), single literal (5), single high-bit
// value (6), run of 3 (6), 4 alternating literals (8), 128-run (6), 129-run (8),
// 130-run (8), mixed AAABBB (8); and for every case `encodedLen(src)` equals the
// byte length of `encode(src)`, including a 300-byte pseudo-random buffer.
//
// GREEN (contract): deterministic byte-exact stdout `rle encodedLen ok\n`
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

fn ckLen(ar: *std.arena.Arena, src: []const u8, want: usize, what: []const u8) void {
    ck(rle.encodedLen(src) == want, what);
    var got = rle.encode(ar, src) catch {
        @panic(what);
    };
    ck(got.len == want, what);
    ck(got.len == rle.encodedLen(src), what);
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

    var e0: [1]u8 = undefined;
    ckLen(&ar, e0[0..0], 4, "len empty");

    var s1 = [_]u8{'A'};
    ckLen(&ar, s1[0..], 5, "len single literal");

    var s2 = [_]u8{0x80};
    ckLen(&ar, s2[0..], 6, "len single high");

    var s3 = [_]u8{ 0x7A, 0x7A, 0x7A };
    ckLen(&ar, s3[0..], 6, "len run3");

    var s4 = [_]u8{ 'A', 'B', 'A', 'B' };
    ckLen(&ar, s4[0..], 8, "len alternating");

    var s5: [128]u8 = undefined;
    fillConst(s5[0..], 0x41);
    ckLen(&ar, s5[0..], 6, "len run128");

    var s6: [129]u8 = undefined;
    fillConst(s6[0..], 0x41);
    ckLen(&ar, s6[0..], 8, "len run129");

    var s7: [130]u8 = undefined;
    fillConst(s7[0..], 0x00);
    ckLen(&ar, s7[0..], 8, "len run130");

    var s8 = [_]u8{ 'A', 'A', 'A', 'B', 'B', 'B' };
    ckLen(&ar, s8[0..], 8, "len mixed");

    // 300 pseudo-random bytes: encodedLen must equal the encode output length.
    var rnd: [300]u8 = undefined;
    var st: u32 = 0x1234ABCD;
    var i: usize = 0;
    while (i < rnd.len) : (i += 1) {
        st = st *% 1664525 +% 1013904223;
        rnd[i] = @intCast(u8, (st >> 24) & 0xFF);
    }
    var enc = rle.encode(&ar, rnd[0..]) catch {
        @panic("len random encode");
    };
    ck(rle.encodedLen(rnd[0..]) == enc.len, "len random cross-check");

    if (g_fail == 0) {
        std.io.write("rle encodedLen ok\n");
    } else {
        std.io.write("rle encodedLen FAIL\n");
    }
}
