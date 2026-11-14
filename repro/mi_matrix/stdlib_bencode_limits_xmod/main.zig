// stdlib_bencode_limits_xmod — STDLIB std_bencode (M0 §4.2) limit/error
// contract.
//
// Feeds the mandated malformed inputs and prints the BencodeError name each
// returns:
//   i04e                          -> InvalidToken  (leading zero)
//   i-0e                          -> InvalidToken  (negative zero)
//   i99999999999999999999e        -> Overflow      (i64 overflow)
//   d1:ai1e1:ai2ee                -> DuplicateKey  (duplicate `a`)
//   101-deep list                 -> TooDeep       (nesting cap 100)
//   5:ab                          -> InvalidToken  (length > remaining input)
//
// GREEN: deterministic byte-exact stdout (RUNRC=0):
//   i04e: InvalidToken
//   i-0e: InvalidToken
//   i99999999999999999999e: Overflow
//   duplicate-key: DuplicateKey
//   deep-101: TooDeep
//   short-string: InvalidToken
//   limits ok
const std = @import("std");
const ben = @import("std_bencode.zig");

fn errName(e: ben.BencodeError) []const u8 {
    if (e == error.InvalidToken) {
        var v: []const u8 = "InvalidToken";
        return v;
    }
    if (e == error.Overflow) {
        var v: []const u8 = "Overflow";
        return v;
    }
    if (e == error.TooDeep) {
        var v: []const u8 = "TooDeep";
        return v;
    }
    if (e == error.TooLarge) {
        var v: []const u8 = "TooLarge";
        return v;
    }
    if (e == error.DuplicateKey) {
        var v: []const u8 = "DuplicateKey";
        return v;
    }
    if (e == error.OutOfMemory) {
        var v: []const u8 = "OutOfMemory";
        return v;
    }
    var u: []const u8 = "Unknown";
    return u;
}

fn expectErr(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    const v = ben.decode(ar, src) catch |e| {
        const got = errName(e);
        if (!eqBytes(got, want)) @panic(what);
        std.io.write(got);
        std.io.write("\n");
        return;
    };
    _ = v;
    @panic(what);
}

fn eqBytes(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

pub fn main() void {
    var backing: [4096]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var s1: []const u8 = "i04e";
    std.io.write("i04e: ");
    expectErr(&ar, s1, "InvalidToken", "i04e");

    var s2: []const u8 = "i-0e";
    std.io.write("i-0e: ");
    expectErr(&ar, s2, "InvalidToken", "i-0e");

    var s3: []const u8 = "i99999999999999999999e";
    std.io.write("i99999999999999999999e: ");
    expectErr(&ar, s3, "Overflow", "overflow");

    var s4: []const u8 = "d1:ai1e1:ai2ee";
    std.io.write("duplicate-key: ");
    expectErr(&ar, s4, "DuplicateKey", "dup");

    var buf: [256]u8 = undefined;
    var i: usize = 0;
    while (i < 101) : (i += 1) {
        buf[i] = 'l';
    }
    i = 0;
    while (i < 101) : (i += 1) {
        buf[101 + i] = 'e';
    }
    var deep: []const u8 = buf[0..202];
    std.io.write("deep-101: ");
    expectErr(&ar, deep, "TooDeep", "deep");

    var s6: []const u8 = "5:ab";
    std.io.write("short-string: ");
    expectErr(&ar, s6, "InvalidToken", "short");

    std.io.write("limits ok\n");
}
