// diag_missing_return_expr_ok_xmod — control fixture for the A7F review-fix:
// the missing-return reachability predicate must accept expression-position
// control flow as a terminating tail:
//   * `const x: T = if (c) { return a; } else { return b; };`
//     (both branches return; the declaration's initializer is noreturn);
//   * `while (true) { return v; }` (literal-true condition, terminating body,
//     no reachable `break`).
// It must NOT accept `while (true)` that can `break` out (see the sibling
// reject fixtures); the break scan is conservative (any break disqualifies).
// Contract (GREEN): compiles + runs, prints "1\n2\n3\n".
// Note: the `noreturn` initializer also trips the pre-existing lenient
// `warning[3000]` coercion notice (noreturn -> declared type); it is not an
// error and predates this predicate fix (the form used to be hard-rejected).
const std = @import("std");

fn viaIfExpr(c: bool) i32 {
    const x: i32 = if (c) {
        return 1;
    } else {
        return 2;
    };
    _ = x;
}

fn viaWhileTrue() i32 {
    while (true) {
        return 3;
    }
}

pub fn main() void {
    std.io.printInt(@intCast(i32, viaIfExpr(true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaIfExpr(false)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaWhileTrue()));
    std.io.writeByte('\n');
}
