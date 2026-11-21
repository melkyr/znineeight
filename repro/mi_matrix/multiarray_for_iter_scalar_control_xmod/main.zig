// multiarray_for_iter_scalar_control_xmod — CONTROL: a `for` loop that only
// reads a SCALAR element of a multi-dimensional array (Track-4 Task 2g-I).
//
// `for (0..5) |i| { total += g[i][0]; }` over `g: [5][4]u8`. The loop is a
// RANGE loop, and the body reads the scalar element `g[i][0]` through the
// direct multi-dimensional element access Task 2f-F fixed. No array-typed
// iteration item is materialized, so this is already valid C89.
//
// Contract: dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no stdout.
var g: [5][4]u8 = undefined;

pub fn main() void {
    g[2][0] = 7;
    var total: u32 = 0;
    for (0..5) |i| {
        total += g[i][0];
    }
    if (total != 7) {
        @panic("multiarray_for_iter_scalar_control_xmod: sum mismatch");
    }
}
