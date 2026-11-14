const E = error{ A, B };
pub fn main() void {
    var e: E = E.A;
    _ = e == E.A;
}
