// stdlib_str_trim_xmod — std_str.trim (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `trim(s)` strips ASCII whitespace from both ends
// and returns a view into `s`. The ASCII whitespace set is 0x09..0x0D
// (TAB/LF/VT/FF/CR) plus 0x20 (SPACE).
//
// Cases pinned:
//   "  hi  "      -> "hi"
//   "\t\nhi\r\n"  -> "hi"
//   "hi"          -> "hi"
//   "   "         -> ""
//   ""            -> ""
//   " a b "       -> "a b"   (inner spaces kept)
//   "\v\fhi\v\f"  -> "hi"    (VT/FF are whitespace)
//
// GREEN (contract): deterministic byte-exact stdout `str trim ok\n`.
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

fn eq(a: []const u8, b: []const u8) bool {
    return std.str.eql(a, b);
}

pub fn main() void {
    var s1: []const u8 = "  hi  ";
    ck(eq(std.str.trim(s1), "hi"), "spaces");

    var s2: []const u8 = "\t\nhi\r\n";
    ck(eq(std.str.trim(s2), "hi"), "tab/nl/cr");

    var s3: []const u8 = "hi";
    ck(eq(std.str.trim(s3), "hi"), "no-op");

    var s4: []const u8 = "   ";
    ck(eq(std.str.trim(s4), ""), "all space");

    var s5: []const u8 = "";
    ck(eq(std.str.trim(s5), ""), "empty");

    var s6: []const u8 = " a b ";
    ck(eq(std.str.trim(s6), "a b"), "inner kept");

    // Z98 has no \v/\f string escapes, so VT (0x0B) / FF (0x0C) are built as
    // raw bytes; trim must still strip them as ASCII whitespace.
    var raw7: [6]u8 = undefined;
    raw7[0] = 11;
    raw7[1] = 12;
    raw7[2] = 'h';
    raw7[3] = 'i';
    raw7[4] = 11;
    raw7[5] = 12;
    var s7: []const u8 = raw7[0..];
    ck(eq(std.str.trim(s7), "hi"), "vt/ff");

    std.io.write("str trim ok\n");
}
