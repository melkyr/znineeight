// stdlib_os_env_xmod — STDLIB std_os (L1) env unset/set GREEN fixture.
//
// Contract (blueprint §3 L1): env(name) ?[]const u8; null if unset, empty
// slice for a variable set to the empty string. env wraps the portable CRT
// getenv (no allocation): the returned slice aliases the environment block.
//
// The fixture runs in a normal shell environment, so PATH is set. The unset
// probe uses a deliberately improbable name. (No setenv exists, so the
// "set to empty string" branch cannot be constructed portably here; the null
// vs. non-null distinction is what is pinned.)
//
// GREEN (contract): deterministic byte-exact stdout `os env ok\n` (RUNRC=0).
const std = @import("std");
const os = @import("std_os.zig");

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    // Unset: a name that no sane environment defines returns null.
    var missing = os.env("Z98_STDLIB_OS_ENV_UNSET_9F3A");
    ck(missing == null, "unset name -> null");

    // Set: PATH is present in the fixture run environment; non-null, non-empty.
    var path = os.env("PATH");
    ck(path != null, "PATH set");
    if (path) |v| {
        ck(v.len > 0, "PATH non-empty");
        // The slice aliases the environment block (readable, NUL-free).
        ck(v[0] != 0, "PATH no leading NUL");
    }

    // A too-long name is rejected without reading past the caller's slice.
    var long_name: []const u8 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    ck(os.env(long_name) == null, "over-long name -> null");

    // std.zig re-export smoke check.
    ck(std.os.env("Z98_STDLIB_OS_ENV_UNSET_9F3A") == null, "std.os re-export");

    if (g_fail == 0) {
        std.io.write("os env ok\n");
    } else {
        std.io.write("os env FAIL\n");
    }
}
