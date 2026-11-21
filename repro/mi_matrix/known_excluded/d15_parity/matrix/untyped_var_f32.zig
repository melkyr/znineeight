fn pick(v: u32) void {
    var r =     switch (v) {
        0 => @as(f32, 1.5),
        1 => @as(f32, 2),
        else => @as(f32, 3.5),
    };
    r = r;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
