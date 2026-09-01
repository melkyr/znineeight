extern fn __bootstrap_print_int(x: i32) void;
const Pair = struct { a: i32, b: i32 };
fn store_it(p: *Pair) void {
    p.* = Pair{ .a = @intCast(i32, 7), .b = @intCast(i32, 9) };
}
pub fn main() void {
    var pr: Pair = Pair{ .a = @intCast(i32, 0), .b = @intCast(i32, 0) };
    store_it(&pr);
    __bootstrap_print_int(pr.a + pr.b);
}
