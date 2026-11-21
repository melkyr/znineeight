// stdlib_rle_determinism_xmod — std_rle (L4) determinism GREEN fixture (R6).
//
// Contract (blueprint §3 L4 + §1 R6): the encoding is a pure function of the
// input bytes — no address, clock, or PID input. Repeated `encode` of the same
// source must be byte-identical, and repeated `decode` of the same stream must
// be byte-identical, even when the arena lives in differently-offset backing
// storage.
//
// Cases pinned: a 256-byte pseudo-random source, a constant-run source, and an
// alternating source each encoded 3x into arenas at three different offsets and
// compared byte-for-byte; the first encoded stream decoded 3x and compared.
//
// GREEN (contract): deterministic byte-exact stdout `rle determinism ok\n`
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

fn fillConst(dst: []u8, v: u8) void {
    var i: usize = 0;
    while (i < dst.len) : (i += 1) {
        dst[i] = v;
    }
}

fn checkDet(src: []const u8, what: []const u8) void {
    var b1: [16384]u8 = undefined;
    var b2: [16384]u8 = undefined;
    var b3: [16384]u8 = undefined;
    var a1 = std.arena.init(b1[0..]);
    var a2 = std.arena.init(b2[7..]);
    var a3 = std.arena.init(b3[64..]);

    var e1 = rle.encode(&a1, src) catch {
        @panic(what);
    };
    var e2 = rle.encode(&a2, src) catch {
        @panic(what);
    };
    var e3 = rle.encode(&a3, src) catch {
        @panic(what);
    };
    ckBytes(e1, e2, what);
    ckBytes(e1, e3, what);

    var d1 = rle.decode(&a1, e1) catch {
        @panic(what);
    };
    var d2 = rle.decode(&a2, e1) catch {
        @panic(what);
    };
    var d3 = rle.decode(&a3, e1) catch {
        @panic(what);
    };
    ckBytes(d1, d2, what);
    ckBytes(d1, d3, what);
    ckBytes(d1, src, what);
}

pub fn main() void {
    // pseudo-random source
    var rnd: [256]u8 = undefined;
    var st: u32 = 0x0BADF00D;
    var i: usize = 0;
    while (i < rnd.len) : (i += 1) {
        st = st *% 1664525 +% 1013904223;
        rnd[i] = @intCast(u8, (st >> 24) & 0xFF);
    }
    checkDet(rnd[0..], "det random");

    // constant-run source
    var cst: [300]u8 = undefined;
    fillConst(cst[0..], 0x5A);
    checkDet(cst[0..], "det const");

    // alternating source
    var alt: [257]u8 = undefined;
    i = 0;
    while (i < alt.len) : (i += 1) {
        if (i % 2 == 0) alt[i] = 0x01 else alt[i] = 0x80;
    }
    checkDet(alt[0..], "det alt");

    if (g_fail == 0) {
        std.io.write("rle determinism ok\n");
    } else {
        std.io.write("rle determinism FAIL\n");
    }
}
