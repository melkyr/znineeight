fn pick(v: u32) void {
    const S = struct { x: i32 };
    const s = S{ .x =     switch (v) {
        0 => 1,
        1 => 2,
        else => 3,
    } };
    _ = s;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
