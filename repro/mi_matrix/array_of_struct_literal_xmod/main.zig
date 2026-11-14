// array_of_struct_literal_xmod — Plan C Task 4b-I RED pin (the I half of the
// Task 4b I/F pair, operator ruling m1787) for the array-of-struct-literal
// compiler defect found while authoring std_sort (Plan C Task 4).
//
// DEFECT. The array-init type resolution does not propagate the array's
// element type as the expected type while resolving each element, so an
// anonymous struct literal element (`.{ ... }`) resolves to `void`:
//
//   Shape 1 (inferred length):
//     var a = [_]Pair{ .{ .key = 1, .val = 2 }, .{ .key = 3, .val = 4 } };
//     -> error[3000]: cannot declare variable of type void (rc 2, 0 .c).
//
//   Shape 2 (annotated length):
//     var b: [2]Pair = [_]Pair{ .{ .key = 1, .val = 2 }, ... };
//     -> warning[3000] type mismatch (source: void), rc 0, but the emitted C
//        references an undeclared temp for the first element:
//        `gcc: error: 'zT_2' undeclared (first use in this function)`.
//
// The typed-element form (`Pair{ ... }` elements) already resolves and emits
// correctly, so it is kept as a control. The workaround used by std_sort's
// vtable fixture is `var a: [N]Pair = undefined;` + per-element assignment.
//
// RED -> GREEN contract (Task 4b-F). All three forms lower/emit/run; this
// program prints exactly `array of struct literal ok` with exit code 0. The
// committed goldens (`expected.txt`/`expected.rc`) encode this DESIRED GREEN
// behaviour, so this pin is RED until Task 4b-F.
//
// This is a compiler-class pin only: no `sf/src` change here, and the fixed
// point stays UNMOVED at bcfa85a40279a5c7bc4d8e6fd5f8df91.
const std = @import("std");

const Pair = struct { key: u32, val: u32 };

var g_fail: u32 = 0;

fn ck(cond: bool, what: []const u8) void {
    if (!cond) {
        g_fail += 1;
        @panic(what);
    }
}

pub fn main() void {
    // Shape 1: inferred-length array literal of anonymous struct elements.
    var a = [_]Pair{ .{ .key = 1, .val = 2 }, .{ .key = 3, .val = 4 } };
    ck(a[0].key + a[1].val == 5, "inferred-length literal");

    // Shape 2: annotated array literal of anonymous struct elements.
    var b: [2]Pair = [_]Pair{ .{ .key = 5, .val = 6 }, .{ .key = 7, .val = 8 } };
    ck(b[0].key + b[1].val == 13, "annotated literal");

    // Control: typed elements already resolve and emit today.
    var c = [_]Pair{ Pair{ .key = 9, .val = 10 }, Pair{ .key = 11, .val = 12 } };
    ck(c[0].key + c[1].val == 21, "typed-element control");

    if (g_fail == 0) {
        std.io.write("array of struct literal ok\n");
    } else {
        std.io.write("array of struct literal FAIL\n");
    }
}
