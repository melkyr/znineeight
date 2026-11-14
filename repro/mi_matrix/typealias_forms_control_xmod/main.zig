// typealias_forms_control_xmod — control for A9F-b. Proves the pointer /
// optional / error-union / function aliases are usable in annotation, param,
// return and `@sizeOf` positions, and that the equivalent genuine (non-alias)
// spellings still behave identically.
//
// Contract: compile-clean, run prints 4\n4\n8\n8\n8\n8\n4\n4\n92\n7\n5\n6\n10\n8\n11\n.
const std = @import("std");

const P = *u8;
const O = ?i32;
const E = error{Bad}!i32;
const F = fn(i32) i32;
const Bad = error{Bad};
const NE = Bad!i32;

fn addone(x: i32) i32 {
    return x + 1;
}

fn ret_ptr(p: P) P {
    return p;
}

fn ret_opt(x: i32) O {
    return x;
}

fn ret_eu(x: i32) E {
    return x;
}

fn ret_fn(f: F) F {
    return f;
}

fn ret_ne(x: i32) NE {
    return x;
}

fn use_params(p: P, o: O, e: E, f: F) i32 {
    var r: i32 = 0;
    r += @intCast(i32, p.*);
    r += o orelse 0;
    r += e catch 0;
    r += f(0);
    return r;
}

fn show(n: i32) void {
    std.io.printInt(n);
    std.io.writeByte('\n');
}

pub fn main() void {
    show(@intCast(i32, @sizeOf(P)));
    show(@intCast(i32, @sizeOf(*u8)));
    show(@intCast(i32, @sizeOf(O)));
    show(@intCast(i32, @sizeOf(?i32)));
    show(@intCast(i32, @sizeOf(E)));
    show(@intCast(i32, @sizeOf(error{Bad}!i32)));
    show(@intCast(i32, @sizeOf(F)));
    show(@intCast(i32, @sizeOf(fn(i32) i32)));

    var b: u8 = 7;
    var o: O = 42;
    var e: E = 42;
    var f: F = addone;

    show(use_params(&b, o, e, f));

    var p2: P = ret_ptr(&b);
    show(@intCast(i32, p2.*));
    var o2: O = ret_opt(5);
    show(o2 orelse 0);
    var e2: E = ret_eu(6);
    show(e2 catch 0);
    var f2: F = ret_fn(addone);
    show(f2(9));

    show(@intCast(i32, @sizeOf(NE)));
    var ne: NE = ret_ne(11);
    show(ne catch 0);
}
