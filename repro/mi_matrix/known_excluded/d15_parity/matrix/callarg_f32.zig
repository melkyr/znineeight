fn take(x: f32) void { _ = x; }
fn pick(v: u32) void {
    take(    switch (v) {
        0 => 1.5,
        1 => 2,
        else => 3.5,
    });
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
