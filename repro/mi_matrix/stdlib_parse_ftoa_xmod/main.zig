// stdlib_parse_ftoa_xmod — STDLIB std_parse (L5) ftoa GREEN fixture.
//
// Contract (blueprint §3 L5): ftoa(buf, v, precision) []u8. Writes backwards
// from buf's end; the returned slice points into buf. Fixed-point notation with
// `precision` digits after the decimal point (round half up). Non-finite input
// is total: NaN -> "nan", +inf -> "inf", -inf -> "-inf". A buffer too small for
// the rendered text yields buf[0..0] and writes nothing. No allocation, no
// errors.
//
// GREEN: deterministic stdout `ftoa ok\n` (RUNRC=0).
const std = @import("std");
const parse = @import("std_parse.zig");

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

fn roundTrip(v: f64, p: u8, what: []const u8) void {
    var buf: [64]u8 = undefined;
    var r = parse.ftoa(buf[0..], v, p);
    var back = parse.parseFloat(r);
    if (back) |b| {
        var d = b - v;
        if (d < 0.0) d = -d;
        ck(d < 0.001, what);
    } else {
        ck(false, what);
    }
}

pub fn main() void {
    var buf: [64]u8 = undefined;
    var r: []u8 = undefined;

    r = parse.ftoa(buf[0..], 0.0, 2);
    ckBytes(r, "0.00", "ftoa 0.00");

    r = parse.ftoa(buf[0..], 2.0, 2);
    ckBytes(r, "2.00", "ftoa 2.00");

    r = parse.ftoa(buf[0..], 3.14, 2);
    ckBytes(r, "3.14", "ftoa 3.14");

    r = parse.ftoa(buf[0..], -1.25, 1);
    ckBytes(r, "-1.3", "ftoa -1.3");

    r = parse.ftoa(buf[0..], 3.7, 0);
    ckBytes(r, "4", "ftoa 4");

    r = parse.ftoa(buf[0..], 123.456, 2);
    ckBytes(r, "123.46", "ftoa 123.46");

    r = parse.ftoa(buf[0..], 9.99, 1);
    ckBytes(r, "10.0", "ftoa carry");

    r = parse.ftoa(buf[0..], 0.0, 0);
    ckBytes(r, "0", "ftoa zero p0");

    r = parse.ftoa(buf[0..], 0.25, 2);
    ckBytes(r, "0.25", "ftoa 0.25");
    ck(buf[63] == '5', "ftoa writes from end");

    r = parse.ftoa(buf[0..], 0.5, 0);
    ckBytes(r, "1", "ftoa 0.5 p0");

    r = parse.ftoa(buf[0..], -0.5, 0);
    ckBytes(r, "-1", "ftoa -0.5 p0");

    roundTrip(123.456, 3, "ftoa roundtrip 123.456");
    roundTrip(0.25, 2, "ftoa roundtrip 0.25");
    roundTrip(-42.5, 1, "ftoa roundtrip -42.5");

    // --- non-finite: total (never hangs, never traps) ---
    var inf: f64 = 1.0;
    var k: u32 = 0;
    while (k < 400) : (k += 1) inf = inf * 10.0;
    var nan: f64 = inf - inf;

    r = parse.ftoa(buf[0..], inf, 2);
    ckBytes(r, "inf", "ftoa +inf");
    r = parse.ftoa(buf[0..], -inf, 2);
    ckBytes(r, "-inf", "ftoa -inf");
    r = parse.ftoa(buf[0..], nan, 2);
    ckBytes(r, "nan", "ftoa nan");

    // --- large finite exponent: bounded temps, no OOB ---
    var big: f64 = 1.0;
    k = 0;
    while (k < 300) : (k += 1) big = big * 10.0;
    var bigbuf: [400]u8 = undefined;
    r = parse.ftoa(bigbuf[0..], big, 2);
    ck(r.len >= 300 and r.len <= 310, "ftoa large exponent length bounded");
    ck(r[0] >= '1' and r[0] <= '9', "ftoa large leading digit");
    ck(r[r.len - 3] == '.', "ftoa large point position");

    // --- short buffer: documented empty result, writes nothing ---
    var tiny: [4]u8 = undefined;
    tiny[0] = 'x';
    r = parse.ftoa(tiny[0..], 123.456, 2);
    ck(r.len == 0, "ftoa short buffer empty");
    ck(tiny[0] == 'x', "ftoa short buffer untouched");

    if (g_fail == 0) {
        std.io.write("ftoa ok\n");
    } else {
        std.io.write("ftoa FAIL\n");
    }
}
