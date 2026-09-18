// stdlib_str_splitlines_xmod — std_str.splitLines (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `splitLines(arena, s) ![][]const u8` splits on
// '\n' and strips a single trailing '\r' from each segment (CRLF-aware). Like
// `split`, segments are views into `s`; only the outer array allocates.
//
// Cases pinned:
//   "a\nb\nc"     -> 3 parts "a" "b" "c"
//   "a\nb\n"      -> 3 parts "a" "b" ""   (trailing newline => trailing empty)
//   "a\r\nb\r\n"  -> 2 parts "a" "b"      (CR stripped)
//   ""            -> 1 part  ""
//   "a\n\nb"      -> 3 parts "a" "" "b"   (blank line)
//   "a\r\nb"      -> 2 parts "a" "b"
//   "a\rb"        -> 1 part  "a\rb"       (lone CR is NOT a line break)
//
// GREEN (contract): deterministic byte-exact stdout `str splitlines ok\n`.
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

    var s1: []const u8 = "a\nb\nc";
    var p1 = std.str.splitLines(&ar, s1) catch {
        @panic("splitLines lf");
    };
    ck(p1.len == 3, "lf count");
    ck(eq(p1[0], "a") and eq(p1[1], "b") and eq(p1[2], "c"), "lf parts");

    var s2: []const u8 = "a\nb\n";
    var p2 = std.str.splitLines(&ar, s2) catch {
        @panic("splitLines trailing");
    };
    ck(p2.len == 3, "trailing count");
    ck(eq(p2[2], ""), "trailing empty");

    var s3: []const u8 = "a\r\nb\r\n";
    var p3 = std.str.splitLines(&ar, s3) catch {
        @panic("splitLines crlf");
    };
    ck(p3.len == 3, "crlf count");
    ck(eq(p3[0], "a") and eq(p3[1], "b") and eq(p3[2], ""), "crlf stripped");

    var s4: []const u8 = "";
    var p4 = std.str.splitLines(&ar, s4) catch {
        @panic("splitLines empty");
    };
    ck(p4.len == 1 and eq(p4[0], ""), "empty");

    var s5: []const u8 = "a\n\nb";
    var p5 = std.str.splitLines(&ar, s5) catch {
        @panic("splitLines blank");
    };
    ck(p5.len == 3 and eq(p5[1], ""), "blank line");

    var s6: []const u8 = "a\r\nb";
    var p6 = std.str.splitLines(&ar, s6) catch {
        @panic("splitLines mixed");
    };
    ck(p6.len == 2 and eq(p6[0], "a") and eq(p6[1], "b"), "mixed");

    var s7: []const u8 = "a\rb";
    var p7 = std.str.splitLines(&ar, s7) catch {
        @panic("splitLines lone cr");
    };
    ck(p7.len == 1 and eq(p7[0], "a\rb"), "lone cr retained");

    std.io.write("str splitlines ok\n");
}
