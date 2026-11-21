var g: i32 = 0;
pub fn main() void {
    const T = @TypeOf(g = 1);
    comptime {
        if (T != void) @compileError("assignment type is not void");
    }
}
