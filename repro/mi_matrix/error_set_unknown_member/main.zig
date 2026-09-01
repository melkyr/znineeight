const E = error { A, B };
fn f() E { return E.Zzz; }
pub fn main() void { _ = f(); }
