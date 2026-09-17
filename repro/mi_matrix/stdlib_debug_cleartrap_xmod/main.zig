// stdlib_debug_cleartrap_xmod — STDLIB std_debug clearTrapHandler GREEN fixture.
//
// R7 coverage for the public `clearTrapHandler()`. Installs a handler, clears
// it, re-installs the handler, then triggers a real trap; the handler prints
// the contract line and exits 0 (pal_abort is never reached). The clear call
// is exercised end-to-end (the setter extern is invoked with NULL). The
// abort-after-clear consequence cannot be a GREEN run (it terminates the
// process); it is proven by a scratch probe recorded in the Task 4 fix report.
//
// Deterministic stdout contract (RUNRC=0):
//   assertion failed
//   clear ok
const std = @import("std");

fn handler(ctx: *std.debug.TrapContext) void {
    _ = ctx;
    var m: []const u8 = "clear ok\n";
    std.debug.log(m);
    std.os.exit(0);
}

pub fn main() void {
    std.debug.setTrapHandler(handler);
    std.debug.clearTrapHandler();
    std.debug.setTrapHandler(handler);
    std.debug.assert(false);
}
