// stdlib_str_replace_xmod — std_str.replace (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `replace(arena, s, from, to) ![]u8` replaces every
// NON-OVERLAPPING occurrence of `from` with `to` and allocates the result only.
// An empty `from` performs no replacement (returns a copy of `s`). `from` and
// `to` may alias `s`: the result is a fresh allocation and `s` is only read.
//
// Cases pinned:
//   ("a-b-c", "-", "+")     -> "a+b+c"
//   ("hello", "l", "L")     -> "heLLo"
//   ("aaa",   "aa", "b")    -> "ba"      (non-overlapping, leftmost-first)
//   ("abc",   "x", "y")     -> "abc"
//   ("abc",   "", "X")      -> "abc"     (empty from => unchanged)
//   ("abc",   "abc", "")    -> ""        (deletion)
//   ("abcabc","abc", "x")   -> "xx"
//   ("a",     "a", "xyz")   -> "xyz"     (growth)
//   ("",      "a", "b")     -> ""
//   aliasing: src="abc", from=src[0..1]="a", to=src[2..3]="c" -> "cbc"
//
// GREEN (contract): deterministic byte-exact stdout `str replace ok\n`.
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

    var s1: []const u8 = "a-b-c";
    var r1 = std.str.replace(&ar, s1, "-", "+") catch {
        @panic("replace a-b-c");
    };
    ck(eq(r1, "a+b+c"), "a-b-c");

    var s2: []const u8 = "hello";
    var r2 = std.str.replace(&ar, s2, "l", "L") catch {
        @panic("replace hello");
    };
    ck(eq(r2, "heLLo"), "hello");

    var s3: []const u8 = "aaa";
    var r3 = std.str.replace(&ar, s3, "aa", "b") catch {
        @panic("replace aaa");
    };
    ck(eq(r3, "ba"), "non-overlapping");

    var s4: []const u8 = "abc";
    var r4 = std.str.replace(&ar, s4, "x", "y") catch {
        @panic("replace no match");
    };
    ck(eq(r4, "abc"), "no match");

    var r5 = std.str.replace(&ar, s4, "", "X") catch {
        @panic("replace empty from");
    };
    ck(eq(r5, "abc"), "empty from");

    var r6 = std.str.replace(&ar, s4, "abc", "") catch {
        @panic("replace delete");
    };
    ck(r6.len == 0, "delete");

    var s7: []const u8 = "abcabc";
    var r7 = std.str.replace(&ar, s7, "abc", "x") catch {
        @panic("replace twice");
    };
    ck(eq(r7, "xx"), "two occurrences");

    var s8: []const u8 = "a";
    var r8 = std.str.replace(&ar, s8, "a", "xyz") catch {
        @panic("replace grow");
    };
    ck(eq(r8, "xyz"), "growth");

    var s9: []const u8 = "";
    var r9 = std.str.replace(&ar, s9, "a", "b") catch {
        @panic("replace empty");
    };
    ck(r9.len == 0, "empty input");

    // from/to alias s: the source is read-only; the result is a fresh buffer.
    var src: [3]u8 = undefined;
    std.str.copy(src[0..], "abc");
    var ra = std.str.replace(&ar, src[0..], src[0..1], src[2..3]) catch {
        @panic("replace alias");
    };
    ck(eq(ra, "cbc"), "alias from/to");

    std.io.write("str replace ok\n");
}
