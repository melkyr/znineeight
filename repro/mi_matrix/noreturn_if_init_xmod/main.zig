// noreturn_if_init_xmod — A19 value-position fixture (inferred initializer).
// Both if_expr shapes are noreturn-valued (every arm diverges via `return`):
//   * non-block arms: `const x = if (c) return 1 else return 2;`
//   * block arms:     `const y = if (c) { return 3; } else { return 4; };`
// The resolver accepts them (A7F reachability); lowering must treat them as
// divergence constructs — arms emit their own terminators, the enclosing block
// is terminated, and no noreturn result temp is materialized (no unknown-type
// C). The `_ = x` bindings exercise the unreachable local.
// Contract (GREEN): compiles + runs, prints "1\n2\n3\n4\n".
const std = @import("std");

fn viaIfExpr(c: bool) i32 {
    const x = if (c) return 1 else return 2;
    _ = x;
}

fn viaIfExprBlock(c: bool) i32 {
    const y = if (c) {
        return 3;
    } else {
        return 4;
    };
    _ = y;
}

pub fn main() void {
    std.io.printInt(@intCast(i32, viaIfExpr(true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaIfExpr(false)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaIfExprBlock(true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaIfExprBlock(false)));
    std.io.writeByte('\n');
}
