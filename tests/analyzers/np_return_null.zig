// np_return_null.zig — Task 9b NP-2 fixture.
//
// `return` expressions are walked through `analyzeExpr`; `p` is definitely
// null, so `return p.*` is ERR_2004_DEFINITE_NULL_DEREF.
fn np_return_null() u32 {
    var p: *u32 = null;
    return p.*;
}

pub fn main() void {
    _ = np_return_null();
}
