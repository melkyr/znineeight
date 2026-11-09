fn take(x: ?i32) ?i32 {
    return x;
}

const X = take(switch (1) { 0 => null, else => 7 });

pub fn main() void {
    _ = X;
}
