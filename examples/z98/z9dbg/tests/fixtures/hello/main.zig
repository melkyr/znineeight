var counter_value: u32 = 0;

const Counter = struct {
    value: u32,
};

// Comment-only line; a break here must snap forward or be rejected.
fn addOne(n: u32) u32 {
    const x = n + 1;
    return x;
}

pub fn main() void {
    var c = Counter{ .value = 41 };
    // Comment between statements; a break here snaps to the next statement.
    c.value = addOne(c.value);
}
