// stdlib_str_xmod — STDLIB std_str byte-string helpers GREEN fixture.
//
// std_str.zig is a PURE (no externs, no cstdio) Z98 module re-exported from
// std.zig as `str`; this fixture imports it via a BARE `@import("std")` (lib
// search path binds the canonical <exe>/lib std module) and exercises every
// public function of the module: len / eql / copy / copyZ / findChar /
// startsWith / endsWith / toUpper / toLower.
//
// SHIPPED COMPILER FEATURES pinned alongside the module:
//   - optional return ?usize from findChar + `orelse` fallback
//   - `for` loop over a []const u8 slice with element payload capture
//   - slice len / mutable-slice element indexing / []u8 -> []const u8 coercion
//   - `and` boolean short-circuit, negative-literal i32
//
// GREEN (contract): deterministic byte-exact stdout below (RUNRC=0), one
// result per line (numeric via std.io.printInt + '\n', byte strings via
// std.io.write + '\n'):
//   11          len("Hello, Z98!")
//   1           eql(a, b) — equal
//   0           eql(a, c) — last char differs
//   0           eql(a, d) — length differs
//   1           copy(buf[0..], a) then eql(buf, a)
//   1           copy bounds-safe no-op: 11 > 4 leaves dst sentinels intact
//   11          copyZ returns copied length
//   1           copyZ NUL-terminates at dst[len]
//   1           copyZ payload equals a
//   4           findChar(a, 'o') first index
//   10          findChar(a, '!') last char index
//   99          findChar(a, 'q') orelse 99 (optional + orelse)
//   1           startsWith(a, "Hello")
//   0           startsWith(a, "Hellx")
//   0           startsWith("Hi", "Hello") — prefix longer than s
//   1           endsWith(a, "Z98!")
//   0           endsWith(a, "Z98?")
//   ABC1Z!      toUpper("aBc1z!") in place (non-alpha untouched)
//   1           eql(upper result, "ABC1Z!")
//   abc1z!      toLower(result) in place
//   1           eql(lower result, "abc1z!")
//   2           for-over-slice count of 'l' in a
const std = @import("std");

fn p(v: i32) void {
    std.io.printInt(v);
    std.io.writeByte('\n');
}

fn pb(cond: bool) void {
    if (cond) {
        p(1);
    } else {
        p(0);
    }
}

pub fn main() void {
    var a: []const u8 = "Hello, Z98!";
    var b: []const u8 = "Hello, Z98!";
    var c: []const u8 = "Hello, Z98?";
    var d: []const u8 = "Hello";

    p(@intCast(i32, std.str.len(a)));

    pb(std.str.eql(a, b));
    pb(std.str.eql(a, c));
    pb(std.str.eql(a, d));

    var buf: [11]u8 = undefined;
    std.str.copy(buf[0..], a);
    pb(std.str.eql(buf[0..], a));

    var small: [4]u8 = undefined;
    small[0] = 'x';
    small[1] = 'x';
    small[2] = 'x';
    small[3] = 'x';
    std.str.copy(small[0..], a);
    pb(small[0] == 'x' and small[3] == 'x');

    var zbuf: [16]u8 = undefined;
    var zl = std.str.copyZ(&zbuf[0], a);
    p(@intCast(i32, zl));
    pb(zbuf[11] == 0);
    pb(std.str.eql(zbuf[0..11], a));

    p(@intCast(i32, std.str.findChar(a, 'o') orelse 88));
    p(@intCast(i32, std.str.findChar(a, '!') orelse 88));
    p(@intCast(i32, std.str.findChar(a, 'q') orelse 99));

    pb(std.str.startsWith(a, d));
    var hellx: []const u8 = "Hellx";
    pb(std.str.startsWith(a, hellx));
    var hi: []const u8 = "Hi";
    pb(std.str.startsWith(hi, d));

    var tail_ok: []const u8 = "Z98!";
    var tail_no: []const u8 = "Z98?";
    pb(std.str.endsWith(a, tail_ok));
    pb(std.str.endsWith(a, tail_no));

    var su: []const u8 = "aBc1z!";
    var up: [6]u8 = undefined;
    std.str.copy(up[0..], su);
    std.str.toUpper(up[0..]);
    std.io.write(up[0..]);
    std.io.writeByte('\n');
    var eu: []const u8 = "ABC1Z!";
    pb(std.str.eql(up[0..], eu));
    std.str.toLower(up[0..]);
    std.io.write(up[0..]);
    std.io.writeByte('\n');
    var el: []const u8 = "abc1z!";
    pb(std.str.eql(up[0..], el));

    var nl: i32 = 0;
    for (a) |ch| {
        if (ch == 'l') {
            nl += 1;
        }
    }
    p(nl);
}
