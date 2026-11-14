// module_value_scalar_xmod — scalar `pub const` via a 2-level module alias.
//
// `mid.leaf.HEADER_SIZE`: `mid` is a module, `leaf` is `pub const leaf =
// @import("leaf.zig")` (a nested module alias), `HEADER_SIZE` is a scalar
// `pub const` in `leaf`. Fixture-local (no std dependency) so the construct is
// isolated from the std search path.
//
// GREEN (Task 2a-F, fixed point 43d41bfb903d56c153ebf653131aef6d): `n == 16`;
// dump rc=0, 5 `.c`, gcc clean, link+run rc=0, no stdout.
// Was RED at 286c9011691ccd39403534019baa12c6: error[3042] + warning[3023],
// dump rc=2, 0 `.c` (corpus classifier ICE).
const mid = @import("mid.zig");

pub fn main() void {
    var n: usize = mid.leaf.HEADER_SIZE;
    if (n != 16) {
        @panic("module_value_scalar_xmod: HEADER_SIZE mismatch");
    }
}
