// Off-corpus mutable-for fixture (Task 3 Step 1i): the rejected range item must
// still be followed by index registration, so `j` resolves (no error[20]) and
// exactly one error[3078] is reported for the item.
fn sink(x: usize) void {
    _ = x;
}

fn loop(n: u32) void {
    for (0..n) |*i, j| {
        sink(j);
    }
}

pub fn main() void {
    loop(3);
}
