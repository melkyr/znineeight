// stdlib_base64_decode_xmod — STDLIB std_base64 (L5) decode GREEN fixture.
//
// std_base64.zig is an L5 module that imports only std_arena (L1) and allocates
// its output from the caller's arena (R1). This fixture imports it by module
// basename (the compiler's lib search path binds <exe>/lib/std_base64.zig).
//
// Format pinned: RFC 4648 §4 standard base64 — alphabet
//   A-Z a-z 0-9 + /
// with mandatory '=' padding out to a multiple of 4 input characters.
//
// WHITESPACE / INVALID-INPUT POLICY (pinned here): decode does NOT skip
// whitespace. Any byte outside the base64 alphabet — space, tab, CR, LF, or any
// other byte — a wrong length, or misplaced/malformed '=' makes the whole input
// invalid and returns `error.InvalidInput` (contract error set:
// OutOfMemory, InvalidInput; operator ruling m1842). An empty input is a VALID
// empty result (a length-0 slice, no error), distinct from an invalid one.
//
// Cases: the RFC 4648 §10 vectors; 0x00/0xFF/0xDEADBEEF; all 256 byte values;
// whitespace rejection (leading, embedded, trailing, CRLF); non-alphabet byte
// rejection; wrong-length rejection; misplaced/malformed '=' rejection.
//
// GREEN (contract): deterministic byte-exact stdout `base64 decode ok\n`
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

fn decIs(ar: *std.arena.Arena, src: []const u8, want: []const u8, what: []const u8) void {
    var got = b64.decode(ar, src) catch {
        @panic(what);
    };
    ckBytes(got, want, what);
}

fn decInvalid(ar: *std.arena.Arena, src: []const u8, what: []const u8) void {
    var got = b64.decode(ar, src) catch |e| {
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
    decIs(&ar, "Zg==", "f", "f");
    decIs(&ar, "Zm8=", "fo", "fo");
    decIs(&ar, "Zm9v", "foo", "foo");
    decIs(&ar, "Zm9vYg==", "foob", "foob");
    decIs(&ar, "Zm9vYmE=", "fooba", "fooba");
    decIs(&ar, "Zm9vYmFy", "foobar", "foobar");

    var b1: [1]u8 = [_]u8{0x00};
    decIs(&ar, "AA==", b1[0..], "0x00");
    var b2: [1]u8 = [_]u8{0xFF};
    decIs(&ar, "/w==", b2[0..], "0xFF");
    var b3: [4]u8 = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    decIs(&ar, "3q2+7w==", b3[0..], "0xDEADBEEF");

    var all: [256]u8 = undefined;
    var i: usize = 0;
    while (i < all.len) : (i += 1) {
        all[i] = @intCast(u8, i);
    }
    var enc_all: []const u8 = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/w==";
    decIs(&ar, enc_all, all[0..], "all256");

    decInvalid(&ar, "Zm9v\n", "reject trailing newline");
    decInvalid(&ar, "Zm9v ", "reject trailing space");
    decInvalid(&ar, "Zm 9", "reject embedded space");
    decInvalid(&ar, "Zm9\t", "reject trailing tab");
    decInvalid(&ar, "\rZm9v", "reject leading cr");
    decInvalid(&ar, "Zm9v\r\n", "reject crlf");

    decInvalid(&ar, "Zm9!", "reject bang");
    decInvalid(&ar, "Zm9-", "reject dash");
    decInvalid(&ar, "Zm9_", "reject underscore");
    decInvalid(&ar, "Zm9.", "reject dot");

    decInvalid(&ar, "Zm9", "reject len3");
    decInvalid(&ar, "Z", "reject len1");
    decInvalid(&ar, "Zm9vY", "reject len5");

    decInvalid(&ar, "====", "reject all pad");
    decInvalid(&ar, "=m9v", "reject leading pad");
    decInvalid(&ar, "Zg=Z", "reject pad then data");
    decInvalid(&ar, "Zg==Zg==", "reject pad in non-final quad");
    decInvalid(&ar, "Zm=v", "reject pad in slot3");
    decInvalid(&ar, "Z===", "reject three pad");
    decInvalid(&ar, "Zm9v=", "reject stray pad");

    if (g_fail == 0) {
        std.io.write("base64 decode ok\n");
    } else {
        std.io.write("base64 decode FAIL\n");
    }
}
