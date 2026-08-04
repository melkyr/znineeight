var counter: i32 = 0;
fn bump() void {
    counter = counter + 1;
}
extern fn __bootstrap_print_int(n: i32) void;
pub fn main() void {
    bump();
    bump();
    __bootstrap_print_int(counter);
}
