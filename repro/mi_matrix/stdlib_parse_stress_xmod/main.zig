// stdlib_parse_stress_xmod — STDLIB std_parse (L5) hand-written stress table.
//
// No PRNG: every input is an explicit literal table. Stresses:
//   - valid/invalid tables for parseInt/parseUint/parseInt64/parseUint64/
//     parseFloat (whitespace, '+', '_', malformed, '.'-only, exponent);
//   - the i32/u32/i64/u64 overflow boundaries (max accepted, max+1 rejected,
//     min accepted, min-1 rejected);
//   - itoa/utoa/itoa64/utoa64 round-trips (format then reparse == value);
//   - buffer-end writes: itoa/utoa/itoa64/utoa64/ftoa write a suffix at the END
//     of buf and leave every earlier byte untouched;
//   - ftoa fixed-point, precision clamp, non-finite, and the short-buffer guard.
//
// GREEN (contract): deterministic byte-exact stdout `parse stress ok\n`
// (RUNRC=0).
const std = @import("std");
const parse = @import("std_parse.zig");

const I32_MIN: i32 = -2147483647 - 1;
const I64_MIN: i64 = @bitCast(i64, @intCast(u64, 0x8000000000000000));
const U32_MAX: u32 = @intCast(u32, 0xFFFFFFFF);
const U64_MAX: u64 = @intCast(u64, 0xFFFFFFFFFFFFFFFF);

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

fn wantI32(s: []const u8, want: i32, what: []const u8) void {
    var got = parse.parseInt(s);
    if (got) |v| {
        ck(v == want, what);
    } else {
        ck(false, what);
    }
}

fn wantU32(s: []const u8, want: u32, what: []const u8) void {
    var got = parse.parseUint(s);
    if (got) |v| {
        ck(v == want, what);
    } else {
        ck(false, what);
    }
}

fn wantI64(s: []const u8, want: i64, what: []const u8) void {
    var got = parse.parseInt64(s);
    if (got) |v| {
        ck(v == want, what);
    } else {
        ck(false, what);
    }
}

fn wantU64(s: []const u8, want: u64, what: []const u8) void {
    var got = parse.parseUint64(s);
    if (got) |v| {
        ck(v == want, what);
    } else {
        ck(false, what);
    }
}

fn wantF(s: []const u8, want: f64, what: []const u8) void {
    var got = parse.parseFloat(s);
    if (got) |v| {
        var d = v - want;
        if (d < 0.0) d = -d;
        ck(d < 0.000001, what);
    } else {
        ck(false, what);
    }
}

fn nullI32(s: []const u8, what: []const u8) void {
    ck(parse.parseInt(s) == null, what);
}
fn nullU32(s: []const u8, what: []const u8) void {
    ck(parse.parseUint(s) == null, what);
}
fn nullI64(s: []const u8, what: []const u8) void {
    ck(parse.parseInt64(s) == null, what);
}
fn nullU64(s: []const u8, what: []const u8) void {
    ck(parse.parseUint64(s) == null, what);
}
fn nullF(s: []const u8, what: []const u8) void {
    ck(parse.parseFloat(s) == null, what);
}

// checkTail asserts `r` is the byte-exact suffix of `buf` (writes from the end)
// and that every byte before the result is still the 0xAA sentinel.
fn checkTail(buf: []const u8, r: []const u8, what: []const u8) void {
    ck(r.len <= buf.len, what);
    var start: usize = buf.len - r.len;
    var i: usize = 0;
    while (i < r.len) : (i += 1) {
        ck(buf[start + i] == r[i], what);
    }
    i = 0;
    while (i < start) : (i += 1) {
        ck(buf[i] == 0xAA, what);
    }
}

fn fillSentinel(buf: []u8) void {
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = 0xAA;
    }
}

pub fn main() void {
    // ---- valid tables ------------------------------------------------------
    wantI32("0", 0, "i32 0");
    wantI32("42", 42, "i32 42");
    wantI32("-42", -42, "i32 -42");
    wantI32("007", 7, "i32 leading zeros");
    wantI32("-0", 0, "i32 -0");
    wantI32("2147483647", @intCast(i32, 2147483647), "i32 max");
    wantI32("-2147483648", I32_MIN, "i32 min");
    wantI32("1000000", 1000000, "i32 million");

    wantU32("0", 0, "u32 0");
    wantU32("42", 42, "u32 42");
    wantU32("007", 7, "u32 leading zeros");
    wantU32("4294967295", U32_MAX, "u32 max");
    wantU32("1000000", 1000000, "u32 million");

    wantI64("0", 0, "i64 0");
    wantI64("42", 42, "i64 42");
    wantI64("-42", -42, "i64 -42");
    wantI64("9223372036854775807", @intCast(i64, 0x7FFFFFFFFFFFFFFF), "i64 max");
    wantI64("-9223372036854775808", I64_MIN, "i64 min");

    wantU64("0", 0, "u64 0");
    wantU64("42", 42, "u64 42");
    wantU64("18446744073709551615", U64_MAX, "u64 max");
    wantU64("18446744073709551614", U64_MAX - 1, "u64 max-1");

    wantF("0", 0.0, "f 0");
    wantF("3.14", 3.14, "f 3.14");
    wantF("-1.25", -1.25, "f -1.25");
    wantF("10.", 10.0, "f 10.");
    wantF(".5", 0.5, "f .5");
    wantF("123.456", 123.456, "f 123.456");
    wantF("-0.5", -0.5, "f -0.5");
    wantF("007", 7.0, "f leading zeros");
    wantF("-0", 0.0, "f -0");

    // ---- invalid tables ----------------------------------------------------
    nullI32("", "i32 empty");
    nullI32("+1", "i32 plus");
    nullI32(" 1", "i32 leading space");
    nullI32("1 ", "i32 trailing space");
    nullI32("1_0", "i32 underscore");
    nullI32("x", "i32 alpha");
    nullI32("-", "i32 lone minus");
    nullI32("--1", "i32 double minus");

    nullU32("", "u32 empty");
    nullU32("-1", "u32 neg");
    nullU32("+1", "u32 plus");
    nullU32(" 1", "u32 leading space");
    nullU32("1 ", "u32 trailing space");
    nullU32("1_0", "u32 underscore");

    nullI64("", "i64 empty");
    nullI64("+1", "i64 plus");
    nullI64(" 1", "i64 leading space");
    nullI64("1 ", "i64 trailing space");
    nullI64("-", "i64 lone minus");

    nullU64("", "u64 empty");
    nullU64("-1", "u64 neg");
    nullU64("+1", "u64 plus");
    nullU64("1 ", "u64 trailing space");

    nullF("", "f empty");
    nullF("-", "f lone minus");
    nullF(".", "f lone dot");
    nullF("+1", "f plus");
    nullF(" 1", "f leading space");
    nullF("1 ", "f trailing space");
    nullF("1_0", "f underscore");
    nullF("1e5", "f exponent");
    nullF("abc", "f alpha");
    nullF("1.2.3", "f two dots");

    // ---- overflow boundaries ----------------------------------------------
    wantI32("2147483647", @intCast(i32, 2147483647), "i32 max boundary ok");
    nullI32("2147483648", "i32 max+1");
    wantI32("-2147483648", I32_MIN, "i32 min boundary ok");
    nullI32("-2147483649", "i32 min-1");

    wantU32("4294967295", U32_MAX, "u32 max boundary ok");
    nullU32("4294967296", "u32 max+1");

    wantI64("9223372036854775807", @intCast(i64, 0x7FFFFFFFFFFFFFFF), "i64 max boundary ok");
    nullI64("9223372036854775808", "i64 max+1");
    wantI64("-9223372036854775808", I64_MIN, "i64 min boundary ok");
    nullI64("-9223372036854775809", "i64 min-1");

    wantU64("18446744073709551615", U64_MAX, "u64 max boundary ok");
    nullU64("18446744073709551616", "u64 max+1");

    // ---- round-trips + buffer-end writes -----------------------------------
    var buf: [64]u8 = undefined;
    var i32s = [_]i32{ 0, 1, -1, 42, -42, 1000, -1000, 2147483647, I32_MIN };
    var i: usize = 0;
    while (i < i32s.len) : (i += 1) {
        fillSentinel(buf[0..]);
        var r = parse.itoa(buf[0..], i32s[i]);
        checkTail(buf[0..], r, "itoa tail");
        var back = parse.parseInt(r);
        if (back) |b| {
            ck(b == i32s[i], "itoa roundtrip");
        } else {
            ck(false, "itoa roundtrip parse");
        }
    }

    var u32s = [_]u32{ 0, 1, 42, 1000, 4294967295, 4294967294 };
    i = 0;
    while (i < u32s.len) : (i += 1) {
        fillSentinel(buf[0..]);
        var r = parse.utoa(buf[0..], u32s[i]);
        checkTail(buf[0..], r, "utoa tail");
        var back = parse.parseUint(r);
        if (back) |b| {
            ck(b == u32s[i], "utoa roundtrip");
        } else {
            ck(false, "utoa roundtrip parse");
        }
    }

    var i64s = [_]i64{ 0, 1, -1, 42, -42, 9223372036854775807, I64_MIN };
    i = 0;
    while (i < i64s.len) : (i += 1) {
        fillSentinel(buf[0..]);
        var r = parse.itoa64(buf[0..], i64s[i]);
        checkTail(buf[0..], r, "itoa64 tail");
        var back = parse.parseInt64(r);
        if (back) |b| {
            ck(b == i64s[i], "itoa64 roundtrip");
        } else {
            ck(false, "itoa64 roundtrip parse");
        }
    }

    var u64s = [_]u64{ 0, 1, 42, 1000, U64_MAX, U64_MAX - 1 };
    i = 0;
    while (i < u64s.len) : (i += 1) {
        fillSentinel(buf[0..]);
        var r = parse.utoa64(buf[0..], u64s[i]);
        checkTail(buf[0..], r, "utoa64 tail");
        var back = parse.parseUint64(r);
        if (back) |b| {
            ck(b == u64s[i], "utoa64 roundtrip");
        } else {
            ck(false, "utoa64 roundtrip parse");
        }
    }

    // explicit buffer-end pins
    fillSentinel(buf[0..]);
    var rr = parse.itoa(buf[0..], 42);
    ckBytes(rr, "42", "itoa 42 text");
    ck(buf[63] == '2', "itoa last byte is units digit");
    ck(buf[62] == '4', "itoa second-last is tens digit");
    fillSentinel(buf[0..]);
    rr = parse.itoa(buf[0..], -42);
    ckBytes(rr, "-42", "itoa -42 text");
    ck(buf[63] == '2' and buf[62] == '4' and buf[61] == '-', "itoa -42 tail");

    // ---- ftoa --------------------------------------------------------------
    var fbuf: [400]u8 = undefined;
    fillSentinel(fbuf[0..]);
    var fr = parse.ftoa(fbuf[0..], 123.456, 2);
    ckBytes(fr, "123.46", "ftoa 123.46");
    checkTail(fbuf[0..], fr, "ftoa tail");

    fillSentinel(fbuf[0..]);
    fr = parse.ftoa(fbuf[0..], -1.25, 1);
    ckBytes(fr, "-1.3", "ftoa -1.3");
    checkTail(fbuf[0..], fr, "ftoa neg tail");

    fillSentinel(fbuf[0..]);
    fr = parse.ftoa(fbuf[0..], 9.99, 1);
    ckBytes(fr, "10.0", "ftoa carry");
    checkTail(fbuf[0..], fr, "ftoa carry tail");

    fillSentinel(fbuf[0..]);
    fr = parse.ftoa(fbuf[0..], 1.0, 20);
    ck(fr.len == 19, "ftoa precision clamp length");
    ck(fr[0] == '1' and fr[1] == '.', "ftoa precision clamp text");

    // non-finite: total
    var inf: f64 = 1.0;
    var k: u32 = 0;
    while (k < 400) : (k += 1) inf = inf * 10.0;
    var nan: f64 = inf - inf;
    fr = parse.ftoa(fbuf[0..], inf, 2);
    ckBytes(fr, "inf", "ftoa inf");
    fr = parse.ftoa(fbuf[0..], -inf, 2);
    ckBytes(fr, "-inf", "ftoa -inf");
    fr = parse.ftoa(fbuf[0..], nan, 2);
    ckBytes(fr, "nan", "ftoa nan");

    // short buffer: empty result, writes nothing
    var tiny: [4]u8 = undefined;
    fillSentinel(tiny[0..]);
    fr = parse.ftoa(tiny[0..], 123.456, 2);
    ck(fr.len == 0, "ftoa short empty");
    i = 0;
    while (i < 4) : (i += 1) {
        ck(tiny[i] == 0xAA, "ftoa short untouched");
    }

    if (g_fail == 0) {
        std.io.write("parse stress ok\n");
    } else {
        std.io.write("parse stress FAIL\n");
    }
}
