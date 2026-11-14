fn pick(v: u32) void {
    var r: f32 =     switch (v) {
        0 => 1.5,
        1 => 2,
        else => 3.5,
    };
    r = r;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
