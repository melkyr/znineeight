// if_expr_unreachable_xmod — RED->GREEN fixture for if-expression divergence
// (A2I Q4: both arms materialize+assign unguarded; the noreturn arm leaks
// `block_terminated` and the outer `return` is skipped).
//
// `const x = if (b) 7 else unreachable;` with `b = true` (valid then-prong).
// RED and GREEN print identical runtime output `7\n` (rc 0): the valid prong
// never reaches the unreachable arm, so this is NOT catchable by the run-gate.
// The defect is emit-level — RED's unreachable arm emits a dangling
// `zT_2 = b;` instead of `pal_trap();`; GREEN replaces it with `pal_trap();`.
// Detectable only by emitted-C inspection.
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
