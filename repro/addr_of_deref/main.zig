extern fn __bootstrap_print_int(x: i32) void;
fn bump(pp: *i32) void {
    pp.* += @intCast(i32, 5);
}
fn outer(p: *i32) void {
    bump(&(p.*));
}
pub fn main() void {
    var n: i32 = @intCast(i32, 10);
    outer(&n);
    __bootstrap_print_int(n);
}
