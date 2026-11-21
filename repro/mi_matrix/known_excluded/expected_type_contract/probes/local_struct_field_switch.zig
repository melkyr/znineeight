fn f() void {
    const S = struct { x: i32 };
    const s = S{ .x = switch (1) { 0 => 1, else => 7 } };
    _ = s;
}

pub fn main() void {
    f();
}
