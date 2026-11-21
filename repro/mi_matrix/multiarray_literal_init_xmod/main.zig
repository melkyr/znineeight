// multiarray_literal_init_xmod — multi-dimensional fixed-array literal
// initializer (`var g: [2][3]u8 = [2][3]u8{ ... }`) (Track-4 Task 2g-F, RED at
// the fixed point 7f9afa82deaa2356633b20a693282cf1).
//
// The array-literal lowering builds each element with `assign_index`
// (`sf/src/lower.zig:5048`/`:5254`); when the element is itself a fixed array
// the source is array-typed, so the emitter renders an illegal array-to-array
// C assignment. The global store (`store_global`) likewise copies the whole
// array row-by-row (`zG_g[_i] = zT_0[_i];`).
//
// RED (fixed point 7f9afa82…): dump rc=0, 0 target diagnostics (SILENT), 4 `.c`;
// gcc rejects `assignment to expression with array type` x3 (two element
// copies + the global-init copy loop).
//
// GREEN (Task 2g-F): the element/global array copies are byte-wise, and the
// nested literal is typed by its annotation (u8 rows, not inferred u32).
// Contract: dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no stdout.
var g: [2][3]u8 = [2][3]u8{ [3]u8{1,2,3}, [3]u8{4,5,6} };

pub fn main() void {
    if (g[0][0] != 1 or g[0][2] != 3 or g[1][0] != 4 or g[1][2] != 6) {
        @panic("multiarray_literal_init_xmod: literal init mismatch");
    }
}
