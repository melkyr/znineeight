extern fn c_get_ptr(ptr: ?*i32) ?*i32;

var call_count: i32 = 0;
var global_ptr: i32 = 0;
fn get_ptr_with_side_effect() ?*i32 {
    call_count = call_count + 1;
    return &global_ptr;
}

pub fn main() i32 {
    global_ptr = 42;
    var res = c_get_ptr(get_ptr_with_side_effect());
    if (call_count != 1) { return 10; }
    if (res) |p| {
        if (p.* != 42) { return 11; }
    } else {
        return 12;
    }
    return 0;
}
