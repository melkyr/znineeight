const E = error{ X, Y };
fn inner() E!i32 { return E.Y; }
fn outer() E!i32 {
    var result = inner() catch |err| return err;
    return result;
}
pub fn main() void { _ = outer(); }
