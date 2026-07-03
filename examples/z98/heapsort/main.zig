const std = @import("std.zig");

fn swap(arr: *[10]i32, i: usize, j: usize) void {
    const temp = arr[i];
    arr[i] = arr[j];
    arr[j] = temp;
}

fn heapify(arr: *[10]i32, n: usize, i: usize) void {
    var largest = i;
    const l = 2 * i + 1;
    const r = 2 * i + 2;

    if (l < n and arr[l] > arr[largest]) {
        largest = l;
    }

    if (r < n and arr[r] > arr[largest]) {
        largest = r;
    }

    if (largest != i) {
        swap(arr, i, largest);
        heapify(arr, n, largest);
    }
}

fn heapSort(arr: *[10]i32) void {
    const n = 10;

    // Build heap
    var i: i32 = @intCast(i32, n / 2 - 1);
    while (i >= 0) {
        heapify(arr, n, @intCast(usize, i));
        i -= 1;
    }

    // Extract elements from heap
    var j: i32 = @intCast(i32, n - 1);
    while (j > 0) {
        swap(arr, 0, @intCast(usize, j));
        heapify(arr, @intCast(usize, j), 0);
        j -= 1;
    }
}

pub fn main() void {
    var arr = [10]i32{ 12, 11, 13, 5, 6, 7, 20, 1, 15, 3 };

    heapSort(&arr);

    var k: usize = 0;
    while (k < 10) {
        std.debug.printInt(arr[k]);
        k += 1;
    }
}
