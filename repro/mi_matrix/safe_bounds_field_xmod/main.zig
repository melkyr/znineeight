// safe_bounds_field_xmod — RED->GREEN `-fsafe`/`-ffast` struct-field array
// OOB-read fixture (A5F: array-through-field decay).
//
// `s.arr[i]` with `i = 5` on a `[3]i32` field is an out-of-bounds read. The
// field access lowers to a bare `int*` (the array length is lost at the base
// temp), so A5F recovers the length from the field declaration. Pre-A5F it
// emits the raw C `zT_2 = s->arr; zT_3 = zT_2[i];`: RED rc 0 `v=0`.
//
// GREEN (default `-fsafe`): the `check_trap{kind=5}` guard emits
// `if (!(i < 3u)) { pal_trap(); }` before the load, so stdout is empty and
// rc 133 (SIGTRAP). The `-ffast` control keeps the raw read (`v=0` rc 0) — no
// new emission on the fast path.
const std = @import("std");

const S = struct { arr: [3]i32 };

fn get(s: *S, i: usize) i32 {
    return s.arr[i];
}

pub fn main() void {
    var s: S = S{ .arr = [_]i32{10, 20, 30} };
    var i: usize = 5;
    var v: i32 = get(&s, i);
    std.io.writeStr("v=");
    std.io.printInt(v);
    std.io.writeByte('\n');
}
