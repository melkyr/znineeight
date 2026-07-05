const E = error { Foo };
fn f() E!*u32 { return error.Foo; }
pub fn main() void { _ = f() catch return; }
