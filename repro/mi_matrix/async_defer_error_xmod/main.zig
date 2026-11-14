fn worker(out: *i32) void {
    defer {
        @asyncSuspend(null);
    }
    out.* = 7;
}

pub fn main() void {
    var result: i32 = 0;
    worker(&result);
}
