pub const S = struct { x: i32 };

pub fn main() void {
    // BUG: local const aggregate is treated as type decl and skipped
    const s = S{ .x = 1 };
    _ = s;
}
