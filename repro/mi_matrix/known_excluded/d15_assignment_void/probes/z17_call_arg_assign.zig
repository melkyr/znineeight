var g: i32 = 0;
fn take(a: i32) void { _ = a; }
pub fn main() void {
    take(g = 1);
}
