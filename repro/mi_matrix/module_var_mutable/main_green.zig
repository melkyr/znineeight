const x: i32 = 42;
fn get_x() i32 { return x; }
pub fn main() void {
    var v = get_x();
    _ = v;
}
