// stdlib_debug_trap_xmod — STDLIB std_debug (L1) trap-hook GREEN fixture.
//
// Operator ruling 2026-09-17: the single authorized compiler↔std crossing for
// std_debug is the trap hook. `zig_pal.c` gains `TrapContext`,
// `g_trap_handler` and `pal_set_trap_handler`; `pal_trap()` populates the
// context and calls the installed handler before terminating. `std_debug`
// declares the setter extern and wraps it as `setTrapHandler`.
//
// This fixture installs a handler, triggers a real trap via `assert(false)`,
// and verifies the captured context's `eip` is non-zero. The handler writes
// the deterministic contract line and exits 0 (so the process never reaches
// `pal_abort`); a zero `eip` or a non-invoked handler yields rc != 0.
//
// GREEN (contract): deterministic byte-exact stdout (RUNRC=0):
//   assertion failed
//   debug trap ok
// (`assert(false)` writes the first line before trapping; the handler writes
// the second and exits 0, so pal_abort is never reached.)
const std = @import("std");

// Handler state, written before the exit so the trap path is observable even
// if the handler were ever to return (it must not — pal_abort follows).
var g_handler_ran: i32 = 0;
var g_eip: u32 = 0;

fn trapHandler(ctx: *std.debug.TrapContext) void {
    g_handler_ran = 1;
    g_eip = ctx.eip;

    // eip is the return address of the call into pal_trap — never zero.
    if (ctx.eip != 0) {
        var ok: []const u8 = "debug trap ok\n";
        std.debug.log(ok);
        std.os.exit(0);
    }

    var bad: []const u8 = "debug trap FAIL\n";
    std.debug.log(bad);
    std.os.exit(1);
}

pub fn main() void {
    // Install the handler through the blueprint setter
    // (`?fn(*TrapContext) void`; the extern setter is under the hood).
    std.debug.setTrapHandler(trapHandler);

    // A real trap: assert(false) writes its message then calls pal_trap().
    // The installed handler runs first and exits 0 before pal_abort.
    std.debug.assert(false);

    // Unreachable when the hook works (pal_trap never returns); a diagnostic
    // for a silently-dropped trap.
    if (g_handler_ran == 0) {
        var no: []const u8 = "debug trap FAIL (handler not invoked)\n";
        std.debug.log(no);
        std.os.exit(2);
    }
    if (g_eip == 0) {
        var noe: []const u8 = "debug trap FAIL (eip zero)\n";
        std.debug.log(noe);
        std.os.exit(3);
    }
}
