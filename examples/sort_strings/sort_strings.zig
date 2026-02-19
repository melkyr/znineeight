extern fn __bootstrap_print(s: *const u8) void;

fn strLessThan(a: [*]const u8, b: [*]const u8) bool {
    var i: usize = 0;
    while (a[i] != 0 and b[i] != 0) {
        if (a[i] < b[i]) { return true; }
        if (a[i] > b[i]) { return false; }
        i += 1;
    }
    return a[i] == 0 and b[i] != 0; // a is shorter -> true
}

fn sortStrings(ptr: [*][*]const u8, len: usize) void {
    var i: usize = 1;
    while (i < len) {
        var j = i;
        while (j > 0) {
            if (strLessThan(ptr[j], ptr[j-1])) {
                const tmp = ptr[j];
                ptr[j] = ptr[j-1];
                ptr[j-1] = tmp;
                j -= 1;
            } else {
                break;
            }
        }
        i += 1;
    }
}

fn printStrings(ptr: [*][*]const u8, len: usize) void {
    var i: usize = 0;
    while (i < len) {
        __bootstrap_print(@ptrCast(*const u8, ptr[i]));
        __bootstrap_print(" ");
        i += 1;
    }
    __bootstrap_print("\n");
}

pub fn main() void {
    var words = [4][*]const u8{
        @ptrCast([*]const u8, "banana"),
        @ptrCast([*]const u8, "apple"),
        @ptrCast([*]const u8, "cherry"),
        @ptrCast([*]const u8, "date")
    };
    __bootstrap_print("Original: banana apple cherry date\n");

    __bootstrap_print("Sorted strings: ");
    sortStrings(@ptrCast([*][*]const u8, &words), 4);
    printStrings(@ptrCast([*][*]const u8, &words), 4);
}
