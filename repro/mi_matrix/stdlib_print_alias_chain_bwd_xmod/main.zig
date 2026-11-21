// stdlib_print_alias_chain_bwd_xmod — Task 9 fix round 4 (review Finding 1):
// a backward same-module literal-const alias chain.
//
// `const s = 5; const s2 = s;` are declared before `var g = .{ s2, 7 }`, so
// `s2` is the first global lowered in `__module_init` (temp 0). The literal
// fold of `s` reported "no fold" through the sentinel value 0, was dropped,
// and the emitted C loaded the skipped (never-declared) literal const: gcc
// `error: 'zG_..._s' undeclared` with rc 0 and 7 `.c` on the fix-round-3
// compiler (the backward order was broken before Task 9 as well).
//
// GREEN contract (rc 0, 3x byte-exact, byte-identical to the Zig-0.15.2
// `std.debug.print` twin): exactly one line
//   g=.{ 5, 7 }
const std = @import("std");

const s = 5;
const s2 = s;
var g = .{ s2, 7 };

pub fn main() void {
    std.io.print("g={}\n", .{g});
}
