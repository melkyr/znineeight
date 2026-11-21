// multiarray_index_xmod — multi-dimensional fixed-array element access with a
// DYNAMIC outer index (Track-4 Task 2f-I, pinned RED at the fixed point
// 8a322dd9221077780202e8ac6dd6983a).
//
// `g: [5][4]u8` global. `&g[i][0]` (dynamic `i`) and the rvalue `g[i][j]`
// (dynamic `i`,`j`). The lowerer's `lowerExpr` index_access arm
// (`sf/src/lower.zig:3080`) materializes the OUTER index `g[i]` into an
// ARRAY-typed temp (`elem_type = resolvedTypeTableGet(node) == [4]u8`) and the
// emitter's `emitBaseIdxAccess` (`sf/src/c89_emit.zig:189`, `kind==0`) emits an
// array-to-array C assignment — illegal in C89.
//
// RED (fixed point 8a322dd9…): dump rc=0 with 0 target diagnostics (SILENT),
// 4 `.c`; gcc rejects `assignment to expression with array type`. Shape:
//   Arr_u8_4 zT_<n>;
//   zT_<n> = zG_<m>_g[i];        /* array = array; invalid C89 */
//   ... = zT_<n>[j];
//
// GREEN (Task 2f-F): the outer index must not produce an array-to-array
// assignment (decay to a pointer / emit an element address). Contract: dump
// rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no stdout (assertion holds).
fn sink(p: [*]u8) void {
    var k: usize = 0;
    while (k < 4) : (k += 1) {
        p[k] = @intCast(u8, k + 1);
    }
}

var g: [5][4]u8 = undefined;

pub fn main() void {
    var i: usize = 2;
    var j: usize = 3;
    sink(@ptrCast([*]u8, &g[i][0]));
    var v: u8 = g[i][j];
    if (v != 4) {
        @panic("multiarray_index_xmod: element value mismatch");
    }
}
