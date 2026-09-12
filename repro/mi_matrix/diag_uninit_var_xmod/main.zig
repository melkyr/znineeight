// diag_uninit_var_xmod — compile-time diagnostic: uninitialized variable.
// Contract (GREEN): `var x: i32;` without an initializer is an ERROR
//   (error[3014]), dump rc=2, 0 emitted .c. Zig-faithful: real Zig requires
//   initialization; `var x: i32 = undefined;` is the explicit escape (control
//   fixture).
// RED (today, pre-A7F): silently accepted, emits C and runs (prints 5).
const std = @import("std");

pub fn main() void {
    var x: i32;
    x = 5;
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
