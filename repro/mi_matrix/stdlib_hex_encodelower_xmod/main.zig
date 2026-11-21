// stdlib_hex_encodelower_xmod — STDLIB std_hex (L5) encodeLower GREEN fixture.
//
// std_hex.zig is an L5 module that imports only std_arena (L1) and allocates
// its output from the caller's arena (R1). This fixture imports it by module
// basename (the compiler's lib search path binds <exe>/lib/std_hex.zig).
//
// Format pinned: lowercase hexadecimal, two characters per input byte, high
// nybble first, alphabet 0-9 a-f. encodeLower emits no whitespace or newlines.
//
// Cases: empty; 0x00; 0x0F; 0xF0; 0xFF; 0xDEADBEEF; "hello"; and all 256 byte
// values 0x00..0xFF in ascending order.
//
// GREEN (contract): deterministic byte-exact stdout `hex encodeLower ok\n`
// (RUNRC=0).
const std = @import("std");
const hex = @import("std_hex.zig");

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

fn encIs(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    var got = hex.encodeLower(ar, src) catch {
        @panic(what);
    };
    ck(got.len == src.len * 2, what);
    ckBytes(got, want, what);
}

pub fn main() void {
    var backing: [65536]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var empty: []const u8 = "";
    encIs(&ar, empty, "", "empty");

    var b0: [1]u8 = [_]u8{0x00};
    encIs(&ar, b0[0..], "00", "0x00");
    var b1: [1]u8 = [_]u8{0x0F};
    encIs(&ar, b1[0..], "0f", "0x0F");
    var b2: [1]u8 = [_]u8{0xF0};
    encIs(&ar, b2[0..], "f0", "0xF0");
    var b3: [1]u8 = [_]u8{0xFF};
    encIs(&ar, b3[0..], "ff", "0xFF");
    var w: [4]u8 = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    encIs(&ar, w[0..], "deadbeef", "0xDEADBEEF");
    encIs(&ar, "hello", "68656c6c6f", "hello");

    var all: [256]u8 = undefined;
    var i: usize = 0;
    while (i < all.len) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    var want_all: []const u8 = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff";
    encIs(&ar, all[0..], want_all, "all256");

    if (g_fail == 0) {
        std.io.write("hex encodeLower ok\n");
    } else {
        std.io.write("hex encodeLower FAIL\n");
    }
}
