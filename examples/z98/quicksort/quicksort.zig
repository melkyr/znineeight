const std = @import("std");

@cInclude("zig_runtime.h");

fn quicksort(ptr: [*]i32, len: usize, cmp: fn(i32, i32) bool) void {
    if (ptr == null) { return; }
    if (len < 2) { return; }
    var pivot = ptr[0];
    var i: usize = 1;
    var j: usize = len - 1;
    while (i <= j) {
        if (cmp(ptr[i], pivot)) {
            i += 1;
        } else if (cmp(pivot, ptr[j])) {
            j -= 1;
        } else {
            const tmp = ptr[i];
            ptr[i] = ptr[j];
            ptr[j] = tmp;
            i += 1;
            j -= 1;
        }
    }
    // swap pivot into place
    ptr[0] = ptr[j];
    ptr[j] = pivot;
    quicksort(ptr, j, cmp);
    quicksort(ptr + i, len - i, cmp);
}

fn lessThan(a: i32, b: i32) bool {
    return a < b;
}

fn greaterThan(a: i32, b: i32) bool {
    return a > b;
}

fn printArray(ptr: [*]i32, len: usize) void {
    var i: usize = 0;
    while (i < len) {
        std.io.printInt(ptr[i]);
        std.io.print(" ");
        i += 1;
    }
    std.io.print("\n");
}

pub fn main() void {
    var arr = [10]i32{ 3, 1, 4, 1, 5, 9, 2, 6, 5, 3 };
    std.io.print("Original: 3 1 4 1 5 9 2 6 5 3\n");

    std.io.print("Sorted (ascending): ");
    quicksort(@ptrCast([*]i32, &arr), 10, lessThan);
    printArray(@ptrCast([*]i32, &arr), 10);

    std.io.print("Sorted (descending): ");
    quicksort(@ptrCast([*]i32, &arr), 10, greaterThan);
    printArray(@ptrCast([*]i32, &arr), 10);
}
