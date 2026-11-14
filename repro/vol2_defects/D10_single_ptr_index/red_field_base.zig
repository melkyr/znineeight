// D10 sibling: indexing a single-item pointer-to-struct, then field access
// (`ps[0].x`). Seed v88 accepted it and printed `ps[0].x=5 ps.x=5`; now the
// index rejects `error[3066]` (rc 2 / 0 `.c`), while `ps.x` auto-deref stays
// accepted (see NOTES.md).
const std = @import("std");

const Point = struct { x: i32, y: i32 };

pub fn main() void {
    var pt: Point = .{ .x = 5, .y = 6 };
    const ps: *Point = &pt;
    std.io.print("ps[0].x={} ps.x={}\n", .{ ps[0].x, ps.x });
}
