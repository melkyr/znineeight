// module_value_alias3_xmod — 3-level module alias in value position.
//
// `mid2.mid.leaf.HEADER_SIZE`: two nested module aliases (`mid2.mid`, then
// `.leaf`) before the member. Confirms the gap is per-nesting-level, not a
// single-alias special case.
//
// GREEN (Task 2a-F, fixed point 43d41bfb903d56c153ebf653131aef6d): `n == 16`;
// dump rc=0, 5 `.c`, gcc clean, link+run rc=0, no stdout.
// Was RED at 286c9011691ccd39403534019baa12c6: error[3042] + warning[3023],
// dump rc=2, 0 `.c` (corpus classifier ICE).
const mid2 = @import("mid2.zig");

pub fn main() void {
    var n: usize = mid2.mid.leaf.HEADER_SIZE;
    if (n != 16) {
        @panic("module_value_alias3_xmod: HEADER_SIZE mismatch");
    }
}
