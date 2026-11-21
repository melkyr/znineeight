// conditional_import_switch_xmod — §4 conditional `@import`, switch form (T0
// fixture, red before any fix). Plan: docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md
// Spec: docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md §4
// ("and the `switch` form").
//
// `const impl = switch (@isWindows()) { true => @import("a.zig"), else => @import("b.zig") };`
// must resolve to the LIVE module exactly like the if/else form
// (conditional_import_if_xmod). The `true`/`else` spelling is used because
// Z98's switch rejects an exhaustive bool prong set without `else`
// (`error[3068]`; a separate pre-existing behavior, out of T4 scope — the
// `true`/`false` no-else spelling is recorded in NOTES.md as an observation).
// Pre-fix behavior recorded in NOTES.md.
//
// GREEN contract (post-T4): on a linux build stdout `b ping\ncond import switch ok\n`,
// on an `-osw` build stdout `a ping\ncond import switch ok\n`; rc 0,
// deterministic 3x; only the live module is resolved/emitted.
const std = @import("std");
const impl = switch (@isWindows()) {
    true => @import("a.zig"),
    else => @import("b.zig"),
};

pub fn main() void {
    impl.ping();
    std.io.write("cond import switch ok\n");
}
