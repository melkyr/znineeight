// module_value_pos_xmod — MINIMAL repro: nested module alias in value position.
//
// `std.async` is `pub const async = @import("std_async.zig")` in `std.zig`, i.e.
// a module alias that is itself a member of a module. Reading a scalar `pub
// const` through it (`std.async.HEADER_SIZE`) is a value-position access whose
// base is a NESTED module reference.
//
// RED (current, fixed point 286c9011691ccd39403534019baa12c6):
//   error[3042]: non-value base expression in field access
//   warning[3023]: module used as value expression
//   dump rc=2, 0 `.c`. Corpus classifier: `error[3042]` => ICE (QUICK_REF.md).
// Root: `sf/src/lower.zig` field_access lowers the base as a value; a nested
// module alias is not recognized as a module reference (only a DIRECT module
// ident is, at lower.zig:3400-3416 / sema semantic_analyzer.zig:659).
//
// Expected GREEN contract: `n == 16`; dump rc=0, gcc -m32 -std=c89 clean,
// link+run rc=0, no stdout. Tasks 2/4/5 read `std.async.HEADER_SIZE`.
//
// Reference: deferred as "Amendment 7, Res 4" in
// docs/superpowers/specs/2026-09-13-async-prelude-and-feasibility-design.md:474.
const std = @import("std");

pub fn main() void {
    var n: usize = std.async.HEADER_SIZE;
    if (n != 16) {
        @panic("module_value_pos_xmod: HEADER_SIZE mismatch");
    }
}
