export fn zig_unwrap_with_side_effect() ?*i32 {
    return get_ptr_with_side_effect();
}

var call_count: i32 = 0;
var global_ptr: i32 = 0;
fn get_ptr_with_side_effect() ?*i32 {
    call_count = call_count + 1;
    return &global_ptr;
}

pub fn main() i32 {
    _ = zig_unwrap_with_side_effect();
    if (call_count != 1) { return 10; }
    return 0;
}
