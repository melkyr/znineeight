var g: i32 = 0;
fn pick(v: u32) void {
    const r =     switch (v) {
        0 => @as(?*i32, null),
        1 => @as(?*i32, &g),
        else => @as(?*i32, &g),
    };
    _ = r;
 }
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
