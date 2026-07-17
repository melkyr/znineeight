extern fn __bootstrap_print_int(x: i32) void;

const MyErr = error{ Worse, Bad, Terrible };

fn do_work() MyErr!u32 {
    return error.Bad;
}

pub fn main() void {
    const result = do_work();
    const val = result catch |err| {
        var ec = @intCast(u32, @enumToInt(err));
        var ei: i32 = @intCast(i32, ec);
        __bootstrap_print_int(ei);
        return;
    };
    __bootstrap_print_int(@intCast(i32, val));
}
