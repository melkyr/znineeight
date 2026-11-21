// sig_arb_width.zig — SIG-1 arbitrary-width integer signature surface.
//
// Contract (analyzer tests/analyzers runner): 0 diagnostics. Arbitrary-width
// ints (`i1`-`i63` / `u1`-`u64`, the parseArbIntWidth family) are accepted in
// parameters and returns; they lower to a stable C89 carrier.
fn f1(x: i7, y: u48) i3 {
    _ = x;
    _ = y;
    return 1;
}

fn f2(x: i63, y: u64) u1 {
    _ = x;
    _ = y;
    return 1;
}

pub fn main() void {
    _ = f1(1, 2);
    _ = f2(1, 2);
}
