extern fn __bootstrap_print_int(i: i32) void;
pub fn main() void {
    var b: bool = true;
    if (b) { __bootstrap_print_int(1); } else { __bootstrap_print_int(0); }
    var n: i32 = 0;
    while (true) { n += 1; if (n >= 3) break; }
    __bootstrap_print_int(n);
}
