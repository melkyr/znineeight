// stdlib_rle_roundtrip_xmod — std_rle (L4) round-trip GREEN fixture.
//
// Contract (blueprint §3 L4): `encode`/`decode` are inverse for every byte
// string; `encodedLen` is exact; `decodedLen` recovers the source length. This
// is the brief's case set: round-trip on random bytes, constant bytes,
// alternating bytes, and empty input.
//
// Cases pinned:
//   - empty input (length 0);
//   - constant bytes: lengths 1/2/127/128/129/300 x values 0x00/0x7F/0x80/0xFF;
//   - alternating bytes: 0xAA/0x55 and 0x01/0x80, lengths 1/2/256/257;
//   - random bytes: LCG buffers of lengths 0/1/2/3/7/64/255/256/257/1000;
//   - every byte value 0..255 in ascending order;
//   - a mixed buffer of long runs and isolated literals.
//
// GREEN (contract): deterministic byte-exact stdout `rle roundtrip ok\n`
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

fn ckBytes(got: []const u8, want: []const u8, what: []const u8) void {
    ck(got.len == want.len, what);
    var i: usize = 0;
    while (i < got.len) : (i += 1) {
        ck(got[i] == want[i], what);
    }
}

fn roundtrip(ar: *std.arena.Arena, src: []const u8, what: []const u8) void {
    var enc = rle.encode(ar, src) catch {
        @panic(what);
    };
    ck(enc.len == rle.encodedLen(src), what);
    ck(rle.decodedLen(enc) == src.len, what);
    var dec = rle.decode(ar, enc) catch {
        @panic(what);
    };
    ckBytes(dec, src, what);
}

fn fillConst(dst: []u8, v: u8) void {
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        dst[i] = v;
    }
}

fn fillAlt(dst: []u8, a: u8, b: u8) void {
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        if (i % 2 == 0) dst[i] = a else dst[i] = b;
    }
}

pub fn main() void {
    var backing: [131072]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    // empty
    var e0: [1]u8 = undefined;
    roundtrip(&ar, e0[0..0], "rt empty");

    // constant bytes across lengths and values
    var buf: [301]u8 = undefined;
    var lens = [_]usize{ 1, 2, 127, 128, 129, 300 };
    var vals = [_]u8{ 0x00, 0x7F, 0x80, 0xFF };
    var li: usize = 0;
    while (li < lens.len) : (li += 1) {
        var vi: usize = 0;
        while (vi < vals.len) : (vi += 1) {
            var n: usize = lens[li];
            fillConst(buf[0..n], vals[vi]);
            roundtrip(&ar, buf[0..n], "rt const");
        }
    }

    // alternating bytes
    var alt: [257]u8 = undefined;
    fillAlt(alt[0..], 0xAA, 0x55);
    roundtrip(&ar, alt[0..257], "rt alt aa55 257");
    roundtrip(&ar, alt[0..256], "rt alt aa55 256");
    roundtrip(&ar, alt[0..2], "rt alt aa55 2");
    roundtrip(&ar, alt[0..1], "rt alt aa55 1");
    fillAlt(alt[0..], 0x01, 0x80);
    roundtrip(&ar, alt[0..257], "rt alt 0180 257");
    roundtrip(&ar, alt[0..256], "rt alt 0180 256");

    // random bytes
    var rnd: [1000]u8 = undefined;
    var rlens = [_]usize{ 0, 1, 2, 3, 7, 64, 255, 256, 257, 1000 };
    var ri: usize = 0;
    while (ri < rlens.len) : (ri += 1) {
        var st: u32 = 0x9E3779B9 + @intCast(u32, ri);
        var i: usize = 0;
        while (i < rnd.len) : (i += 1) {
            st = st *% 1664525 +% 1013904223;
            rnd[i] = @intCast(u8, (st >> 24) & 0xFF);
        }
        roundtrip(&ar, rnd[0..rlens[ri]], "rt random");
    }

    // every byte value in ascending order
    var all: [256]u8 = undefined;
    var i: usize = 0;
    while (i < all.len) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    roundtrip(&ar, all[0..], "rt all values");

    // mixed long runs and isolated literals
    var mix: [400]u8 = undefined;
    i = 0;
    while (i < mix.len) : (i += 1) mix[i] = 0x00;
    var k: usize = 0;
    while (k < 5) : (k += 1) {
        var base: usize = k * 80;
        fillConst(mix[base .. base + 70], @intCast(u8, 0x41 + k));
        mix[base + 70] = 0x80 + @intCast(u8, k);
        mix[base + 71] = 0x7F - @intCast(u8, k);
    }
    roundtrip(&ar, mix[0..], "rt mixed");

    if (g_fail == 0) {
        std.io.write("rle roundtrip ok\n");
    } else {
        std.io.write("rle roundtrip FAIL\n");
    }
}
