// stdlib_base64_roundtrip_xmod — STDLIB std_base64 (L5) round-trip GREEN fixture.
//
// std_base64.zig is an L5 module that imports only std_arena (L1) and allocates
// its output from the caller's arena (R1). This fixture imports it by module
// basename (the compiler's lib search path binds <exe>/lib/std_base64.zig).
//
// Contract pinned: encode/decode are inverse for every byte string and the
// encoding is a pure function of the input (R6) — repeated encode of the same
// source into differently-offset arenas is byte-identical, and repeated decode
// of the same stream is byte-identical.
//
// Cases: empty; constant bytes (lengths 1/2/3/4/5/6/7/127/128/129/300 x values
// 0x00/0x7F/0x80/0xFF); alternating bytes; pseudo-random LCG buffers of lengths
// 0/1/2/3/7/64/255/256/257/1000; and all 256 byte values in ascending order.
//
// GREEN (contract): deterministic byte-exact stdout `base64 roundtrip ok\n`
// (RUNRC=0).
const std = @import("std");
const b64 = @import("std_base64.zig");

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

fn fillConst(dst: []u8, v: u8) void {
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        dst[i] = v;
    }
}

fn roundtrip(ar: *std.arena.Arena, src: []const u8, what: []const u8) void {
    var enc = b64.encode(ar, src) catch {
        @panic(what);
    };
    ck(enc.len == b64.encodedLen(src.len), what);
    ck(b64.decodedLen(enc.len) >= src.len, what);
    var dec = b64.decode(ar, enc) catch {
        @panic(what);
    };
    ckBytes(dec, src, what);
}

fn checkDet(src: []const u8, what: []const u8) void {
    var b1: [16384]u8 = undefined;
    var b2: [16384]u8 = undefined;
    var b3: [16384]u8 = undefined;
    var a1 = std.arena.init(b1[0..]);
    var a2 = std.arena.init(b2[7..]);
    var a3 = std.arena.init(b3[64..]);

    var e1 = b64.encode(&a1, src) catch {
        @panic(what);
    };
    var e2 = b64.encode(&a2, src) catch {
        @panic(what);
    };
    var e3 = b64.encode(&a3, src) catch {
        @panic(what);
    };
    ckBytes(e1, e2, what);
    ckBytes(e1, e3, what);

    var d1 = b64.decode(&a1, e1) catch {
        @panic(what);
    };
    var d2 = b64.decode(&a2, e1) catch {
        @panic(what);
    };
    var d3 = b64.decode(&a3, e1) catch {
        @panic(what);
    };
    ckBytes(d1, d2, what);
    ckBytes(d1, d3, what);
    ckBytes(d1, src, what);
}

pub fn main() void {
    var backing: [524288]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var e0: [1]u8 = undefined;
    roundtrip(&ar, e0[0..0], "rt empty");

    var buf: [301]u8 = undefined;
    var lens = [_]usize{ 1, 2, 3, 4, 5, 6, 7, 127, 128, 129, 300 };
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

    var alt: [257]u8 = undefined;
    var i: usize = 0;
    while (i < alt.len) : (i += 1) {
        if (i % 2 == 0) alt[i] = 0xAA else alt[i] = 0x55;
    }
    roundtrip(&ar, alt[0..257], "rt alt aa55 257");
    roundtrip(&ar, alt[0..256], "rt alt aa55 256");
    roundtrip(&ar, alt[0..2], "rt alt aa55 2");
    roundtrip(&ar, alt[0..1], "rt alt aa55 1");

    var rnd: [1000]u8 = undefined;
    var rlens = [_]usize{ 0, 1, 2, 3, 7, 64, 255, 256, 257, 1000 };
    var ri: usize = 0;
    while (ri < rlens.len) : (ri += 1) {
        var st: u32 = 0x9E3779B9 + @intCast(u32, ri);
        i = 0;
        while (i < rnd.len) : (i += 1) {
            st = st *% 1664525 +% 1013904223;
            rnd[i] = @intCast(u8, (st >> 24) & 0xFF);
        }
        roundtrip(&ar, rnd[0..rlens[ri]], "rt random");
    }

    var all: [256]u8 = undefined;
    i = 0;
    while (i < all.len) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    roundtrip(&ar, all[0..], "rt all values");

    checkDet(rnd[0..], "det random");
    var cst: [300]u8 = undefined;
    fillConst(cst[0..], 0x5A);
    checkDet(cst[0..], "det const");
    checkDet(alt[0..], "det alt");

    if (g_fail == 0) {
        std.io.write("base64 roundtrip ok\n");
    } else {
        std.io.write("base64 roundtrip FAIL\n");
    }
}
