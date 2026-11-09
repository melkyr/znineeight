var g: i32 = 0;
const E = error{Bad};
var sink: i32 = 0;
pub fn main() void {
    const y: E!i32 = {
        g = 1;
    };
    sink = y catch 0;
}
