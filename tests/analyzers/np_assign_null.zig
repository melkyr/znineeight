// np_assign_null.zig — Task 9b NP-3 fixture (assignment RHS walk).
//
// Assignment RHS expressions are walked through `analyzeExpr`; `p` is
// definitely null, so `q = p.*` is ERR_2004_DEFINITE_NULL_DEREF.
fn np_assign_null() void {
    var p: *u32 = null;
    var q: u32 = 0;
    q = p.*;
}

pub fn main() void {
    np_assign_null();
}
