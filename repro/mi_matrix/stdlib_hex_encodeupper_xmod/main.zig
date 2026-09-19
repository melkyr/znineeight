// stdlib_hex_encodeupper_xmod — STDLIB std_hex (L5) encodeUpper GREEN fixture.
//
// std_hex.zig is an L5 module that imports only std_arena (L1) and allocates
// its output from the caller's arena (R1). This fixture imports it by module
// basename (the compiler's lib search path binds <exe>/lib/std_hex.zig).
//
// Format pinned: uppercase hexadecimal, two characters per input byte, high
// nybble first, alphabet 0-9 A-F. encodeUpper emits no whitespace or newlines.
//
// Cases: empty; 0x00; 0x0F; 0xF0; 0xFF; 0xDEADBEEF; "hello"; and all 256 byte
// values 0x00..0xFF in ascending order.
//
// GREEN (contract): deterministic byte-exact stdout `hex encodeUpper ok\n`
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
    var got = hex.encodeUpper(ar, src) catch {
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
    encIs(&ar, b1[0..], "0F", "0x0F");
    var b2: [1]u8 = [_]u8{0xF0};
    encIs(&ar, b2[0..], "F0", "0xF0");
    var b3: [1]u8 = [_]u8{0xFF};
    encIs(&ar, b3[0..], "FF", "0xFF");
    var w: [4]u8 = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    encIs(&ar, w[0..], "DEADBEEF", "0xDEADBEEF");
    encIs(&ar, "hello", "68656C6C6F", "hello");

    var all: [256]u8 = undefined;
    var i: usize = 0;
    while (i < all.len) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    var want_all: []const u8 = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F606162636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F808182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9FA0A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBFC0C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDFE0E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF";
    encIs(&ar, all[0..], want_all, "all256");

    if (g_fail == 0) {
        std.io.write("hex encodeUpper ok\n");
    } else {
        std.io.write("hex encodeUpper FAIL\n");
    }
}
