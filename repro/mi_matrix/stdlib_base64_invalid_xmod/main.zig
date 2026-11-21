// stdlib_base64_invalid_xmod — STDLIB std_base64 (L5) invalid-input
// expected-failure probe (Plan C hardening Task 3).
//
// Contract (sf/src/std_base64.zig:21-27,102-129): `decode` accepts only
// canonical padded RFC 4648 base64. Any byte outside the alphabet (space, tab,
// CR, LF, or any other), a length that is not a multiple of 4, or
// misplaced/malformed '=' is rejected with exactly `error.InvalidInput`; the
// call allocates nothing (`arena.used` unchanged). An empty input is a VALID
// empty result and is NOT an invalid one.
//
// This probe drives the documented invalid-input channel: every malformed input
// MUST report `error.InvalidInput` and leave the arena untouched. A decode that
// returns a slice, reports `error.OutOfMemory`, or grows the arena FAILS the
// probe. The failure is reported in-process, so the process exits cleanly
// (rc 0) on the expected path.
//
// GREEN (contract): deterministic byte-exact stdout `base64 invalid ok\n` (rc 0).
const std = @import("std");
const b64 = @import("std_base64.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

fn invalid(ar: *std.arena.Arena, src: []const u8, what: []const u8) void {
    var used_before = ar.used;
    var got = b64.decode(ar, src) catch |e| {
        ck(e == error.InvalidInput, what);
        ck(ar.used == used_before, what);
        return;
    };
    _ = got;
    ck(false, what);
}

fn validEmpty(ar: *std.arena.Arena, what: []const u8) void {
    var empty: []const u8 = "";
    var got = b64.decode(ar, empty) catch {
        @panic(what);
    };
    ck(got.len == 0, what);
}

pub fn main() void {
    var backing: [4096]u8 = undefined;
    var ar = std.arena.init(backing[0..]);

    // Empty is valid, not invalid (pins the boundary).
    validEmpty(&ar, "empty valid");

    // Non-alphabet bytes (whitespace + punctuation).
    invalid(&ar, "Zm9v\n", "trailing newline");
    invalid(&ar, "Zm9v ", "trailing space");
    invalid(&ar, "Zm 9", "embedded space");
    invalid(&ar, "Zm9\t", "trailing tab");
    invalid(&ar, "\rZm9v", "leading cr");
    invalid(&ar, "Zm9v\r\n", "crlf");
    invalid(&ar, "Zm9!", "bang");
    invalid(&ar, "Zm9-", "dash");
    invalid(&ar, "Zm9_", "underscore");
    invalid(&ar, "Zm9.", "dot");

    // Wrong length (not a multiple of 4).
    invalid(&ar, "Z", "len1");
    invalid(&ar, "Zm9", "len3");
    invalid(&ar, "Zm9vY", "len5");

    // Misplaced / malformed '='.
    invalid(&ar, "====", "all pad");
    invalid(&ar, "=m9v", "leading pad");
    invalid(&ar, "Zg=Z", "pad then data");
    invalid(&ar, "Zg==Zg==", "pad in non-final quad");
    invalid(&ar, "Zm=v", "pad in slot3");
    invalid(&ar, "Z===", "three pad");
    invalid(&ar, "Zm9v=", "stray pad");

    if (g_fail == 0) {
        std.io.write("base64 invalid ok\n");
    } else {
        std.io.write("base64 invalid FAIL\n");
    }
}
