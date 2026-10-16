// iswindows_deadarm_errunion_xmod — D2 faithful repro (T0 fixture, red before
// any fix). Plan: docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md
// Spec: docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md §3.
// Defect: examples/torrent_example_defects.md "D2", minimal reproducer
// (weaponized, both directions).
//
// Each platform module is referenced ONLY from the opposite-comptime arm of
// `if (@isWindows())`. The referenced fn returns an error union (the D2
// trigger — non-error-union references in the same dead arm are already
// pruned). On a linux build the `@isWindows()` true arm is comptime-dead, yet
// the dead `errdep`/`windep` edge survives LIR and the emitter's module-
// reachability scan marks the wrong-platform module reachable: it is emitted
// and its platform-only `@cInclude` breaks the host gcc. Symmetric on `-osw`
// (the dead else arm emits linuxdep with `<sys/ioctl.h>` into a mingw build).
//
// GREEN contract (post-T3): wrong-platform module NOT emitted (`ls <out>/windep_*.c`
// empty on a linux build, `ls <out>/linuxdep_*.c` empty on an `-osw` build);
// the live module builds; stdout `iswindows deadarm ok\n`, rc 0, deterministic
// 3x (goldens to be captured by the fixing task — no runtime golden is
// measurable pre-fix because the host gcc dies on the wrong-platform include;
// zT_missing_fwd_xmod defect-repro shape). RED pre-fix evidence in NOTES.md.
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
    std.io.write("iswindows deadarm ok\n");
}
