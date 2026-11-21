// multiarray_index_struct_control_xmod — CONTROL: 2D fixed array whose ELEMENT
// is a struct (Track-4 Task 2f-I).
//
// `g: [5][4]Cell` mirrors the Task-3/Task-4 `client_cells:
// [5][80 * 50]ui_mod.Cell` shape (element = aggregate, outer index = row of
// aggregates). `&g[i][0]` and the rvalue `g[i][j]` still route the outer row
// `g[i]` through `lowerExpr`'s index_access arm (`sf/src/lower.zig:3080`),
// producing an `Arr_..._Cell` array-typed temp and the same illegal
// array-to-array C assignment. This is the real-world shape the fix must
// cover.
//
// RED (fixed point 8a322dd9…): dump rc=0, 0 target diagnostics (SILENT), 4
// `.c`; gcc rejects `assignment to expression with array type`.
//
// GREEN (Task 2f-F): dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no
// stdout (assertion holds).
const Cell = struct { v: u32 };

var g: [5][4]Cell = undefined;

pub fn main() void {
    var i: usize = 1;
    var j: usize = 2;
    var p: [*]Cell = @ptrCast([*]Cell, &g[i][0]);
    p[j].v = 7;
    var c: Cell = g[i][j];
    if (c.v != 7) {
        @panic("multiarray_index_struct_control_xmod: element value mismatch");
    }
}
