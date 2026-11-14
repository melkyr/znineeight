fn f() void {
    const X = switch (1) { 0 => "a", else => "bb" };
    _ = X;
}

pub fn main() void {
    f();
}
