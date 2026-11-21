var g: i32 = 0;
fn h() i32 {
    return (g = 1);
}
pub fn main() void { _ = h(); }
