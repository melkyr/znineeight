fn pick(v: u32) void {
    var r: []const u8 =     switch (v) {
        0 => "",
        1 => "a",
        else => "b",
    };
    r = r;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
