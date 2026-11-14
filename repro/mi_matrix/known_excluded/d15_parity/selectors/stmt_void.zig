fn a() void {}
fn b() void {}
fn f(v: u32) void {
    switch (v) { 0 => a(), else => b() }
}
pub fn main() void { var v: u32 = 0; v += 1; f(v); }
