// stdlib_str_split_alias_xmod — std_str.split slice-aliasing contract fixture.
//
// Contract (blueprint §3 L2): `split` returns slices INTO `s`, not copies; the
// only allocation is the outer array. This fixture pins that contract directly:
// split a MUTABLE source, mutate the source bytes afterwards, and observe every
// returned segment change with it. If `split` had copied the segments, the
// post-mutation assertions would fail.
//
// GREEN (contract): deterministic byte-exact stdout `str split alias ok\n`.
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.str.eql(a, b);
}

pub fn main() void {
    var backing: [256]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var src: [5]u8 = undefined;
    std.str.copy(src[0..], "a,b,c");

    var s: []const u8 = src[0..];
    var parts = std.str.split(&ar, s, ',') catch {
        @panic("split mutable");
    };
    ck(parts.len == 3, "alias count");
    ck(eq(parts[0], "a"), "alias pre p0");
    ck(eq(parts[1], "b"), "alias pre p1");
    ck(eq(parts[2], "c"), "alias pre p2");

    // Mutating the source must be visible through the segments: they are views.
    src[0] = 'X';
    src[2] = 'Y';
    src[4] = 'Z';
    ck(eq(parts[0], "X"), "alias post p0");
    ck(eq(parts[1], "Y"), "alias post p1");
    ck(eq(parts[2], "Z"), "alias post p2");
    ck(parts[1].len == 1, "alias p1 len (separator excluded)");

    std.io.write("str split alias ok\n");
}
