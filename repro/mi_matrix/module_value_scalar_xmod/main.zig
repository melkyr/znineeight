// module_value_scalar_xmod — scalar `pub const` via a 2-level module alias.
//
// `mid.leaf.HEADER_SIZE`: `mid` is a module, `leaf` is `pub const leaf =
// @import("leaf.zig")` (a nested module alias), `HEADER_SIZE` is a scalar
// `pub const` in `leaf`. Fixture-local (no std dependency) so the construct is
// isolated from the std search path.
//
// RED (current, fixed point 286c9011691ccd39403534019baa12c6):
//   error[3042]: non-value base expression in field access
//   warning[3023]: module used as value expression
//   dump rc=2, 0 `.c`. Corpus classifier: ICE (`error[3042]`).
//
// Expected GREEN contract: `n == 16`; dump rc=0, gcc clean, link+run rc=0,
// no stdout.
const mid = @import("mid.zig");

pub fn main() void {
    var n: usize = mid.leaf.HEADER_SIZE;
    if (n != 16) {
        @panic("module_value_scalar_xmod: HEADER_SIZE mismatch");
    }
}
