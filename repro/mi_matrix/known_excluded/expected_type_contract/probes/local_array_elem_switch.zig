fn f() void {
    const a = [2]i32{ switch (1) { 0 => 1, else => 7 }, 2 };
    _ = a;
}

pub fn main() void {
    f();
}
