const E = error { Foo };
fn f() E!*u32 {
    var p: *u32 = undefined;
    return p;
}
pub fn main() void { _ = f() catch return; }
