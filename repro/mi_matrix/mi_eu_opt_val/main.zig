fn g() ?*u32 { return null; }
const E = error { Bad };
fn f() E!?*u32 { return g(); }
pub fn main() void { _ = f() catch return; }
