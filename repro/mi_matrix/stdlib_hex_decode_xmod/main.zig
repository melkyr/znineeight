// stdlib_hex_decode_xmod — STDLIB std_hex (L5) decode GREEN fixture.
//
// std_hex.zig is an L5 module that imports only std_arena (L1) and allocates
// its output from the caller's arena (R1). This fixture imports it by module
// basename (the compiler's lib search path binds <exe>/lib/std_hex.zig).
//
// Format pinned: hexadecimal, two characters per output byte, high nybble
// first, case-insensitive alphabet 0-9 a-f A-F.
//
// WHITESPACE / INVALID-INPUT POLICY (pinned here): decode does NOT skip
// whitespace. Any byte outside the hex alphabet — space, tab, CR, LF, or any
// other byte — or an odd length makes the whole input invalid and returns
// `error.InvalidInput` (contract error set: OutOfMemory, InvalidInput; operator
// ruling m1842). An empty input is a VALID empty result (a length-0 slice, no
// error), distinct from an invalid one.
//
// Cases: lowercase/uppercase/mixed-case vectors; 0x00/0x0F/0xF0/0xFF;
// 0xDEADBEEF; "hello"; all 256 byte values (both cases); odd-length rejection;
// non-hex byte rejection; whitespace rejection.
//
// GREEN (contract): deterministic byte-exact stdout `hex decode ok\n`
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

fn decIs(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    var got = hex.decode(ar, src) catch {
        @panic(what);
    };
    ckBytes(got, want, what);
}

fn decInvalid(ar: *std.arena.Arena, src: []const u8, what: []const u8) void {
    var got = hex.decode(ar, src) catch |e| {
        ck(e == error.InvalidInput, what);
        return;
    };
    _ = got;
    ck(false, what);
}

pub fn main() void {
    var backing: [131072]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var empty: []const u8 = "";
    decIs(&ar, empty, "", "empty");

    var b0: [1]u8 = [_]u8{0x00};
    decIs(&ar, "00", b0[0..], "0x00");
    var b1: [1]u8 = [_]u8{0x0F};
    decIs(&ar, "0f", b1[0..], "0x0f lower");
    decIs(&ar, "0F", b1[0..], "0x0F upper");
    var b2: [1]u8 = [_]u8{0xF0};
    decIs(&ar, "f0", b2[0..], "0xf0 lower");
    decIs(&ar, "F0", b2[0..], "0xF0 upper");
    var b3: [1]u8 = [_]u8{0xFF};
    decIs(&ar, "ff", b3[0..], "0xff lower");
    decIs(&ar, "FF", b3[0..], "0xFF upper");

    var w: [4]u8 = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    decIs(&ar, "deadbeef", w[0..], "deadbeef");
    decIs(&ar, "DEADBEEF", w[0..], "DEADBEEF");
    decIs(&ar, "DeAdBeEf", w[0..], "DeAdBeEf");
    decIs(&ar, "68656c6c6f", "hello", "hello");

    var all: [256]u8 = undefined;
    var i: usize = 0;
    while (i < all.len) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    var lo_all: []const u8 = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff";
    var up_all: []const u8 = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F202122232425262728292A2B2C2D2E2F303132333435363738393A3B3C3D3E3F404142434445464748494A4B4C4D4E4F505152535455565758595A5B5C5D5E5F606162636465666768696A6B6C6D6E6F707172737475767778797A7B7C7D7E7F808182838485868788898A8B8C8D8E8F909192939495969798999A9B9C9D9E9FA0A1A2A3A4A5A6A7A8A9AAABACADAEAFB0B1B2B3B4B5B6B7B8B9BABBBCBDBEBFC0C1C2C3C4C5C6C7C8C9CACBCCCDCECFD0D1D2D3D4D5D6D7D8D9DADBDCDDDEDFE0E1E2E3E4E5E6E7E8E9EAEBECEDEEEFF0F1F2F3F4F5F6F7F8F9FAFBFCFDFEFF";
    decIs(&ar, lo_all, all[0..], "all256 lower");
    decIs(&ar, up_all, all[0..], "all256 upper");

    decInvalid(&ar, "0", "reject odd 1");
    decInvalid(&ar, "abc", "reject odd 3");
    decInvalid(&ar, "deadbee", "reject odd 7");

    decInvalid(&ar, "0g", "reject g");
    decInvalid(&ar, "zz", "reject z");
    decInvalid(&ar, "de ad", "reject embedded space");
    decInvalid(&ar, "deadbeef\n", "reject trailing newline");
    decInvalid(&ar, " deadbeef", "reject leading space");
    decInvalid(&ar, "dead\tbeef", "reject embedded tab");
    decInvalid(&ar, "0x00", "reject 0x prefix");
    decInvalid(&ar, "-1", "reject minus");

    if (g_fail == 0) {
        std.io.write("hex decode ok\n");
    } else {
        std.io.write("hex decode FAIL\n");
    }
}
