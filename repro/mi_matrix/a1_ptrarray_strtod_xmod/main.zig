// a1_ptrarray_strtod_xmod — Task 0k pointer-shape 4 pin (PRE-EXISTING, not A1).
//
// The `strtod` endptr argument warning is NOT A1-induced: it is present in the
// pre-A1 compiler (json_parser: 1 pre-A1 -> 60 post-A1, but the single pre-A1
// warning IS this strtod one). `null` for a `?[*]const c_char` parameter is
// materialized through the optional temp as a plain `char*`, then passed where
// the `<stdlib.h>` prototype expects `char**`:
//
//   zT_B..._Opt_... zT_2;          /* ?[*]const c_char */
//   char* zT_1;
//   zT_2.has_value = 0;
//   zT_1 = zT_2.has_value ? zT_2.value : NULL;
//   zT_3 = strtod(zT_4, zT_1);     // warning: passing argument 2 of 'strtod'
//                                  //   from incompatible pointer type
//
// A1 additionally produces shapes 1/2 here because `"3.14"` is a string
// literal. Measured with `@cInclude("<stdlib.h>")` so the prototype is visible
// (`-Wno-implicit-function-declaration` otherwise hides the mismatch):
//   pre-A1 : 1 warning (strtod arg 2 only)
//   post-A1: 3 warnings (shape 1 + shape 2 + strtod arg 2)
// Contract: runs and prints `1`.
@cInclude("<stdlib.h>");
extern fn strtod(nptr: [*]const c_char, endptr: ?[*]const c_char) f64;
const std = @import("std");

pub fn main() void {
    var v: f64 = strtod("3.14", null);
    if (v > 3.0 and v < 3.2) {
        std.io.printInt(@intCast(i32, 1));
    } else {
        std.io.printInt(@intCast(i32, 0));
    }
    std.io.writeByte('\n');
}
