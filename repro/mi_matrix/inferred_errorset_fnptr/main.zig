fn builtin() !i32 { return error.Bad; }
pub fn main() void {
    var fptr: *void = @ptrCast(*void, builtin);
    const f = @ptrCast(fn () !i32, fptr);
    var r = f() catch 0;
    _ = r;
}
