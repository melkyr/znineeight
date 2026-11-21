// module_untyped_array_init_ok_xmod — Phase 3.5 D12 repro.
//
// A module-scope untyped array-literal initializer must lower through the
// declared array type and emit an element-wise copy, not a tuple temp assigned
// whole to the array global.
//
// RED (pre-fix): `zig1` dump rc=0 but gcc rejects the emitted C with
//   error: assignment to expression with array type
// (the global store is `zG_<h>_arr = zT_<n>;` with a `Tup_*` temp).
//
// GREEN (post-fix) contract: dump rc=0, gcc -m32 -std=c89 clean, link+run rc=0,
// stdout `1 42 3\n`. The mutation proves the global is real storage.
const std = @import("std");

pub var arr: [3]u32 = .{ 1, 2, 3 };

pub fn main() void {
    arr[1] = 42;
    std.io.printInt(@intCast(i32, arr[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, arr[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, arr[2]));
    std.io.writeByte('\n');
}
