var g: i32 = 0;
var sink: i32 = 0;
fn f(v: u32) void {
    const y: i32 = switch (v) { 0 => { g = 1; }, else => 2 };
    sink = y;
}
pub fn main() void { var v: u32 = 0; v += 1; f(v); }
