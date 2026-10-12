extern fn __bootstrap_print_int(x: i32) void;

pub fn main() void {
    var arr: [3]i32 = [3]i32{ 10, 20, 30 };
    var sl: []const i32 = arr[0..3];

    // slice for-in -- should sum to 60, infinite-loops (counter never stored back)
    var sum_slice: i32 = 0;
    for (sl) |v| {
        sum_slice += v;
    }

    // Unreachable due to infinite loop
    __bootstrap_print_int(sum_slice);
}
