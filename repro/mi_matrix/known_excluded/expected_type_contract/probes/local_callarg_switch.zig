fn take(x: ?i32) ?i32 {
    return x;
}

fn f() void {
    const X = take(switch (1) { 0 => null, else => 7 });
    _ = X;
}

pub fn main() void {
    f();
}
