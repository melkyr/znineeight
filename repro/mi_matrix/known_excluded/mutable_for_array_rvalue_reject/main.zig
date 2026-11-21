// Off-corpus mutable-for fixture (Task 3 Step 1f): a call result array value
// would be copied by lowering, so there is no addressable element ->
// error[3078].
fn makeArray() [2]u32 {
    return [2]u32{ 1, 2 };
}

fn fill() void {
    for (makeArray()) |*x| {
    }
}

pub fn main() void {
    fill();
}
