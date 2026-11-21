// assignment_expr_reject_xmod — A6-F assignment-as-expression reject census.
// Assignment is a statement, not an expression. The original three sites
// (chained `a = b = 2;`, var-initializer `var c: i32 = a = 3;`, `return a = 3;`)
// plus the full sweep (call argument, index, for-range-end) all reject at the
// parser; Z98 wording is error[2000]: expected ';' but found token. rc 2, 0 .c.
// The count includes parserSynchronize recovery diagnostics.
var a: i32 = 0;
var b: i32 = 0;

fn take(v: i32) i32 { return v; }

fn ret() i32 {
    return a = 3;
}

pub fn main() void {
    a = b = 2;
    var c: i32 = a = 3;
    _ = take(a = 3);
    var arr: [3]i32 = [3]i32{1, 2, 3};
    _ = arr[a = 0];
    for (0..a = 3) |i| { _ = i; }
    _ = c;
    _ = ret();
    _ = a;
    _ = b;
}
