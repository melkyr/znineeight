fn worker(cond: bool) i32 {
    var a: i32 = 100;
    @asyncSuspend(null);
    if (cond) {
        a = 1;
    }
    return a;
}

pub fn main() void {
    var r: i32 = worker(true);
    if (r != 1) {
        @panic("branch frame mismatch");
    }
}
