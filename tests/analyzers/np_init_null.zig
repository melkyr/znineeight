// np_init_null.zig — Task 9b NP-3 fixture (var initializer walk).
//
// `var` initializers are walked through `analyzeExpr`; `p` is definitely null,
// so `var q: u32 = p.*` is ERR_2004_DEFINITE_NULL_DEREF.
fn np_init_null() u32 {
    var p: *u32 = null;
    var q: u32 = p.*;
    return q;
}

pub fn main() void {
    _ = np_init_null();
}
