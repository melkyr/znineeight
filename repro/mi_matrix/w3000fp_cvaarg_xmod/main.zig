// w3000fp_cvaarg_xmod — Task 0l warning[3000] false-positive pin (VALID Z98 -> (a)).
//
// `total += @cVaArg(&vl, i32);` — `@cVaArg` returns the type named by its SECOND
// argument (`i32`). The builtin resolver has no `@cVaArg` arm, so it falls into
// the generic `ec.len >= 2` branch (`sf/src/semantic_analyzer.zig:2359-2360`)
// and types the result as its FIRST argument (`&vl`, a pointer), so the
// assignment warns `source: pointer / target: i32`.
//
// CONTRACT (Task 0m): the Z98 compiler emits NO `warning[3000]` for this file.
//
// Runtime (today): prints `60`; the va_arg load is correct.
const std = @import("std");

fn sum(count: u32, ...) i32 {
    var vl: va_list = undefined;
    @cVaStart(&vl);
    var total: i32 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        total += @cVaArg(&vl, i32);
    }
    @cVaEnd(&vl);
    return total;
}

pub fn main() void {
    std.io.printInt(sum(3, 10, 20, 30));
    std.io.writeByte('\n');
}
