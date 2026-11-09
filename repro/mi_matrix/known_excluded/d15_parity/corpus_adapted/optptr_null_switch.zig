var g: i32 = 0;
fn run(v: u32) void {
    var r: ?*i32 =     switch (v) {
        0 => null,
        1 => &g,
        else => &g,
    };
    r = r;
}
pub fn main() void { var v: u32 = 0; v += 1; run(v); }
