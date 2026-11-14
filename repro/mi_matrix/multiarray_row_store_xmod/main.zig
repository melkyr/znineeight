// multiarray_row_store_xmod — row store into a multi-dimensional fixed-array
// element (`g[0] = row;`) (Track-4 Task 2g-F, RED at the fixed point
// 7f9afa82deaa2356633b20a693282cf1).
//
// `lowerAssignLValue`'s `index_access` arm (`sf/src/lower.zig:1564`) emits
// `assign_index` with an ARRAY-typed source, so the emitter renders
// `g[0] = row;` — an illegal array-to-array C assignment.
//
// RED (fixed point 7f9afa82…): dump rc=0, 0 target diagnostics (SILENT), 4 `.c`;
// gcc rejects `assignment to expression with array type`.
//
// GREEN (Task 2g-F): the row copy is byte-wise. Contract: dump rc=0,
// gcc -m32 -std=c89 clean, link+run rc=0, no stdout. The fixture pre-fills all
// 12 bytes with distinct values, stores row 0, and asserts the WHOLE row 0 is
// overwritten (all four bytes, incl. the middle) AND that rows 1-2 are
// untouched (reviewer Minor #4).
var g: [3][4]u8 = undefined;

pub fn main() void {
    var p: [*]u8 = @ptrCast([*]u8, &g[0][0]);
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        p[i] = 200 + @intCast(u8, i);
    }
    var row: [4]u8 = [4]u8{1,2,3,4};
    g[0] = row;
    if (g[0][0] != 1 or g[0][1] != 2 or g[0][2] != 3 or g[0][3] != 4) {
        @panic("multiarray_row_store_xmod: row store mismatch");
    }
    var j: usize = 4;
    while (j < 12) : (j += 1) {
        if (p[j] != 200 + @intCast(u8, j)) {
            @panic("multiarray_row_store_xmod: untouched row clobbered");
        }
    }
}
