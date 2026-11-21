var X: Nope = switch (1) { 0 => @as(i32, 1), else => @as(i32, 7) };

pub fn main() void {
    _ = X;
}
