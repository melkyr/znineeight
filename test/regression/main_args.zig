extern fn __bootstrap_print(s: *const c_char) void;

pub fn main(argc: i32, argv: [*]*const u8) void {
    if (argc > 1) {
        __bootstrap_print("Arg count > 1\n");
        const v = argv;
        _ = v;
    } else {
        __bootstrap_print("No args\n");
    }
}
