// noreturn_opt_ctx_xmod — A19 value-position fixture (optional / error-union
// contexts). A noreturn-valued if_expr initializer or assignment RHS whose
// declared type is `?i32` / `E!i32`: the arms return before any wrapping, so
// no optional/error-union materialization may read a noreturn result temp.
// The lenient warning[3000] (noreturn vs declared type) is pre-existing and
// not an error.
// Contract (GREEN): compiles + runs, prints "1\n4\n5\n8\n".
const std = @import("std");

const MyErr = error{Fail};

fn viaOptIf(c: bool) i32 {
    const x: ?i32 = if (c) return 1 else return 2;
    _ = x;
}

fn viaOptAssign(c: bool) i32 {
    var x: ?i32 = null;
    x = if (c) return 3 else return 4;
    _ = x;
}

fn viaEuIf(c: bool) MyErr!i32 {
    const x: MyErr!i32 = if (c) return 5 else return 6;
    _ = x;
}

fn viaEuAssign(c: bool) MyErr!i32 {
    var x: MyErr!i32 = 0;
    x = if (c) return 7 else return 8;
    _ = x;
}

pub fn main() void {
    std.io.printInt(@intCast(i32, viaOptIf(true)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaOptAssign(false)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaEuIf(true) catch @as(i32, 0)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, viaEuAssign(false) catch @as(i32, 0)));
    std.io.writeByte('\n');
}
