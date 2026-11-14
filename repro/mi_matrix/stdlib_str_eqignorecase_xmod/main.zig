// stdlib_str_eqignorecase_xmod — std_str.eqIgnoreCase (L2) GREEN fixture.
//
// Contract (blueprint §3 L2): `eqIgnoreCase(a, b) bool` compares two byte
// strings ASCII case-insensitively; non-alphabetic bytes must match exactly.
//
// Cases pinned:
//   ("Hello","hELLo") -> true
//   ("Hello","Hello") -> true
//   ("Hello","Hell")  -> false   (length differs)
//   ("aBc1","AbC1")   -> true
//   ("aBc1","AbC2")   -> false
//   ("","")           -> true
//   ("[","{")         -> false   (non-alpha: 0x5B vs 0x7B; a naive |0x20 fold
//                                 would wrongly report equal)
//   ("A","a")         -> true
//   ("Z","z")         -> true
//   ("abc","abd")     -> false
//
// GREEN (contract): deterministic byte-exact stdout `str eqignorecase ok\n`.
const std = @import("std");

fn ck(cond: bool, what: []const u8) void {
    if (!cond) @panic(what);
}

pub fn main() void {
    var a: []const u8 = "Hello";
    var b: []const u8 = "hELLo";
    ck(std.str.eqIgnoreCase(a, b), "Hello/hELLo");
    ck(std.str.eqIgnoreCase(a, a), "identical");
    ck(!std.str.eqIgnoreCase(a, "Hell"), "length differs");

    var c: []const u8 = "aBc1";
    ck(std.str.eqIgnoreCase(c, "AbC1"), "aBc1/AbC1");
    ck(!std.str.eqIgnoreCase(c, "AbC2"), "aBc1/AbC2");

    var e: []const u8 = "";
    ck(std.str.eqIgnoreCase(e, e), "empty/empty");

    var lb: []const u8 = "[";
    var lc: []const u8 = "{";
    ck(!std.str.eqIgnoreCase(lb, lc), "non-alpha");

    ck(std.str.eqIgnoreCase("A", "a"), "A/a");
    ck(std.str.eqIgnoreCase("Z", "z"), "Z/z");
    ck(!std.str.eqIgnoreCase("abc", "abd"), "abc/abd");

    std.io.write("str eqignorecase ok\n");
}
