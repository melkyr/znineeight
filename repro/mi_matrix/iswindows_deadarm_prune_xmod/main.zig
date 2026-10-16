// iswindows_deadarm_prune_xmod — D2 emission-pruning fixture with a PRE-FIX
// runtime golden (T0 fixture). Plan: docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md
// Spec: docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md §3.
//
// Same dead-arm error-union reference shape as iswindows_deadarm_errunion_xmod,
// but the two dependency modules are host-neutral (no `@cInclude`), so the
// current compiler builds and runs the program — the red defect is purely the
// EMISSION of the comptime-dead module (`windep_*.c` present in the output dir
// on a linux build; measured in NOTES.md), and the runtime behavior the fix
// must preserve is frozen in expected.txt/expected.rc (measured from the
// pre-fix compiler). This is also why corpus classify classifies this fixture
// OK both pre- and post-fix (classification compares CLASS files, not emitted C)
// — the T3 verification for this fixture is the golden match PLUS the emission
// contract: `windep_*.c` ABSENT from the output dir after T3.
//
// GREEN contract (post-T3): stdout `iswindows prune ok\n`, rc 0 (same golden —
// preserved), and `ls <out>/windep_*.c` empty on a linux build / `ls
// <out>/linuxdep_*.c` empty on an `-osw` build. Also cross-buildable both ways.
const std = @import("std");
const windep = @import("windep.zig");
const linuxdep = @import("linuxdep.zig");

pub fn main() void {
    var ctx: *void = undefined;
    if (@isWindows()) {
        ctx = windep.open(44100, 2) catch return;
    } else {
        ctx = linuxdep.open(44100, 2) catch return;
    }
    _ = ctx;
    std.io.write("iswindows prune ok\n");
}
