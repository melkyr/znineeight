// safe_bounds_read_xmod — RED->GREEN `-fsafe`/`-ffast` array OOB-read fixture (A5F).
//
// `arr[i]` with `i = 5` on a `[3]i32` is an out-of-bounds read. Pre-A5F it
// emits the raw C `arr[i]`, which reads adjacent stack memory: RED rc 0 with a
// silent garbage value.
//
// GREEN (default `-fsafe`): a `check_trap{kind=5}` guard emits
// `if (!(i < 3u)) { pal_trap(); }` before the load, so stdout is empty and
// rc 133 (SIGTRAP). The `-ffast` control keeps the raw read (garbage rc 0) —
// no new emission on the fast path.
const std = @import("std");

pub fn main() void {
    var arr: [3]i32 = [_]i32{10, 20, 30};
    var i: usize = 5;
    var v: i32 = arr[i];
    std.io.writeStr("v=");
    std.io.printInt(v);
    std.io.writeByte('\n');
}
