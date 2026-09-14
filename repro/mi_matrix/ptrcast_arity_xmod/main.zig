pub fn main() void {
    var n: i32 = 0;
    var p: *void = @ptrCast(&n);        // 1-arg: must be error[3049]
    _ = p;
    var q: *i32 = @ptrCast(*i32, &n);   // 2-arg: must compile
    q.* = 1;
}
