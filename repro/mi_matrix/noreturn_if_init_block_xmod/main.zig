// noreturn_if_init_block_xmod — A19 control fixture: the annotated if_expr
// initializer shapes that already lowered correctly before A19 must keep
// working byte-for-byte at runtime:
//   * annotated block-arm:     `const x: i32 = if (c) { return 1; } else { return 2; };`
//   * annotated non-block:     `const y: i32 = if (c) return 3 else return 4;`
// The annotation overwrites the expression's resolved type to i32, so these
// are not the divergence path, but their bare/block `return` arms must still
// emit their terminators.
// Contract (GREEN): compiles + runs, prints "1\n2\n3\n4\n".
const std = @import("std");

fn viaBlockAnnotated(c: bool) i32 {
    const x: i32 = if (c) {
        return 1;
    } else {
        return 2;
    };
    _ = x;
}

fn viaExprAnnotated(c: bool) i32 {
    const y: i32 = if (c) return 3 else return 4;
    _ = y;
}

pub fn main() void {
    std.io.printInt(@intCast(i32, viaBlockAnnotated(true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaBlockAnnotated(false)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaExprAnnotated(true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaExprAnnotated(false)));
    std.io.writeByte('\n');
}
