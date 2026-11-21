// stdlib_print_alias_chain_scalar_xmod — Task 9 fix round 4 (review Finding
// 1): a scalar use of a same-module literal-const alias chain.
//
// `const s2 = s` (with `const s = 5`) is the first global lowered in
// `__module_init` (temp 0). The literal fold of `s` reported "no fold" through
// the sentinel value 0, was dropped, and the emitted C loaded the skipped
// (never-declared) literal const: gcc `error: 'zG_..._s' undeclared` with
// rc 0 and 7 `.c` on the fix-round-3 compiler.
//
// GREEN contract (rc 0, 3x byte-exact, byte-identical to the Zig-0.15.2
// `std.debug.print` twin): exactly one line
//   s2=5
const std = @import("std");

const s = 5;
const s2 = s;

pub fn main() void {
    std.io.print("s2={}\n", .{s2});
}
