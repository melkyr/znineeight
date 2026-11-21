// stdlib_str_split_xmod — std_str.split (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `split(arena, s, sep) ![][]const u8` returns
// slices INTO `s` (not copies); the only allocation is the outer array. A
// trailing separator yields a trailing empty segment, and an empty `s` yields
// exactly one empty segment. The slice-aliasing half of the contract is pinned
// separately in stdlib_str_split_alias_xmod.
//
// Cases pinned (all against the canonical <exe>/lib std module, bare
// `@import("std")`):
//   "a,b,c"   sep ',' -> 3 parts "a" "b" "c"
//   "a,,b"    sep ',' -> 3 parts "a" ""  "b"   (empty middle segment)
//   ",a,"     sep ',' -> 3 parts ""  "a" ""    (leading + trailing empty)
//   "abc"     sep ',' -> 1 part  "abc"         (no separator)
//   ""        sep ',' -> 1 part  ""            (empty input)
//   "aaaa"    sep 'a' -> 5 parts all empty     (separator-only input)
//
// GREEN (contract): deterministic byte-exact stdout `str split ok\n` (RUNRC=0).
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.str.eql(a, b);
}

pub fn main() void {
    var backing: [1024]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var s1: []const u8 = "a,b,c";
    var p1 = std.str.split(&ar, s1, ',') catch {
        @panic("split a,b,c");
    };
    ck(p1.len == 3, "a,b,c count");
    ck(eq(p1[0], "a"), "a,b,c p0");
    ck(eq(p1[1], "b"), "a,b,c p1");
    ck(eq(p1[2], "c"), "a,b,c p2");

    var s2: []const u8 = "a,,b";
    var p2 = std.str.split(&ar, s2, ',') catch {
        @panic("split a,,b");
    };
    ck(p2.len == 3, "a,,b count");
    ck(eq(p2[0], "a"), "a,,b p0");
    ck(eq(p2[1], ""), "a,,b p1 empty");
    ck(eq(p2[2], "b"), "a,,b p2");

    var s3: []const u8 = ",a,";
    var p3 = std.str.split(&ar, s3, ',') catch {
        @panic("split ,a,");
    };
    ck(p3.len == 3, ",a, count");
    ck(eq(p3[0], ""), ",a, p0 empty");
    ck(eq(p3[1], "a"), ",a, p1");
    ck(eq(p3[2], ""), ",a, p2 empty");

    var s4: []const u8 = "abc";
    var p4 = std.str.split(&ar, s4, ',') catch {
        @panic("split abc");
    };
    ck(p4.len == 1, "abc count");
    ck(eq(p4[0], "abc"), "abc p0");

    var s5: []const u8 = "";
    var p5 = std.str.split(&ar, s5, ',') catch {
        @panic("split empty");
    };
    ck(p5.len == 1, "empty count");
    ck(eq(p5[0], ""), "empty p0");

    var s6: []const u8 = "aaaa";
    var p6 = std.str.split(&ar, s6, 'a') catch {
        @panic("split aaaa");
    };
    ck(p6.len == 5, "aaaa count");
    ck(eq(p6[0], "") and eq(p6[4], ""), "aaaa empties");

    std.io.write("str split ok\n");
}
