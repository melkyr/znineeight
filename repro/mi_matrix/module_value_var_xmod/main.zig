// module_value_var_xmod — `pub var` READ via a 2-level module alias.
//
// `mid.leaf.counter` is a `pub var` global read through a nested module alias.
// The value path lowers the base as a value and fails.
//
// GREEN (Task 2a-F, fixed point 43d41bfb903d56c153ebf653131aef6d): `v == 5`;
// dump rc=0, 5 `.c`, gcc clean, link+run rc=0, no stdout.
// Was RED at 286c9011691ccd39403534019baa12c6: error[3042] + warning[3023],
// dump rc=2, 0 `.c` (corpus classifier ICE).
// (The STORE counterpart is pinned separately in module_value_varstore_xmod.)
const mid = @import("mid.zig");

pub fn main() void {
    var v: i32 = mid.leaf.counter;
    if (v != 5) {
        @panic("module_value_var_xmod: counter mismatch");
    }
}
