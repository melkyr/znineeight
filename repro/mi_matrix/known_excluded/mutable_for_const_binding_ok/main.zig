// Off-corpus mutable-for fixture (Task 3 Step 1d): a `const` BINDING of a
// mutable slice must not leak binding constness into the pointee (`*u32`).
fn fill(s: []u32) void {
    for (s) |*x| {
        x.* = 1;
    }
}

pub fn main() void {
    var buf: [3]u32 = .{ 0, 0, 0 };
    const s: []u32 = buf[0..];
    fill(s);
}
