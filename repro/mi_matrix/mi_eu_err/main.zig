const E = error { Bad };
fn f() E!*u32 { return error.Bad; }
pub fn main() void { _ = f() catch return; }
