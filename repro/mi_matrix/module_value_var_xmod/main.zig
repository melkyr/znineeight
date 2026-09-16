// module_value_var_xmod — `pub var` READ via a 2-level module alias.
//
// `mid.leaf.counter` is a `pub var` global read through a nested module alias.
// The value path lowers the base as a value and fails.
//
// RED (current, fixed point 286c9011691ccd39403534019baa12c6):
//   error[3042]: non-value base expression in field access
//   warning[3023]: module used as value expression
//   dump rc=2, 0 `.c`. Corpus classifier: ICE (`error[3042]`).
// (The STORE counterpart is pinned separately in module_value_varstore_xmod,
// where the l-value path yields `error[3043]` instead.)
//
// Expected GREEN contract: `v == 5`; dump rc=0, gcc clean, link+run rc=0,
// no stdout.
const mid = @import("mid.zig");

pub fn main() void {
    var v: i32 = mid.leaf.counter;
    if (v != 5) {
        @panic("module_value_var_xmod: counter mismatch");
    }
}
