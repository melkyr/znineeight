var g: i32 = 0;
fn take(x: ?*i32) void { _ = x; }
fn pick(v: u32) void {
    take(    switch (v) {
        0 => null,
        1 => &g,
        else => &g,
    });
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
