// const_rodata_gate/runtime_shapes.zig — M2 T1C-F nm-gate probe (`.bss` class).
//
// These must stay `.bss` (`nm` `B`/`b`/`C` — never `R`/`r`):
//   rs_nonconst  non-constant const initializer (runtime value)
//   rs_undef     `undefined`-init const (zero-filled, not a value)
//   rs_union     STOP-1 non-first-member union const (not a C89 constant
//                initializer — the `.bss` fallback keeps correct values)
//   rs_var       plain `var` (unchanged by the fix)
// And `__module_init` must still store rs_nonconst / rs_union (values).
const std = @import("std");

const U1 = union { a: u32, b: u8 };

var rs_seed: u32 = 4;
const rs_nonconst: u32 = rs_seed + 1;
const rs_undef: u32 = undefined;
const rs_union = U1{ .b = 5 };
var rs_var: u32 = 2;

pub fn main() void {
    rs_var = rs_var + 1;
    std.io.print("{d} {d} {d}\n", .{ rs_nonconst, rs_var, @intCast(u32, rs_union.b) });
}
