// if_expr_unreachable_xmod — RED->GREEN fixture for if-expression divergence
// (A2I Q4: both arms materialize+assign unguarded; the noreturn arm leaks
// `block_terminated` and the outer `return` is skipped).
//
// `const x = if (b) 7 else unreachable;` with `b = true`. RED: the function
// emits no return (x is dead), so `f(true)` yields garbage/0. GREEN: 7.
//
// GREEN (contract): deterministic byte-exact stdout `7\n` (rc 0).
const std = @import("std");

fn f(b: bool) i32 {
    const x = if (b) 7 else unreachable;
    return x;
}

pub fn main() void {
    std.io.printInt(f(true));
    std.io.writeByte('\n');
}
