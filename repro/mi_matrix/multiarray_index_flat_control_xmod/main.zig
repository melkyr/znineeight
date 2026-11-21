// multiarray_index_flat_control_xmod — CONTROL: flat 1D fixed-array element
// access (Track-4 Task 2f-I).
//
// `g: [20]u8` with `&g[i]` and the rvalue `g[i]`. A flat 1D array has no outer
// array-typed row, so `lowerExpr`'s index_access arm yields the scalar element
// type directly and the emitter writes `zT = zG_g[i];` (scalar, valid C89).
// This is the ALREADY-OK control: it must stay GREEN both before and after
// Task 2f-F.
//
// Contract: dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0, no stdout.
fn sink(p: [*]u8, i: usize) void {
    p[i] = 7;
}

var g: [20]u8 = undefined;

pub fn main() void {
    var i: usize = 5;
    sink(@ptrCast([*]u8, &g[i]), i);
    var v: u8 = g[i];
    if (v != 7) {
        @panic("multiarray_index_flat_control_xmod: element value mismatch");
    }
}
