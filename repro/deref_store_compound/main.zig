extern fn __bootstrap_print_int(x: i32) void;
fn bump(p: *i32) void {
    p.* += @intCast(i32, 5);
}
pub fn main() void {
    var arr: [1]i32 = [1]i32{ @intCast(i32, 10) };
    bump(&arr[0]);
    __bootstrap_print_int(arr[0]);
}
