// stdlib_utf8_stress_xmod — STDLIB std_utf8 (L5) hand-written stress table.
//
// No PRNG: every input is an explicit byte array or a written code-point table.
// Stresses:
//   - valid multi-byte sequences for a written code-point table spanning every
//     boundary (U+0000/007F/0080/07FF/0800/D7FF/E000/FFFF/10000/10FFFF) and
//     assorted scalars: encode, codepointLen, decode, countCodepoints all agree;
//   - invalid continuations, overlong 2/3/4-byte encodings, surrogates,
//     >U+10FFFF, impossible leads, and truncated sequences all decode null;
//   - encode rejects surrogates, >U+10FFFF, and an undersized buffer (writes
//     nothing);
//   - countCodepoints over a mixed valid+invalid input and over all 256 bytes.
//
// GREEN (contract): deterministic byte-exact stdout `utf8 stress ok\n`
// (RUNRC=0).
const std = @import("std");
const utf8 = @import("std_utf8.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn encOk(cp: u32, want_len: usize, what: []const u8) void {
    var buf: [8]u8 = undefined;
    var e = utf8.encode(buf[0..], cp);
    if (e) |s| {
        ck(s.len == want_len, what);
        ck(utf8.codepointLen(s[0]) == @intCast(u8, want_len), what);
        var d = utf8.decode(s);
        if (d) |c| {
            ck(c.cp == cp, what);
            ck(@intCast(usize, c.len) == want_len, what);
        } else {
            ck(false, what);
        }
        ck(utf8.countCodepoints(s) == 1, what);
    } else {
        ck(false, what);
    }
}

fn decNull(b: []const u8, what: []const u8) void {
    ck(utf8.decode(b) == null, what);
}

fn appendInv(dst: []u8, pos0: usize, src: []const u8) usize {
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        dst[pos0 + i] = src[i];
    }
    return pos0 + src.len;
}

var g_mix: [256]u8 = undefined;

pub fn main() void {
    // ---- valid code points (boundaries + assorted scalars) -----------------
    var cps = [_]u32{
        0x00, 0x01, 0x24, 0x41, 0x7E, 0x7F,
        0x80, 0xA2, 0xE9, 0x7FF,
        0x800, 0x939, 0x20AC, 0xD7FF, 0xE000, 0xFFFD, 0xFFFF,
        0x10000, 0x10348, 0x1D11E, 0x1F600, 0x10FFFF,
    };
    var i: usize = 0;
    while (i < cps.len) : (i += 1) {
        var cp: u32 = cps[i];
        var want: usize = 4;
        if (cp < 0x80) {
            want = 1;
        } else if (cp < 0x800) {
            want = 2;
        } else if (cp < 0x10000) {
            want = 3;
        }
        encOk(cp, want, "valid cp");
    }

    // ---- invalid continuations ---------------------------------------------
    var bad2: [2]u8 = [_]u8{ 0xC3, 0x41 };
    decNull(bad2[0..], "bad cont 2");
    var bad3: [3]u8 = [_]u8{ 0xE2, 0x82, 0x41 };
    decNull(bad3[0..], "bad cont 3");
    var bad4: [4]u8 = [_]u8{ 0xF0, 0x9F, 0x98, 0x41 };
    decNull(bad4[0..], "bad cont 4");
    var bad_hi2: [2]u8 = [_]u8{ 0xC3, 0xC0 };
    decNull(bad_hi2[0..], "cont too high 2");
    var bad_hi3: [3]u8 = [_]u8{ 0xE2, 0x82, 0xFF };
    decNull(bad_hi3[0..], "cont too high 3");

    // ---- overlong ----------------------------------------------------------
    var ol2a: [2]u8 = [_]u8{ 0xC0, 0x80 };
    decNull(ol2a[0..], "overlong 2 C0 80");
    var ol2b: [2]u8 = [_]u8{ 0xC1, 0xBF };
    decNull(ol2b[0..], "overlong 2 C1 BF");
    var ol3a: [3]u8 = [_]u8{ 0xE0, 0x80, 0x80 };
    decNull(ol3a[0..], "overlong 3 E0 80 80");
    var ol3b: [3]u8 = [_]u8{ 0xE0, 0x9F, 0xBF };
    decNull(ol3b[0..], "overlong 3 E0 9F BF");
    var ol4a: [4]u8 = [_]u8{ 0xF0, 0x80, 0x80, 0x80 };
    decNull(ol4a[0..], "overlong 4 F0 80 80 80");
    var ol4b: [4]u8 = [_]u8{ 0xF0, 0x8F, 0xBF, 0xBF };
    decNull(ol4b[0..], "overlong 4 F0 8F BF BF");

    // ---- surrogates --------------------------------------------------------
    var sur_hi: [3]u8 = [_]u8{ 0xED, 0xA0, 0x80 };
    decNull(sur_hi[0..], "surrogate D800");
    var sur_lo: [3]u8 = [_]u8{ 0xED, 0xBF, 0xBF };
    decNull(sur_lo[0..], "surrogate DFFF");

    // ---- above U+10FFFF ----------------------------------------------------
    var big1: [4]u8 = [_]u8{ 0xF4, 0x90, 0x80, 0x80 };
    decNull(big1[0..], "U+110000");
    var big2: [4]u8 = [_]u8{ 0xF5, 0x80, 0x80, 0x80 };
    decNull(big2[0..], "lead F5");
    var big3: [4]u8 = [_]u8{ 0xF7, 0xBF, 0xBF, 0xBF };
    decNull(big3[0..], "lead F7");

    // ---- impossible leads --------------------------------------------------
    var l80: [1]u8 = [_]u8{0x80};
    decNull(l80[0..], "lead 80");
    var lbf: [1]u8 = [_]u8{0xBF};
    decNull(lbf[0..], "lead BF");
    var lc0: [1]u8 = [_]u8{0xC0};
    decNull(lc0[0..], "lead C0");
    var lc1: [1]u8 = [_]u8{0xC1};
    decNull(lc1[0..], "lead C1");
    var lfe: [1]u8 = [_]u8{0xFE};
    decNull(lfe[0..], "lead FE");
    var lff: [1]u8 = [_]u8{0xFF};
    decNull(lff[0..], "lead FF");
    ck(utf8.codepointLen(0x80) == 0, "codepointLen 80");
    ck(utf8.codepointLen(0xC0) == 0, "codepointLen C0");
    ck(utf8.codepointLen(0xC1) == 0, "codepointLen C1");
    ck(utf8.codepointLen(0xF5) == 0, "codepointLen F5");
    ck(utf8.codepointLen(0xFF) == 0, "codepointLen FF");
    ck(utf8.codepointLen(0xC2) == 2, "codepointLen C2");
    ck(utf8.codepointLen(0xE0) == 3, "codepointLen E0");
    ck(utf8.codepointLen(0xF0) == 4, "codepointLen F0");

    // ---- truncated ---------------------------------------------------------
    var t1: [1]u8 = [_]u8{0xC3};
    decNull(t1[0..], "truncated 2");
    var t2: [2]u8 = [_]u8{ 0xE2, 0x82 };
    decNull(t2[0..], "truncated 3");
    var t3: [3]u8 = [_]u8{ 0xF0, 0x9F, 0x98 };
    decNull(t3[0..], "truncated 4");
    decNull("", "empty");

    // ---- encode rejects + short buffer -------------------------------------
    var eb: [8]u8 = undefined;
    ck(utf8.encode(eb[0..], 0xD800) == null, "encode surrogate lo");
    ck(utf8.encode(eb[0..], 0xDFFF) == null, "encode surrogate hi");
    ck(utf8.encode(eb[0..], 0x110000) == null, "encode above max");
    ck(utf8.encode(eb[0..], 0xFFFFFFFF) == null, "encode u32 max");
    var tiny: [1]u8 = undefined;
    tiny[0] = 0xAA;
    ck(utf8.encode(tiny[0..], 0x80) == null, "encode short buffer");
    ck(tiny[0] == 0xAA, "encode short buffer untouched");
    var tiny3: [2]u8 = undefined;
    tiny3[0] = 0xAA;
    tiny3[1] = 0xAA;
    ck(utf8.encode(tiny3[0..], 0x20AC) == null, "encode short 3");

    // ---- countCodepoints over a mixed valid+invalid input ------------------
    var pos: usize = 0;
    var expect: usize = 0;
    i = 0;
    while (i < cps.len) : (i += 1) {
        var b: [8]u8 = undefined;
        var e = utf8.encode(b[0..], cps[i]);
        if (e) |s| {
            std.str.copy(g_mix[pos .. pos + s.len], s);
            pos += s.len;
            expect += 1;
        }
    }
    // Append invalid sequences; each byte contributes exactly one unit.
    pos = appendInv(g_mix[0..], pos, bad2[0..]);
    expect += 2;
    pos = appendInv(g_mix[0..], pos, bad3[0..]);
    expect += 3;
    pos = appendInv(g_mix[0..], pos, ol2a[0..]);
    expect += 2;
    pos = appendInv(g_mix[0..], pos, sur_hi[0..]);
    expect += 3;
    pos = appendInv(g_mix[0..], pos, big1[0..]);
    expect += 4;
    pos = appendInv(g_mix[0..], pos, lff[0..]);
    expect += 1;
    ck(utf8.countCodepoints(g_mix[0..pos]) == expect, "mixed count");

    // ---- countCodepoints over all 256 bytes = 256 --------------------------
    var all: [256]u8 = undefined;
    i = 0;
    while (i < 256) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    ck(utf8.countCodepoints(all[0..]) == 256, "all256 count");

    if (g_fail == 0) {
        std.io.write("utf8 stress ok\n");
    } else {
        std.io.write("utf8 stress FAIL\n");
    }
}
