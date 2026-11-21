fn take(x: i32) void { _ = x; }
fn pick(v: u32) void {
    take(    switch (v) {
        0 => 1,
        1 => 2,
        else => 3,
    });
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
