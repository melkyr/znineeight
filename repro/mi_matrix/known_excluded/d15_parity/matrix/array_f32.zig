fn pick(v: u32) void {
    const a = [_]f32{     switch (v) {
        0 => 1.5,
        1 => 2,
        else => 3.5,
    } };
    _ = a;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
