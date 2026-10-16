// conditional_import_if_xmod — §4 conditional `@import`, if/else form (T0
// fixture, red before any fix). Plan: docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md
// Spec: docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md §4.
//
// `const impl = if (@isWindows()) @import("a.zig") else @import("b.zig");`
// must resolve to the LIVE module (the Zig idiom; z9play M6 wants exactly this
// shape for per-platform backends). Pre-fix the if-expression over two
// `import_expr`s yields `void` (`import_expr` is only handled at
// decl/member positions), so `impl.ping()` is invalid (exact red evidence in
// NOTES.md).
//
// GREEN contract (post-T4): on a linux build stdout `b ping\ncond import if ok\n`,
// on an `-osw` build stdout `a ping\ncond import if ok\n`; rc 0, deterministic
// 3x; only the live module is resolved/emitted. The linux golden below is the
// T0 pre-fix-measured contract where measurable (see NOTES.md for the red
// state — where the pre-fix frontend rejects, the goldens are the post-fix
// contract captured by the fixing task, zT_missing_fwd_xmod shape).
const std = @import("std");
const impl = if (@isWindows()) @import("a.zig") else @import("b.zig");

pub fn main() void {
    impl.ping();
    std.io.write("cond import if ok\n");
}
