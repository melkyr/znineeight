// stdlib_utf8_encode_xmod — STDLIB std_utf8 (L5) encode GREEN fixture.
//
// std_utf8.zig is a pure L5 module: no imports, no allocation, no error set
// (contract: alloc none | errors none | coroutine no; R1). This fixture imports
// it by module basename (the compiler's lib search path binds
// <exe>/lib/std_utf8.zig).
//
// encode(buf, cp) writes the UTF-8 encoding of scalar value `cp` into the
// caller's buffer and returns the written slice `buf[0..n]` (n in 1..4), or
// null when `cp` is not a Unicode scalar value (a surrogate U+D800..U+DFFF or
// above U+10FFFF) or when `buf` cannot hold the encoding. `buf` is never
// grown; the returned slice aliases the front of `buf`.
//
// Cases: every 1/2/3/4-byte boundary (U+0000, U+007F, U+0080, U+07FF, U+0800,
// U+D7FF, U+E000, U+FFFF, U+10000, U+10FFFF, U+1F600, U+20AC); invalid scalars
// (surrogates, >U+10FFFF); too-small buffers (0..3) rejected; exact-fit
// buffers accepted; encode->decode round-trips.
//
// GREEN (contract): deterministic byte-exact stdout `utf8 encode ok\n`
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

fn encIs(cp: u32, want: []const u8, what: []const u8) void {
    var buf: [8]u8 = undefined;
    var got = utf8.encode(buf[0..], cp);
    if (got) |g| {
        ck(g.len == want.len, what);
        var i: usize = 0;
        while (i < g.len) : (i += 1) {
            ck(g[i] == want[i], what);
        }
    } else {
        ck(false, what);
    }
}

fn encNull(cp: u32, what: []const u8) void {
    var buf: [8]u8 = undefined;
    var got = utf8.encode(buf[0..], cp);
    ck(got == null, what);
}

// Exact-fit: buf.len == the encoding length must succeed.
fn encFit(cp: u32, cap: usize, want_len: u8, what: []const u8) void {
    var buf: [8]u8 = undefined;
    var got = utf8.encode(buf[0..cap], cp);
    if (got) |g| {
        ck(g.len == @intCast(usize, want_len), what);
    } else {
        ck(false, what);
    }
}

// Too-small: buf.len < the encoding length must return null.
fn encSmall(cp: u32, cap: usize, what: []const u8) void {
    var buf: [8]u8 = undefined;
    var got = utf8.encode(buf[0..cap], cp);
    ck(got == null, what);
}

// encode then decode recovers the scalar and the byte length.
fn rt(cp: u32, what: []const u8) void {
    var buf: [8]u8 = undefined;
    var got = utf8.encode(buf[0..], cp);
    if (got) |g| {
        var back = utf8.decode(g);
        if (back) |c| {
            ck(c.cp == cp, what);
            ck(c.len == @intCast(u8, g.len), what);
        } else {
            ck(false, what);
        }
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    // 1-byte.
    var w0: [1]u8 = [_]u8{0x00};
    encIs(0x00, w0[0..], "U+0000");
    encIs(0x41, "A", "U+0041");
    var w7f: [1]u8 = [_]u8{0x7F};
    encIs(0x7F, w7f[0..], "U+007F");

    // 2-byte.
    var w80: [2]u8 = [_]u8{ 0xC2, 0x80 };
    encIs(0x80, w80[0..], "U+0080");
    var we9: [2]u8 = [_]u8{ 0xC3, 0xA9 };
    encIs(0xE9, we9[0..], "U+00E9");
    var w7ff: [2]u8 = [_]u8{ 0xDF, 0xBF };
    encIs(0x7FF, w7ff[0..], "U+07FF");

    // 3-byte.
    var w800: [3]u8 = [_]u8{ 0xE0, 0xA0, 0x80 };
    encIs(0x800, w800[0..], "U+0800");
    var w20ac: [3]u8 = [_]u8{ 0xE2, 0x82, 0xAC };
    encIs(0x20AC, w20ac[0..], "U+20AC");
    var wd7ff: [3]u8 = [_]u8{ 0xED, 0x9F, 0xBF };
    encIs(0xD7FF, wd7ff[0..], "U+D7FF");
    var we000: [3]u8 = [_]u8{ 0xEE, 0x80, 0x80 };
    encIs(0xE000, we000[0..], "U+E000");
    var wffff: [3]u8 = [_]u8{ 0xEF, 0xBF, 0xBF };
    encIs(0xFFFF, wffff[0..], "U+FFFF");

    // 4-byte.
    var w10000: [4]u8 = [_]u8{ 0xF0, 0x90, 0x80, 0x80 };
    encIs(0x10000, w10000[0..], "U+10000");
    var w1f600: [4]u8 = [_]u8{ 0xF0, 0x9F, 0x98, 0x80 };
    encIs(0x1F600, w1f600[0..], "U+1F600");
    var w10ffff: [4]u8 = [_]u8{ 0xF4, 0x8F, 0xBF, 0xBF };
    encIs(0x10FFFF, w10ffff[0..], "U+10FFFF");

    // Invalid scalars.
    encNull(0xD800, "surrogate U+D800");
    encNull(0xDFFF, "surrogate U+DFFF");
    encNull(0x110000, "U+110000");
    encNull(0x7FFFFFFF, "i32 max");

    // Too-small buffers.
    encSmall(0x41, 0, "cap 0 for 1-byte");
    encSmall(0xE9, 1, "cap 1 for 2-byte");
    encSmall(0x20AC, 2, "cap 2 for 3-byte");
    encSmall(0x1F600, 3, "cap 3 for 4-byte");

    // Exact-fit buffers.
    encFit(0x41, 1, 1, "fit 1-byte");
    encFit(0xE9, 2, 2, "fit 2-byte");
    encFit(0x20AC, 3, 3, "fit 3-byte");
    encFit(0x1F600, 4, 4, "fit 4-byte");

    // encode -> decode round-trips across all length classes.
    rt(0x00, "rt U+0000");
    rt(0x41, "rt U+0041");
    rt(0x7F, "rt U+007F");
    rt(0x80, "rt U+0080");
    rt(0xE9, "rt U+00E9");
    rt(0x7FF, "rt U+07FF");
    rt(0x800, "rt U+0800");
    rt(0x20AC, "rt U+20AC");
    rt(0xD7FF, "rt U+D7FF");
    rt(0xE000, "rt U+E000");
    rt(0xFFFF, "rt U+FFFF");
    rt(0x10000, "rt U+10000");
    rt(0x1F600, "rt U+1F600");
    rt(0x10FFFF, "rt U+10FFFF");

    if (g_fail == 0) {
        std.io.write("utf8 encode ok\n");
    } else {
        std.io.write("utf8 encode FAIL\n");
    }
}
