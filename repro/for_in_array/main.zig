extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var arr: [3]i32 = [3]i32{ 10, 20, 30 };
    var sum: i32 = 0;

    for (arr) |v| {
        sum += v;
    }

    __bootstrap_print_int(sum); // expected: 60
}
