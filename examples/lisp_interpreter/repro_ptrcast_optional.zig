pub fn main() void {
    var opt: ?*i32 = null;
    var raw: *i32 = @ptrCast(*i32, opt);
    _ = raw;
}
