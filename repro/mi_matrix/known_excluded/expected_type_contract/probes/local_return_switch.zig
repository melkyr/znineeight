fn pick(v: u32) ?i32 {
    return switch (v) { 0 => null, else => 7 };
}

pub fn main() void {
    _ = pick(0);
}
