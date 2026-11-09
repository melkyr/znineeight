fn pick() ?i32 {
    return switch (0) { 0 => null, 1 => 0, else => 1 };
}
pub fn main() void { _ = pick(); }
