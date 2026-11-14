fn g(x: i32) void {
    @asyncSuspend(null);
}

fn f(a: i32) void {
    g(a);
}

fn h() void {
    g(5);
}

pub fn main() void {
    f(1);
    h();
}
