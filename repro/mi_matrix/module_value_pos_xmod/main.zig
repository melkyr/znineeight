// module_value_pos_xmod — MINIMAL repro: nested module alias in value position.
//
// `std.async` is `pub const async = @import("std_async.zig")` in `std.zig`, i.e.
// a module alias that is itself a member of a module. Reading a scalar `pub
// const` through it (`std.async.HEADER_SIZE`) is a value-position access whose
// base is a NESTED module reference.
//
// GREEN (Task 2a-F, fixed point 43d41bfb903d56c153ebf653131aef6d): `n == 16`;
// dump rc=0, 5 `.c`, gcc -m32 -std=c89 clean, link+run rc=0, no stdout.
// Was RED at 286c9011691ccd39403534019baa12c6: error[3042]: non-value base
// expression in field access + warning[3023]: module used as value expression,
// dump rc=2, 0 `.c` (corpus classifier ICE).
// Fix: `sf/src/lower.zig` field_access now resolves a nested module-alias base
// (or module-typed global) to its owning module and emits the member
// (`resolveModuleBase` + `lowerModuleMemberValue`), mirroring the direct-module
// ident path. Tasks 2/4/5 read `std.async.HEADER_SIZE`.
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
