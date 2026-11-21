fn pick(v: u32) void {
    const r =     switch (v) {
        0 => @as([]const u8, ""),
        1 => @as([]const u8, "a"),
        else => @as([]const u8, "b"),
    };
    _ = r;
 }
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
