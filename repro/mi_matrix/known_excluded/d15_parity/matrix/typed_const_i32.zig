fn pick(v: u32) void {
    const r: i32 =     switch (v) {
        0 => 1,
        1 => 2,
        else => 3,
    };
    _ = r;
 }
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
