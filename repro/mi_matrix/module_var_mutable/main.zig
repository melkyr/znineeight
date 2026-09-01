var x: i32 = 0;
fn set_x(v: i32) void { x = v; }
fn get_x() i32 { return x; }
pub fn main() void {
    set_x(42);
    var v = get_x();
    _ = v;
}
