// fnptr_opt_aggregate_emit_xmod — D1 emit-ordering shape (T0 fixture, red
// before any fix). Plan: docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md
// Spec: docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md §2 bug 2.
// Defect: examples/torrent_example_defects.md "D1", reproducer B.
//
// Merely DEFINING `contract.Console` (fn-pointer field `readKey_fn: fn (*void)
// ?Key`, never assembling a literal) makes the frontend accept (dump rc 0) but
// the emitted C89 is invalid: the fn-pointer typedef is emitted before (or
// without) the optional-of-aggregate typedef it references —
// `zig_special_types.h:663: expected declaration specifiers or '...' before '*'
// token` / `unknown type name 'zT_..._FP_zT_..._Opt_'`. A D8-class typedef
// ordering/dispatch gap for `optional_type` (`c89_emit.zig` per-kind dispatch
// or `typeHasForwardDecl` edge suppression — T2 pins which).
//
// GREEN contract (post-T2, for the fixing task to capture as goldens):
// stdout `fnptr emit ok\n`, rc 0, deterministic 3x — every emitted `.c`
// compiles clean with the binding gcc flag-set (which is also what flips the
// corpus class FAIL -> OK on this new fixture; recorded, not a pre-existing
// mover). RED pre-fix: dump rc 0, gcc `-c` of the emitted headers/sources
// fails (exact evidence in NOTES.md). No runtime golden is measurable pre-fix
// (the build dies in gcc) — the zT_missing_fwd_xmod defect-repro shape.
const std = @import("std");
const con = @import("contract.zig");

var g_c: *con.Console = undefined;

pub fn main() void {
    _ = g_c;
    std.io.write("fnptr emit ok\n");
}
