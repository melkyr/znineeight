// module_member_missing_reject_xmod — missing member on a module alias.
//
// `h` is a direct module symbol; `nope` is absent. Before Task 3b the lowerer
// returned TEMP_NONE, fell through to `lowerExpr`, and reported
//   error[3042]: non-value base expression in field access
// plus `warning[3023]: module used as value expression` -- a misleading pair
// for a missing member. Task 3b-R diagnoses it in the semantic analyzer at
// level 0 with
//   no field or member function named 'nope' in module
// so lowering never runs: rc 2, 0 `.c`, one error[3060] per site, no 3042/3023.
//
// Positions covered: read, call, store, address, and nested module chain.
const h = @import("helper.zig");

pub fn main() void {
    _ = h.nope;
    h.nope();
    h.nope = 1;
    const p = &h.nope;
    _ = h.sub.nope;
}
