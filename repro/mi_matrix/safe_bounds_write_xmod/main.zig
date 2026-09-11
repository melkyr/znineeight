// safe_bounds_write_xmod — RED->GREEN `-fsafe`/`-ffast` array OOB-write fixture (A5F).
//
// `arr[i] = 99` with `i = 5` on a `[3]i32` is an out-of-bounds write. Pre-A5F
// it emits the raw C `arr[i] = 99;`, corrupting adjacent stack memory: RED
// rc 0 with `after` printed.
//
// GREEN (default `-fsafe`): a `check_trap{kind=5}` guard emits
// `if (!(i < 3u)) { pal_trap(); }` before the store, so stdout is empty and
// rc 133 (SIGTRAP). The `-ffast` control keeps the raw store (`after` rc 0) —
// no new emission on the fast path.
const std = @import("std");

pub fn main() void {
    var arr: [3]i32 = [_]i32{10, 20, 30};
    var i: usize = 5;
    arr[i] = 99;
    std.io.writeStr("after\n");
}
