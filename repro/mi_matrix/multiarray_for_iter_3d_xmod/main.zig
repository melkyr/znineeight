// multiarray_for_iter_3d_xmod — NESTED/3-D `for` iteration over a fixed array
// (Track-4 Task 2g-I, RED at the fixed point 7f9afa82deaa2356633b20a693282cf1).
//
// `g: [3][4][5]u8`. `for (g) |plane|` iterates `[4][5]u8` rows and
// `for (plane) |row|` iterates `[5]u8` rows. EACH for-loop emits an
// array-typed item temp with a hardcoded `decay = 0`
// (`sf/src/lower.zig:6131`), so the emitter renders TWO array-to-array
// assignments (illegal C89). Pins that the Task 2g-F fix must handle N-level
// nesting, not just 2-D.
//
// RED (fixed point 7f9afa82…): dump rc=0, 0 target diagnostics (SILENT), 4
// `.c`; gcc rejects `assignment to expression with array type` (x2).
//
// GREEN (Task 2g-F): dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no
// stdout (assertion holds).
var g: [3][4][5]u8 = undefined;

pub fn main() void {
    g[1][2][3] = 9;
    var total: u32 = 0;
    for (g) |plane| {
        for (plane) |row| {
            var k: usize = 0;
            while (k < 5) : (k += 1) {
                total += row[k];
            }
        }
    }
    if (total != 9) {
        @panic("multiarray_for_iter_3d_xmod: plane sum mismatch");
    }
}
