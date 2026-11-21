// stdlib_debug_defaulttrap_xmod — STDLIB std_debug defaultTrapHandler probe.
//
// R7 coverage for the public `defaultTrapHandler(ctx) noreturn`. The function
// writes `core.dump` in the CWD and calls pal_abort() — it never returns, so a
// GREEN run contract is impossible. This dir is dumped/built GREEN and its RUN
// is a documented probe: rc=134 (SIGABRT) after core.dump is written with the
// synthetic context below. Probe evidence (rc + core.dump bytes + cleanup) is
// recorded in the Task 4 fix report.
const std = @import("std");

pub fn main() void {
    var ctx: std.debug.TrapContext = undefined;
    ctx.eip = 4660;
    ctx.esp = 1;
    ctx.ebp = 2;
    ctx.eflags = 3;
    ctx.eax = 4;
    ctx.ebx = 5;
    ctx.ecx = 6;
    ctx.edx = 7;
    ctx.esi = 8;
    ctx.edi = 9;

    // Never returns: writes core.dump then pal_abort().
    std.debug.defaultTrapHandler(&ctx);
}
