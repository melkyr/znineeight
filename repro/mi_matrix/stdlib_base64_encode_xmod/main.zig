// stdlib_base64_encode_xmod — STDLIB std_base64 (L5) encode GREEN fixture.
//
// std_base64.zig is an L5 module that imports only std_arena (L1) and allocates
// its output from the caller's arena (R1). This fixture imports it by module
// basename (the compiler's lib search path binds <exe>/lib/std_base64.zig).
//
// Format pinned: RFC 4648 §4 standard base64 — alphabet
//   A-Z a-z 0-9 + /
// with mandatory '=' padding out to a multiple of 4 output characters. encode
// never emits whitespace or newlines.
//
// Cases: the RFC 4648 §10 vectors (empty, "f", "fo", "foo", "foob", "fooba",
// "foobar"); the single-byte edge values 0x00 and 0xFF; the 0xDEADBEEF word;
// and all 256 byte values 0x00..0xFF in ascending order.
//
// GREEN (contract): deterministic byte-exact stdout `base64 encode ok\n`
// (RUNRC=0).
const std = @import("std");
const b64 = @import("std_base64.zig");

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
    var got = b64.encode(ar, src) catch {
        @panic(what);
    };
    ck(got.len == b64.encodedLen(src.len), what);
    ckBytes(got, want, what);
}

pub fn main() void {
    var backing: [65536]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    var empty: []const u8 = "";
    encIs(&ar, empty, "", "empty");
    encIs(&ar, "f", "Zg==", "f");
    encIs(&ar, "fo", "Zm8=", "fo");
    encIs(&ar, "foo", "Zm9v", "foo");
    encIs(&ar, "foob", "Zm9vYg==", "foob");
    encIs(&ar, "fooba", "Zm9vYmE=", "fooba");
    encIs(&ar, "foobar", "Zm9vYmFy", "foobar");

    var z: [1]u8 = [_]u8{0x00};
    encIs(&ar, z[0..], "AA==", "0x00");
    var f: [1]u8 = [_]u8{0xFF};
    encIs(&ar, f[0..], "/w==", "0xFF");
    var w: [4]u8 = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    encIs(&ar, w[0..], "3q2+7w==", "0xDEADBEEF");

    var all: [256]u8 = undefined;
    var i: usize = 0;
    while (i < all.len) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    var want_all: []const u8 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/w==";
    encIs(&ar, all[0..], want_all, "all256");

    if (g_fail == 0) {
        std.io.write("base64 encode ok\n");
    } else {
        std.io.write("base64 encode FAIL\n");
    }
}
