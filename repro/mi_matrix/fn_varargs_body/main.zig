extern fn printf(fmt: [*]const u8, ...) i32;

fn sum(count: u32, ...) i32 {
    var vl: va_list = undefined;
    @cVaStart(&vl);
    var total: i32 = 0;
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        total += @cVaArg(&vl, i32);
    }
    @cVaEnd(&vl);
    return total;
}

pub fn main() void {
    var fmt: [*]const u8 = "sum=%d\n";
    var s: i32 = sum(3, 10, 20, 30);
    _ = printf(fmt, s);
}
