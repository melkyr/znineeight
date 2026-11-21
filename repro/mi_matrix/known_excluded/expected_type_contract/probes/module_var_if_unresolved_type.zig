var X: Nope = if (true) @as(i32, 1) else @as(i32, 7);

pub fn main() void {
    _ = X;
}
