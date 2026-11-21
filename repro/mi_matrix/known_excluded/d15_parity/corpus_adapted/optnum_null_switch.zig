fn run(v: u32) void {
    var r: ?u64 =     switch (v) {
        0 => null,
        1 => 0,
        else => 0,
    };
    r = r;
}
pub fn main() void { var v: u32 = 0; v += 1; run(v); }
