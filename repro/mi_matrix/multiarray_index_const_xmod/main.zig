// multiarray_index_const_xmod — multi-dimensional fixed-array element access
// with CONSTANT indices (Track-4 Task 2f-I, RED at the fixed point
// 8a322dd9221077780202e8ac6dd6983a).
//
// `&g[2][0]` and the rvalue `g[2][3]` — no dynamic index at all. Even a
// constant outer index routes through `lowerExpr`'s index_access arm
// (`sf/src/lower.zig:3080`), which still materializes the OUTER row `g[2]`
// into an array-typed temp, so the same illegal array-to-array C assignment is
// emitted. This pins that the defect is index-VALUE-independent.
//
// RED (fixed point 8a322dd9…): dump rc=0, 0 target diagnostics (SILENT), 4
// `.c`; gcc rejects `assignment to expression with array type`.
//
// GREEN (Task 2f-F): dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no
// stdout (assertion holds).
fn sink(p: [*]u8) void {
    p[3] = 5;
}

var g: [5][4]u8 = undefined;

pub fn main() void {
    sink(@ptrCast([*]u8, &g[2][0]));
    var v: u8 = g[2][3];
    if (v != 5) {
        @panic("multiarray_index_const_xmod: element value mismatch");
    }
}
