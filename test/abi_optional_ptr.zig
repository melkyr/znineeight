extern fn c_get_ptr(ptr: ?*i32) ?*i32;

export fn zig_wrap_ptr(ptr: *i32) ?*i32 {
    return ptr;
}

export fn zig_unwrap_ptr(ptr: ?*i32) ?*i32 {
    return ptr;
}

pub fn main() i32 {
    var val: i32 = 42;
    var res = c_get_ptr(&val);
    if (res) |p| {
        if (p.* != 42) {
            return 1;
        }
    } else {
        return 2;
    }

    var res_null = c_get_ptr(null);
    if (res_null) |_| {
        return 3;
    }

    return 0;
}
