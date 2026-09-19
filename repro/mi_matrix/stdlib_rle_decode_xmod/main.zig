// stdlib_rle_decode_xmod — std_rle (L4) `decode` GREEN fixture.
//
// Contract (blueprint §3 L4 + §1 R1): `decode(arena, src) ![]u8` allocates the
// output (the prefix value) from the caller's arena; the error set is exactly
// `error.OutOfMemory`.
//
// Wire format (pinned by stdlib_rle_encode_xmod): 4-byte little-endian u32
// decoded-length prefix, then literal bytes (< 0x80) and run tokens
// `0x80 | (n - 1)` (1 <= n <= 128) followed by the value byte.
//
// Cases pinned: all-literal stream; single run; run of 1 high value; a 130-byte
// chunked run; mixed runs; empty stream; trailing bytes after the declared
// length are ignored; an overlong run is clamped to the declared length; a
// stream shorter than the 4-byte prefix decodes to empty.
//
// GREEN (contract): deterministic byte-exact stdout `rle decode ok\n` (RUNRC=0).
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

fn dec(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    var got = rle.decode(ar, src) catch {
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

    // all-literal stream
    var s0 = [_]u8{ 3, 0, 0, 0, 'A', 'B', 'C' };
    var w0 = [_]u8{ 'A', 'B', 'C' };
    dec(&ar, s0[0..], w0[0..], "dec literals");

    // single run of 3
    var s1 = [_]u8{ 3, 0, 0, 0, 0x82, 0x7A };
    var w1 = [_]u8{ 0x7A, 0x7A, 0x7A };
    dec(&ar, s1[0..], w1[0..], "dec run3");

    // run of 1 high value
    var s2 = [_]u8{ 1, 0, 0, 0, 0x80, 0x80 };
    var w2 = [_]u8{0x80};
    dec(&ar, s2[0..], w2[0..], "dec run1 high");

    // 130-byte chunked run
    var s3 = [_]u8{ 130, 0, 0, 0, 0xFF, 0x00, 0x81, 0x00 };
    var w3: [130]u8 = undefined;
    fillConst(w3[0..], 0x00);
    dec(&ar, s3[0..], w3[0..], "dec run130");

    // mixed runs AAABBB
    var s4 = [_]u8{ 6, 0, 0, 0, 0x82, 'A', 0x82, 'B' };
    var w4 = [_]u8{ 'A', 'A', 'A', 'B', 'B', 'B' };
    dec(&ar, s4[0..], w4[0..], "dec mixed");

    // empty stream
    var s5 = [_]u8{ 0, 0, 0, 0 };
    var w5 = [_]u8{0};
    dec(&ar, s5[0..], w5[0..0], "dec empty");

    // trailing bytes after the declared length are ignored
    var s6 = [_]u8{ 2, 0, 0, 0, 'X', 'Y', 'Z' };
    var w6 = [_]u8{ 'X', 'Y' };
    dec(&ar, s6[0..], w6[0..], "dec trailing");

    // overlong run clamped to the declared length
    var s7 = [_]u8{ 2, 0, 0, 0, 0x82, 'Q' };
    var w7 = [_]u8{ 'Q', 'Q' };
    dec(&ar, s7[0..], w7[0..], "dec clamp");

    // shorter than the 4-byte prefix -> empty
    var s8 = [_]u8{ 1, 0, 0 };
    dec(&ar, s8[0..], w5[0..0], "dec short");

    if (g_fail == 0) {
        std.io.write("rle decode ok\n");
    } else {
        std.io.write("rle decode FAIL\n");
    }
}
