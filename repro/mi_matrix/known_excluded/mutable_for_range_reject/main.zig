// Off-corpus mutable-for fixture (Task 3 Step 1c): a range item is a loop
// value, not addressable storage -> error[3078].
fn loop(n: u32) void {
    for (0..n) |*i| {
    }
}

pub fn main() void {
    loop(3);
}
