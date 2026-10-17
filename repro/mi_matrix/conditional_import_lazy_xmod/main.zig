// conditional_import_lazy_xmod — §4/C1b: true Zig laziness for dead-arm
// `@import` (Amendment 2). Plan: docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md
// Spec: docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md §4.
//
// An untaken arm's `@import` NEVER loads its file — Zig never opens it, so a
// missing file behind a comptime-dead condition must produce NO error
// (`error[3048]` is a live-arm-only diagnostic), and the dead file must not be
// parse-registered or emitted. Both conditional forms pin it:
//
//   const lazy_if = if (false) @import("missing.zig") else @import("real.zig");
//   const lazy_sw = switch (false) {
//       true => @import("missing.zig"),
//       else => @import("real.zig"),
//   };
//
// `missing.zig` deliberately does not exist in this directory.
//
// GREEN contract (post-C1b): dump rc 0 with NO error[3048]; only `real_*`
// (plus `std_io_*`/support) emitted; stdout `real ping\nreal ping\ncond import
// lazy ok\n`, rc 0, deterministic 3x. RED record (pre-C1b) in NOTES.md +
// expected_error.txt (the compile rejects on `missing.zig`).
const std = @import("std");
const lazy_if = if (false) @import("missing.zig") else @import("real.zig");
const lazy_sw = switch (false) {
    true => @import("missing.zig"),
    else => @import("real.zig"),
};

pub fn main() void {
    lazy_if.ping();
    lazy_sw.ping();
    std.io.write("cond import lazy ok\n");
}
