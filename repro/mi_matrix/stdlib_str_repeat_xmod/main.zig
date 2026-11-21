// stdlib_str_repeat_xmod — std_str.repeat (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `repeat(arena, s, n) ![]u8` allocates the result
// of concatenating `s` with itself `n` times. n == 0 or an empty `s` yields a
// zero-length result.
//
// Cases pinned:
//   ("ab", 3) -> "ababab"
//   ("ab", 0) -> ""   (len 0)
//   ("",   5) -> ""   (len 0)
//   ("x",  1) -> "x"
//   ("a",  4) -> "aaaa"
//
// GREEN (contract): deterministic byte-exact stdout `str repeat ok\n`.
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

    var s1: []const u8 = "ab";
    var r1 = std.str.repeat(&ar, s1, 3) catch {
        @panic("repeat ab");
    };
    ck(eq(r1, "ababab"), "ab x3");

    var r2 = std.str.repeat(&ar, s1, 0) catch {
        @panic("repeat zero");
    };
    ck(r2.len == 0, "zero times");

    var s2: []const u8 = "";
    var r3 = std.str.repeat(&ar, s2, 5) catch {
        @panic("repeat empty");
    };
    ck(r3.len == 0, "empty source");

    var s3: []const u8 = "x";
    var r4 = std.str.repeat(&ar, s3, 1) catch {
        @panic("repeat once");
    };
    ck(eq(r4, "x"), "once");

    var s4: []const u8 = "a";
    var r5 = std.str.repeat(&ar, s4, 4) catch {
        @panic("repeat a");
    };
    ck(eq(r5, "aaaa"), "a x4");

    std.io.write("str repeat ok\n");
}
