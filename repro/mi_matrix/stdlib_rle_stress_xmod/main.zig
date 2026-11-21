// stdlib_rle_stress_xmod — STDLIB std_rle (L4) hand-written stress table.
//
// No PRNG: every input is an explicit table or an explicit fixed pattern.
// Stresses:
//   - long runs at the 128-byte token boundary: 128/129/130/256/257/384/1000/
//     1024/4096 equal bytes, for values 0x00/0x41/0x7F/0x80/0xFF; the exact
//     encoded size is pinned for the runs;
//   - alternating bytes (0xAA/0x55, 0x01/0x80) at adversarial lengths;
//   - the empty input (encodedLen 4, decodedLen 0, empty decode);
//   - a mixed run/literal buffer and all 256 byte values;
//   - for every case: encode.len == encodedLen(src), decodedLen(enc) == src.len,
//     and decode(encode(src)) == src.
//
// GREEN (contract): deterministic byte-exact stdout `rle stress ok\n` (RUNRC=0).
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

fn checkLen(ar: *std.arena.Arena, src: []const u8, want: usize, what: []const u8) void {
    ck(rle.encodedLen(src) == want, what);
    var enc = rle.encode(ar, src) catch {
        @panic(what);
    };
    ck(enc.len == want, what);
    ck(enc.len == rle.encodedLen(src), what);
    ck(rle.decodedLen(enc) == src.len, what);
    var dec = rle.decode(ar, enc) catch {
        @panic(what);
    };
    ckBytes(dec, src, what);
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

var g_buf: [4096]u8 = undefined;
var g_backing: [4194304]u8 = undefined;
var g_arena = std.arena.init(g_backing[0..]);

pub fn main() void {
    // ---- empty -------------------------------------------------------------
    var e0: [1]u8 = undefined;
    checkLen(&g_arena, e0[0..0], 4, "empty");
    ck(rle.decodedLen(e0[0..0]) == 0, "empty decodedLen short src");

    // ---- single literals / high-bit singles --------------------------------
    var s1 = [_]u8{'A'};
    checkLen(&g_arena, s1[0..], 5, "single literal");
    var s2 = [_]u8{0x80};
    checkLen(&g_arena, s2[0..], 6, "single high-bit");
    var s3 = [_]u8{ 0x7F, 0x7F };
    checkLen(&g_arena, s3[0..], 6, "run2");
    var s4 = [_]u8{ 0x7F, 0x7F, 0x7F };
    checkLen(&g_arena, s4[0..], 6, "run3");

    // ---- run token boundaries: exact encoded sizes -------------------------
    // run n equal bytes v: n==1 and v<0x80 -> literal (1); else 2*ceil(n/128).
    var lens = [_]usize{ 128, 129, 130, 256, 257, 384, 1000, 1024, 4096 };
    var vals = [_]u8{ 0x00, 0x41, 0x7F, 0x80, 0xFF };
    var li: usize = 0;
    while (li < lens.len) : (li += 1) {
        var vi: usize = 0;
        while (vi < vals.len) : (vi += 1) {
            var n: usize = lens[li];
            var want: usize = 4 + 2 * ((n + 127) / 128);
            fillConst(g_buf[0..n], vals[vi]);
            checkLen(&g_arena, g_buf[0..n], want, "run boundary");
        }
    }

    // ---- alternating bytes (adversarial lengths) ---------------------------
    var alens = [_]usize{ 1, 2, 3, 4, 5, 127, 128, 129, 255, 256, 257, 1000 };
    li = 0;
    while (li < alens.len) : (li += 1) {
        var n: usize = alens[li];
        fillAlt(g_buf[0..n], 0xAA, 0x55);
        roundtrip(&g_arena, g_buf[0..n], "alt aa55");
        fillAlt(g_buf[0..n], 0x01, 0x80);
        roundtrip(&g_arena, g_buf[0..n], "alt 0180");
        fillAlt(g_buf[0..n], 0x7F, 0x00);
        roundtrip(&g_arena, g_buf[0..n], "alt 7f00");
    }

    // ---- all 256 byte values ascending -------------------------------------
    var all: [256]u8 = undefined;
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    // 128 literals (values < 0x80) + 128 two-byte runs + 4 prefix = 388
    checkLen(&g_arena, all[0..], 388, "all 256 ascending");

    // ---- mixed runs + literals ---------------------------------------------
    i = 0;
    while (i < 4096) : (i += 1) {
        var seg: usize = i / 7;
        if (seg % 3 == 0) {
            g_buf[i] = 0xAA;
        } else if (i % 2 == 0) {
            g_buf[i] = 0x41;
        } else {
            g_buf[i] = 0x42;
        }
    }
    roundtrip(&g_arena, g_buf[0..4096], "mixed runs/literals");

    // ---- leading/trailing runs with literals in between --------------------
    fillConst(g_buf[0..500], 0x00);
    fillConst(g_buf[500..1000], 0x41);
    g_buf[1000] = 0x80;
    fillConst(g_buf[1001..2000], 0xFF);
    roundtrip(&g_arena, g_buf[0..2000], "leading/trailing runs");

    if (g_fail == 0) {
        std.io.write("rle stress ok\n");
    } else {
        std.io.write("rle stress FAIL\n");
    }
}
