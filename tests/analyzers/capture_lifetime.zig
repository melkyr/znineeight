// capture_lifetime.zig — T5 LifetimeAnalyzer capture propagation fixture
// (tech-debt §2.1 shape).
//
// Contract (analyzer tests/analyzers runner): 0 errors, >=1 warning — the
// capture `ptr` inherits the provenance of `op` (a local's address), so
// `return ptr` is "returning pointer to local via variable" (WARN_6010).
fn lifetime_capture() *i32 {
    var x: i32 = 10;
    var op: ?*i32 = &x;
    if (op) |ptr| {
        return ptr;
    }
}

pub fn main() void {
    _ = lifetime_capture();
}
