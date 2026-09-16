// module_value_alias3_xmod — 3-level module alias in value position.
//
// `mid2.mid.leaf.HEADER_SIZE`: two nested module aliases (`mid2.mid`, then
// `.leaf`) before the member. Confirms the gap is per-nesting-level, not a
// single-alias special case.
//
// RED (current, fixed point 286c9011691ccd39403534019baa12c6):
//   error[3042]: non-value base expression in field access
//   warning[3023]: module used as value expression
//   dump rc=2, 0 `.c`. Corpus classifier: ICE (`error[3042]`).
//
// Expected GREEN contract: `n == 16`; dump rc=0, gcc clean, link+run rc=0,
// no stdout.
const mid2 = @import("mid2.zig");

pub fn main() void {
    var n: usize = mid2.mid.leaf.HEADER_SIZE;
    if (n != 16) {
        @panic("module_value_alias3_xmod: HEADER_SIZE mismatch");
    }
}
