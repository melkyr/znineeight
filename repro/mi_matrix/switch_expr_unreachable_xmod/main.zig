// switch_expr_unreachable_xmod — RED->GREEN fixture for the switch-expression
// `block_terminated` leak (A2I Q4; operator-approved A2F scope).
//
// `return switch (c) { 0 => 1, else => unreachable }` puts a switch EXPRESSION
// in direct-return position. The switch-expr lowering (lower.zig) restores
// `current_bb = exit_bb` but did NOT reset `block_terminated`, so the noreturn
// else-prong's flag leaked out; the outer `return_stmt` then skipped the `ret`
// and emitter DCE removed the prong assigns. RED: `f` emits no return (the
// valid `0 => 1` prong also loses its return). GREEN: `f(0)` returns 1.
//
// GREEN (contract): deterministic byte-exact stdout `1\n` (rc 0).
const std = @import("std");

fn f(c: u8) i32 {
    return switch (c) {
        0 => 1,
        else => unreachable,
    };
}

pub fn main() void {
    std.io.printInt(f(0));
    std.io.writeByte('\n');
}
