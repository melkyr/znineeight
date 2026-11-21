// stdlib_base64_encodedlen_xmod — STDLIB std_base64 (L5) encodedLen GREEN fixture.
//
// std_base64.zig is an L5 module; encodedLen is a pure size helper that
// allocates nothing (R1). This fixture imports it by module basename.
//
// Contract pinned: encodedLen(n) is the exact number of base64 characters
// produced by encode for an n-byte source, i.e. 4 * ceil(n / 3). It is defined
// for every n and is the value encode(...).len must equal (checked here for
// every length 0..256).
//
// GREEN (contract): deterministic byte-exact stdout `base64 encodedLen ok\n`
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

pub fn main() void {
    ck(b64.encodedLen(0) == 0, "n0");
    ck(b64.encodedLen(1) == 4, "n1");
    ck(b64.encodedLen(2) == 4, "n2");
    ck(b64.encodedLen(3) == 4, "n3");
    ck(b64.encodedLen(4) == 8, "n4");
    ck(b64.encodedLen(5) == 8, "n5");
    ck(b64.encodedLen(6) == 8, "n6");
    ck(b64.encodedLen(7) == 12, "n7");
    ck(b64.encodedLen(8) == 12, "n8");
    ck(b64.encodedLen(9) == 12, "n9");
    ck(b64.encodedLen(10) == 16, "n10");
    ck(b64.encodedLen(100) == 136, "n100");
    ck(b64.encodedLen(300) == 400, "n300");

    var backing: [8192]u8 = undefined;
    var buf: [256]u8 = undefined;
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        buf[i] = @intCast(u8, (i * 7 + 3) % 256);
    }
    var n: usize = 0;
    while (n <= 256) : (n += 1) {
        var ar = std.arena.init(backing[0..]);
        var got = b64.encode(&ar, buf[0..n]) catch {
            @panic("encode");
        };
        ck(got.len == b64.encodedLen(n), "encode matches encodedLen");
    }

    if (g_fail == 0) {
        std.io.write("base64 encodedLen ok\n");
    } else {
        std.io.write("base64 encodedLen FAIL\n");
    }
}
