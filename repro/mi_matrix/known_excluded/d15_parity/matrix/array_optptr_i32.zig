var g: i32 = 0;
fn pick(v: u32) void {
    const a = [_]?*i32{     switch (v) {
        0 => null,
        1 => &g,
        else => &g,
    } };
    _ = a;
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
