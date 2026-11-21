fn pick(v: u32) void {
    var r =     switch (v) {
        0 => @as(i32, 1),
        1 => @as(i32, 2),
        else => @as(i32, 3),
    };
    r = r;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
