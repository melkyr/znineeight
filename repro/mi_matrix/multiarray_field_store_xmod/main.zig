// multiarray_field_store_xmod — field store through a multi-dimensional fixed
// array element (`gc[i][j].v = ...`) (Track-4 Task 2g-F, RED at the fixed point
// 7f9afa82deaa2356633b20a693282cf1).
//
// `gc: [5][4]Cell`. `lowerFieldStore`'s `index_access` base branch
// (`sf/src/lower.zig:1780-1787`) builds the field base as a raw `ptr + idx`
// (`BIN_ADD`) on the decayed row pointer, so `gc[1][2].v = 5` scales by the
// WHOLE row (32 B instead of 8 B). gcc emits only a
// `-Wincompatible-pointer-types` warning (no error), so this is SILENT WRONG
// CODE: the value lands at `gc[1] + 2*sizeof(row)`, not `gc[1][2]`. This shape
// is directly reachable from the Track-4 `client_cells` (`[5][80*50]Cell`)
// shape.
//
// RED (fixed point 7f9afa82…): dump rc=0, 0 target diagnostics (SILENT), 4 `.c`;
// gcc rc=0 (warning only); the store lands in the wrong slot so the runtime
// assertion fails. The rvalue read `gc[1][2].v` is already correct (2f-F).
//
// GREEN (Task 2g-F): the field base is the element address `&(*row)[idx]`
// (reusing the 2f-F `load_index{decay=1}` mechanism). Contract: dump rc=0,
// gcc -m32 -std=c89 clean, link+run rc=0, no stdout (all 20 slots hold their
// expected value after `gc[1][2].v = 5`).
const Cell = struct { v: u32 };

var gc: [5][4]Cell = undefined;

pub fn main() void {
    var p: [*]Cell = @ptrCast([*]Cell, &gc[0][0]);
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        p[i].v = 100 + @intCast(u32, i);
    }
    gc[1][2].v = 5;
    var j: usize = 0;
    var bad: u32 = 0;
    while (j < 20) : (j += 1) {
        var want: u32 = 100 + @intCast(u32, j);
        if (j == 6) { want = 5; }
        if (p[j].v != want) { bad = 1; }
    }
    if (bad != 0) {
        @panic("multiarray_field_store_xmod: field store landed in the wrong slot");
    }
}
