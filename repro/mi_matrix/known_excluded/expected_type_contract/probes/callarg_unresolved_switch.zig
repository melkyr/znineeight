fn take(x: Nope) void {
    _ = x;
}

const X = take(switch (1) { 0 => 1, else => 7 });

pub fn main() void {
    _ = X;
}
