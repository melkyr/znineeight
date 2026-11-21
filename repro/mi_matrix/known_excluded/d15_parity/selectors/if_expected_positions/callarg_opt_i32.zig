fn take(x: ?i32) void { _ = x; }
fn pick(v: u32) void { take(if (v == 0) null else 0); }
pub fn main() void { var v: u32 = 0; v += 1; pick(v); }
