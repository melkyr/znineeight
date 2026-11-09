fn pick(v: u32) void {
    const r: []const u8 =     switch (v) {
        0 => "",
        1 => "a",
        else => "b",
    };
    _ = r;
 }
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
