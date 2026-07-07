extern fn __bootstrap_print_int(i: i32) void;
const Counter = struct { n: i32 };
fn bump(c: *Counter, v: i32) void { c.n = v; }
pub fn main() void {
    var c: Counter = Counter{ .n = @intCast(i32, 0) };
    bump(&c, @intCast(i32, 7));
    __bootstrap_print_int(c.n);   // expect 7
}
