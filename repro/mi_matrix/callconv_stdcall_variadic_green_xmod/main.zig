extern "stdcall" fn z98_stdcall_variadic(x: i32, ...) i32;

pub fn main() void {
    _ = z98_stdcall_variadic;
}
