// stdlib_hex_stress_xmod — STDLIB std_hex (L5) hand-written stress table.
//
// No PRNG: every input is an explicit table or an explicit fixed pattern (an
// LCG written out for the byte-pattern buffers). Stresses:
//   - the standard vectors ("foobar" -> "666f6f626172" lower / "666F6F626172"
//     upper; empty -> empty), encode and decode;
//   - decode is case-insensitive (mixed-case input);
//   - whitespace / non-hex rejection: any space/tab/CR/LF or non-hex byte is
//     error.InvalidInput and allocates nothing; an odd length likewise;
//   - the empty input is a valid empty result;
//   - decode(encodeLower/Upper(x)) == x over adversarial lengths 0..17 plus
//     31/32/33/63/64/65/127/128/129/255/256/257/511/512/513/1000 and the
//     0x00/0xFF/0xAA/alternating/LCG patterns.
//
// GREEN (contract): deterministic byte-exact stdout `hex stress ok\n` (RUNRC=0).
const std = @import("std");
const hex = @import("std_hex.zig");

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

fn expectLower(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    var enc = hex.encodeLower(ar, src) catch {
        @panic(what);
    };
    ckBytes(enc, want, what);
}

fn expectUpper(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    var enc = hex.encodeUpper(ar, src) catch {
        @panic(what);
    };
    ckBytes(enc, want, what);
}

fn expectDec(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    var dec = hex.decode(ar, src) catch {
        @panic(what);
    };
    ckBytes(dec, want, what);
}

fn invalid(ar: *std.arena.Arena, src: []const u8, what: []const u8) void {
    var used_before = ar.used;
    var got = hex.decode(ar, src) catch |e| {
        ck(e == error.InvalidInput, what);
        ck(ar.used == used_before, what);
        return;
    };
    _ = got;
    ck(false, what);
}

fn roundtrip(ar: *std.arena.Arena, src: []const u8, what: []const u8) void {
    var lo = hex.encodeLower(ar, src) catch {
        @panic(what);
    };
    ck(lo.len == src.len * 2, what);
    var up = hex.encodeUpper(ar, src) catch {
        @panic(what);
    };
    ck(up.len == src.len * 2, what);
    var dl = hex.decode(ar, lo) catch {
        @panic(what);
    };
    ckBytes(dl, src, what);
    var du = hex.decode(ar, up) catch {
        @panic(what);
    };
    ckBytes(du, src, what);
}

fn fillConst(dst: []u8, v: u8) void {
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        dst[i] = v;
    }
}

var g_buf: [1024]u8 = undefined;

pub fn main() void {
    var backing: [1048576]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    // ---- standard vectors --------------------------------------------------
    expectLower(&ar, "", "", "empty lower");
    expectUpper(&ar, "", "", "empty upper");
    expectDec(&ar, "", "", "empty dec");
    expectLower(&ar, "foobar", "666f6f626172", "foobar lower");
    expectUpper(&ar, "foobar", "666F6F626172", "foobar upper");
    expectDec(&ar, "666f6f626172", "foobar", "foobar dec lower");
    expectDec(&ar, "666F6F626172", "foobar", "foobar dec upper");
    expectDec(&ar, "666f6F626172", "foobar", "foobar dec mixed case");
    expectLower(&ar, "Hello", "48656c6c6f", "Hello lower");
    expectUpper(&ar, "Hello", "48656C6C6F", "Hello upper");
    var ff = [_]u8{ 0x00, 0x0F, 0xF0, 0xFF };
    expectLower(&ar, ff[0..], "000ff0ff", "nibble bounds lower");
    expectUpper(&ar, ff[0..], "000FF0FF", "nibble bounds upper");
    expectDec(&ar, "000FF0ff", ff[0..], "nibble bounds dec");

    // ---- whitespace / malformed rejection ----------------------------------
    invalid(&ar, "66 6f", "ws space");
    invalid(&ar, "66\t6f", "ws tab");
    invalid(&ar, "666f\n", "ws newline");
    invalid(&ar, "666f\r\n", "ws crlf");
    invalid(&ar, "666", "odd len 3");
    invalid(&ar, "6", "odd len 1");
    invalid(&ar, "zz", "non-hex z");
    invalid(&ar, "6g", "non-hex g");
    invalid(&ar, "0x66", "0x prefix");
    invalid(&ar, "-6", "dash");
    invalid(&ar, "6_", "underscore");

    // ---- round-trips over adversarial lengths ------------------------------
    var lens = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
        31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 511, 512, 513, 1000 };
    var li: usize = 0;
    while (li < lens.len) : (li += 1) {
        var len: usize = lens[li];
        fillConst(g_buf[0..len], 0x00);
        roundtrip(&ar, g_buf[0..len], "rt 0x00");
        fillConst(g_buf[0..len], 0xFF);
        roundtrip(&ar, g_buf[0..len], "rt 0xFF");
        fillConst(g_buf[0..len], 0xAA);
        roundtrip(&ar, g_buf[0..len], "rt 0xAA");
        var i: usize = 0;
        while (i < len) : (i += 1) {
            if (i % 2 == 0) g_buf[i] = 0x55 else g_buf[i] = 0xAA;
        }
        roundtrip(&ar, g_buf[0..len], "rt alt");
        var st: u32 = 0x9E3779B9 + @intCast(u32, len);
        i = 0;
        while (i < len) : (i += 1) {
            st = st *% 1664525 +% 1013904223;
            g_buf[i] = @intCast(u8, (st >> 24) & 0xFF);
        }
        roundtrip(&ar, g_buf[0..len], "rt lcg");
    }

    // ---- all 256 byte values ------------------------------------------------
    var all: [256]u8 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    roundtrip(&ar, all[0..], "rt all values");

    if (g_fail == 0) {
        std.io.write("hex stress ok\n");
    } else {
        std.io.write("hex stress FAIL\n");
    }
}
