// multiarray_index_local_xmod — multi-dimensional fixed-array element access on
// a FUNCTION-LOCAL array (Track-4 Task 2f-I, RED at the fixed point
// 8a322dd9221077780202e8ac6dd6983a).
//
// `var g: [5][4]u8` is a local. The same `lowerExpr` index_access arm
// (`sf/src/lower.zig:3080`) materializes the outer row `g[i]` into an
// array-typed temp; the emitter (`sf/src/c89_emit.zig:189`) then emits an
// array-to-array assignment. Local vs global does not change the path.
//
// RED (fixed point 8a322dd9…): dump rc=0, 0 target diagnostics (SILENT), 4
// `.c`; gcc rejects `assignment to expression with array type`.
//
// GREEN (Task 2f-F): dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no
// stdout (assertion holds).
fn sink(p: [*]u8, j: usize) void {
    p[j] = 7;
}

pub fn main() void {
    var g: [5][4]u8 = undefined;
    var i: usize = 1;
    var j: usize = 2;
    sink(@ptrCast([*]u8, &g[i][0]), j);
    var v: u8 = g[i][j];
    if (v != 7) {
        @panic("multiarray_index_local_xmod: element value mismatch");
    }
}
