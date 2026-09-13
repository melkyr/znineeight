// volatile_drop_array_slice_xmod — GREEN guard (A10F review C1). A
// `*volatile [2]u32` converted to `[]u32` drops the volatile qualifier through
// the pointer-to-array -> slice coercion. The pointer's *array* pointee must
// be unwrapped so the drop is detected at both drop sites: a local declaration
// (assignment path) and a call to a `[]u32` function parameter (fn-param
// path). Two drop sites -> exactly TWO `error[3000]` (implicit volatile
// discard), dump rc=2, 0 `.c` emitted.
//
// RED baseline (before the C1 fix): both sites are accepted silently (dump
// rc=0, zero diagnostics): the ptr->slice array-pointee sub-branch returned
// `array_to_slice` without the qualifier gate, and the volatile-drop detector
// compared the array TypeId directly against the slice element instead of the
// array's element type.
const std = @import("std");

fn take(s: []u32) void {
    s[0] = 1;
}

pub fn main() void {
    var arr: [2]u32 = [_]u32{ 0, 0 };
    const p: *volatile [2]u32 = &arr;
    const bad: []u32 = p;
    take(p);
    std.io.printInt(@intCast(i32, bad[0]));
    std.io.writeByte('\n');
}
