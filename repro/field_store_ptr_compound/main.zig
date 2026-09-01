extern fn __bootstrap_print_int(i: i32) void;
const Counter = struct { n: i32 };
fn inc(c: *Counter) void { c.n += @intCast(i32, 1); }
pub fn main() void {
    var c: Counter = Counter{ .n = @intCast(i32, 5) };
    inc(&c);
    inc(&c);
    __bootstrap_print_int(c.n);   // expect 7
}
