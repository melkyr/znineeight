fn take(x: Nope) void {
    _ = x;
}

pub fn main() void {
    const X = take(switch (1) { 0 => 1, else => 7 });
    _ = X;
}
