var counter: i32 = 0;
var global_opt: ?i32 = null;
var global_err: !i32 = 0;

pub fn get_opt_ptr() *?i32 {
    counter = counter + 1;
    return &global_opt;
}

pub fn get_err_ptr() *!i32 {
    counter = counter + 1;
    return &global_err;
}

pub fn test_opt_eval() void {
    get_opt_ptr().* = 42;
}

pub fn test_opt_null_eval() void {
    get_opt_ptr().* = null;
}

pub fn test_err_eval() void {
    get_err_ptr().* = 100;
}

pub fn test_prec(ptr: **?i32) void {
    ptr.*.* = 200;
}

pub fn main() void {
    test_opt_eval();
    test_opt_null_eval();
    test_err_eval();
    var x: ?i32 = null;
    var px: *?i32 = &x;
    test_prec(&px);
}
