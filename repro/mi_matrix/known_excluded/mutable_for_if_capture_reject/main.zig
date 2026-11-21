// Off-corpus mutable-for fixture (Task 3 Step 1k): `*` is accepted at the for
// site only; `if (o) |*x|` must remain a parse error.
pub fn main() void {
    var o: bool = true;
    if (o) |*x| {
    }
}
