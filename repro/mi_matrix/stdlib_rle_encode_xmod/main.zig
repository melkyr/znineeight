// stdlib_rle_encode_xmod — std_rle (L4) `encode` GREEN fixture.
//
// Contract (blueprint §3 L4 + §1 R1): `encode(arena, src) ![]u8` allocates the
// output from the caller's arena; the error set is exactly `error.OutOfMemory`.
//
// Wire format pinned here (deterministic, R6): a 4-byte little-endian u32
// decoded-length prefix, then tokens. A literal is one byte b < 0x80. A run is
// a control byte `0x80 | (n - 1)` (1 <= n <= 128) followed by the value byte.
// A maximal run of n equal bytes is a literal when n == 1 and value < 0x80,
// otherwise one or more run tokens of at most 128 bytes each.
//
// Cases pinned: empty; single literal; single high-bit value (forced run of 1);
// constant run of 3; alternating bytes (all literals); 128-run (single token);
// 129-run (two tokens, the second a run of 1); 130-run; mixed runs; high-bit
// constant run. Each case compares the exact encoded bytes.
//
// GREEN (contract): deterministic byte-exact stdout `rle encode ok\n` (RUNRC=0).
const std = @import("std");
const rle = @import("std_rle.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn ckBytes(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

fn enc(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    var got = rle.encode(ar, src) catch {
        @panic(what);
    };
    ckBytes(got, want, what);
}

fn fillConst(dst: []u8, v: u8) void {
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        dst[i] = v;
    }
}

pub fn main() void {
    var backing: [8192]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    // empty
    var e0: [1]u8 = undefined;
    var w0 = [_]u8{ 0, 0, 0, 0 };
    enc(&ar, e0[0..0], w0[0..], "enc empty");

    // single literal (< 0x80)
    var s1 = [_]u8{'A'};
    var w1 = [_]u8{ 1, 0, 0, 0, 0x41 };
    enc(&ar, s1[0..], w1[0..], "enc single literal");

    // single high-bit value (0x80) -> forced run of 1
    var s2 = [_]u8{0x80};
    var w2 = [_]u8{ 1, 0, 0, 0, 0x80, 0x80 };
    enc(&ar, s2[0..], w2[0..], "enc single high");

    // constant run of 3 x 0x7A
    var s3 = [_]u8{ 0x7A, 0x7A, 0x7A };
    var w3 = [_]u8{ 3, 0, 0, 0, 0x82, 0x7A };
    enc(&ar, s3[0..], w3[0..], "enc run3");

    // alternating bytes -> all literals
    var s4 = [_]u8{ 'A', 'B', 'A', 'B' };
    var w4 = [_]u8{ 4, 0, 0, 0, 'A', 'B', 'A', 'B' };
    enc(&ar, s4[0..], w4[0..], "enc alternating");

    // exactly 128 equal bytes -> one run token
    var s5: [128]u8 = undefined;
    fillConst(s5[0..], 0x41);
    var w5 = [_]u8{ 0x80, 0, 0, 0, 0xFF, 0x41 };
    enc(&ar, s5[0..], w5[0..], "enc run128");

    // 129 equal bytes -> 0xFF + 0x80 (a run token of length 1)
    var s6: [129]u8 = undefined;
    fillConst(s6[0..], 0x41);
    var w6 = [_]u8{ 0x81, 0, 0, 0, 0xFF, 0x41, 0x80, 0x41 };
    enc(&ar, s6[0..], w6[0..], "enc run129");

    // 130 zero bytes -> 0xFF/0x00 + 0x81/0x00
    var s7: [130]u8 = undefined;
    fillConst(s7[0..], 0x00);
    var w7 = [_]u8{ 0x82, 0, 0, 0, 0xFF, 0x00, 0x81, 0x00 };
    enc(&ar, s7[0..], w7[0..], "enc run130");

    // mixed runs AAABBB
    var s8 = [_]u8{ 'A', 'A', 'A', 'B', 'B', 'B' };
    var w8 = [_]u8{ 6, 0, 0, 0, 0x82, 'A', 0x82, 'B' };
    enc(&ar, s8[0..], w8[0..], "enc mixed");

    // high-bit constant run of 3 x 0xFF
    var s9 = [_]u8{ 0xFF, 0xFF, 0xFF };
    var w9 = [_]u8{ 3, 0, 0, 0, 0x82, 0xFF };
    enc(&ar, s9[0..], w9[0..], "enc high run");

    if (g_fail == 0) {
        std.io.write("rle encode ok\n");
    } else {
        std.io.write("rle encode FAIL\n");
    }
}
