// stdlib_print_alias_chain_fwd_xmod — Task 9 fix round 4 (review Finding 1):
// a forward same-module literal-const alias chain.
//
// `g`'s element `s2` is a module const whose own initializer aliases another
// module const (`const s2 = s`, `const s = 5`) declared LATER. The dependency
// order emits `s2`'s store before `g`, so that store allocated the FIRST temp
// of `__module_init` (temp 0). The literal fold of `s` reported "no fold"
// through the sentinel value 0, the fold was dropped, and the emitted C loaded
// the skipped (never-declared) literal const: gcc `error: 'zG_..._s'
// undeclared` with rc 0 and 7 `.c` on the fix-round-3 compiler.
//
// GREEN contract (rc 0, 3x byte-exact, byte-identical to the Zig-0.15.2
// `std.debug.print` twin): exactly one line
//   g=.{ 5, 7 }
const std = @import("std");

var g = .{ s2, 7 };
const s = 5;
const s2 = s;

pub fn main() void {
    std.io.print("g={}\n", .{g});
}
