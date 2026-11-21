// safe_bounds_slice_xmod — RED->GREEN `-fsafe`/`-ffast` slice OOB-read fixture
// (A5F runtime-length + signed-index normalization).
//
// `s[i]` with `i: i64 = -1` on a `[]i32` of length 3 is an out-of-bounds read:
// the slice length is runtime state (`.len`), and a signed index wider than
// `usize` (i64 on the -m32 target) would otherwise compare as signed and pass.
// Pre-A5F it emits the raw C `s.ptr[i]`: RED rc 0 with `v=3`.
//
// GREEN (default `-fsafe`): the `check_trap{kind=5}` guard loads `.len` from the
// original slice and requires `i >= 0` (wider-than-usize conjunct) plus
// `i < len`, so stdout is empty and rc 133 (SIGTRAP). The `-ffast` control
// keeps the raw read (`v=3` rc 0) — no new emission on the fast path.
const std = @import("std");

fn at(s: []i32, i: i64) i32 {
    return s[i];
}

pub fn main() void {
    var backing: [3]i32 = [_]i32{10, 20, 30};
    var s: []i32 = &backing;
    var i: i64 = 0 - 1;
    var v: i32 = at(s, i);
    std.io.writeStr("v=");
    std.io.printInt(v);
    std.io.writeByte('\n');
}
