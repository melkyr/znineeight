fn take(x: ??i32) void { _ = x; }
fn pick(v: u32) void {
    take(    switch (v) {
        0 => null,
        1 => 0,
        else => 1,
    });
}
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
