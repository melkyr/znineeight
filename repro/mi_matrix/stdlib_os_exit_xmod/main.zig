// stdlib_os_exit_xmod — STDLIB std_os (L1) exit-code expected-failure probe
// (Plan A hardening Task 3).
//
// Contract (sf/src/std_os.zig:61-64): exit(code) calls @exit(code) and never
// returns, so the process terminates with the exact code passed in.
//
// This probe is the missing expected-failure assertion: it calls
// std_os.exit(42) and pins rc 42 with empty stdout. The trailing write is only
// reached if exit silently returns, which makes the probe FAIL visibly with
// rc 0 and non-empty stdout.
const std = @import("std");
const os = @import("std_os.zig");

pub fn main() void {
    std.os.exit(42);
    std.io.write("std_os.exit no-exit FAIL\n");
}
