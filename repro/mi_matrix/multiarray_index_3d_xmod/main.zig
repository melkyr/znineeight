// multiarray_index_3d_xmod — 3-level fixed-array element access (Track-4
// Task 2f-I, RED at the fixed point 8a322dd9221077780202e8ac6dd6983a).
//
// `g: [3][4][5]u8`. `&g[i][j][0]` and the rvalue `g[i][j][k]`. Nested access
// recurses through `lowerExpr`'s index_access arm (`sf/src/lower.zig:3080`): the
// OUTER index `g[i]` materializes as a `[4][5]u8` array temp, the middle index
// `g[i][j]` as a `[5]u8` array temp — each emitted as an array-to-array C
// assignment (illegal C89). Pins that the fix must handle N-level nesting, not
// just 2D.
//
// RED (fixed point 8a322dd9…): dump rc=0, 0 target diagnostics (SILENT), 4
// `.c`; gcc rejects `assignment to expression with array type`.
//
// GREEN (Task 2f-F): dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no
// stdout (assertion holds).
fn sink(p: [*]u8, k: usize) void {
    p[k] = 9;
}

var g: [3][4][5]u8 = undefined;

pub fn main() void {
    var i: usize = 1;
    var j: usize = 2;
    var k: usize = 3;
    sink(@ptrCast([*]u8, &g[i][j][0]), k);
    var v: u8 = g[i][j][k];
    if (v != 9) {
        @panic("multiarray_index_3d_xmod: element value mismatch");
    }
}
