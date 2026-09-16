// null_opt_manyptr_arg_xmod — Task 0o pin (pre-existing strtod null-optional).
//
// A statically-null `?[*]const c_char` argument to an extern fn whose real C
// prototype (`<stdlib.h>` `strtod`) declares the parameter as `char**`. Before
// Task 0o the lowering ABI-unwrapped the null optional into a payload-typed
// `char*` temp and passed it, so gcc warned:
//
//   char* zT_2;
//   zT_4.has_value = 0;
//   zT_2 = zT_4.has_value ? zT_4.value : NULL;
//   strtod(zT_1, zT_2);   // warning: passing argument 2 of 'strtod'
//
// After Task 0o the null optional is emitted as a C null pointer constant of
// the generic void-pointer type, so the call is `strtod(zT_1, (void*)(NULL))`
// and gcc is clean. No string literal is used for the `nptr` argument, so this
// fixture is independent of the Task 0p `string_const` decay (it warns 0 times
// both before and after 0p).
//
// Contract: gcc-clean, link rc=0, run rc=0, stdout `1`.
@cInclude("<stdlib.h>");
extern fn strtod(nptr: [*]const c_char, endptr: ?[*]const c_char) f64;
const std = @import("std");

pub fn main() void {
    var buf: [8]u8 = undefined;
    buf[0] = '3';
    buf[1] = '.';
    buf[2] = '5';
    buf[3] = 0;
    var v: f64 = strtod(@ptrCast([*]const c_char, &buf[0]), null);
    if (v > 3.4 and v < 3.6) {
        std.io.printInt(@intCast(i32, 1));
    } else {
        std.io.printInt(@intCast(i32, 0));
    }
    std.io.writeByte('\n');
}
