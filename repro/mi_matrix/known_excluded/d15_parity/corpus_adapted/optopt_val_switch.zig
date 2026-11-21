fn run(v: u32) void {
    var r: ??i32 =     switch (v) {
        0 => 42,
        1 => null,
        else => null,
    };
    r = r;
}
pub fn main() void { var v: u32 = 0; v += 1; run(v); }
