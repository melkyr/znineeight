fn pick(v: u32) void {
    const S = struct { x: f32 };
    const s = S{ .x =     switch (v) {
        0 => 1.5,
        1 => 2,
        else => 3.5,
    } };
    _ = s;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
