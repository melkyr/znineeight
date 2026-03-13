extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(i: i32) void;

fn test_while_continue() void {
    var i: i32 = 0;
    var count: i32 = 0;
    while (i < 10) : (i += 1) {
        if (i == 5) {
            __bootstrap_print("continuing at 5\n");
            continue;
        }
        count += 1;
    }
    __bootstrap_print("Final count (should be 9): ");
    __bootstrap_print_int(count);
    __bootstrap_print("\n");
    __bootstrap_print("Final i (should be 10): ");
    __bootstrap_print_int(i);
    __bootstrap_print("\n");
}

fn test_labeled_while_continue() void {
    var i: i32 = 0;
    var count: i32 = 0;
    outer: while (i < 10) : (i += 1) {
        if (i == 3) {
            __bootstrap_print("labeled continue at 3\n");
            continue :outer;
        }
        if (i == 7) {
            __bootstrap_print("unlabeled continue in labeled loop at 7\n");
            continue;
        }
        count += 1;
    }
    __bootstrap_print("Final count (should be 8): ");
    __bootstrap_print_int(count);
    __bootstrap_print("\n");
}

pub fn main() void {
    test_while_continue();
    test_labeled_while_continue();
}
