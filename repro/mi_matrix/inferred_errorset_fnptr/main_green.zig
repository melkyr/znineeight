const E = error{ Bad };
fn builtin() E!i32 { return error.Bad; }
pub fn main() void {
    const f: fn () E!i32 = builtin;
    var r = f() catch 0;
    _ = r;
}
