// stdlib_debug_cleartrap_xmod — STDLIB std_debug null-uninstall GREEN fixture.
//
// R7 coverage for the null-uninstall path of `setTrapHandler`. Installs a
// handler, clears it via `setTrapHandler(null)`, re-installs the handler, then
// triggers a real trap; the handler prints the contract line and exits 0
// (pal_abort is never reached). The null-install call is exercised end-to-end
// (the setter extern is invoked with a null function pointer). The
// abort-after-clear consequence cannot be a GREEN run (it terminates the
// process); it is proven by a scratch probe recorded in the Task 4 fix report.
//
// Plan A Task 4c: `clearTrapHandler` was dropped (non-blueprint) once Task 4b-F
// made the blueprint's `?fn(*TrapContext) void` signature lower correctly;
// `setTrapHandler(null)` is the null-uninstall.
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
    std.debug.setTrapHandler(null);
    std.debug.setTrapHandler(handler);
    std.debug.assert(false);
}
