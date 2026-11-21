// multiarray_for_iter_flat_control_xmod — CONTROL: `for` over a flat 1-D fixed
// array (Track-4 Task 2g-I).
//
// `g: [20]u8`. A flat 1-D array has no array-typed row, so the for-loop item
// temp is the scalar element (`elem_type[0] = u8`) and `emitBaseIdxAccess`
// renders `x = g[i];` (scalar, valid C89). This is the ALREADY-OK control: it
// must stay GREEN both before and after Task 2g-F.
//
// Contract: dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no stdout.
var g: [20]u8 = undefined;

pub fn main() void {
    g[5] = 7;
    var total: u32 = 0;
    for (g) |x| {
        total += x;
    }
    if (total != 7) {
        @panic("multiarray_for_iter_flat_control_xmod: sum mismatch");
    }
}
