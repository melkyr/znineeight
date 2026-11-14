// orelse_ret_err_void — expression-context `orelse` whose arm performs a
// void `return`, inside an optional-producing expression statement.
//
// Pattern:
//     var v = opt(i) orelse { return; };
//     _ = v;
// Void-return analogue (no error payload) of the orelse_ret_err sibling;
// pins whether the optional `check_optional`+branch is dropped when the
// orelse arm contains a return.
//
// zig0 oracle GREEN contract (RUNRC=0, byte-exact):
//   01234
extern fn putchar(c: i32) i32;

fn printDigit(n: i32) void {
    _ = putchar(48 + n);
}

fn opt(n: i32) ?i32 {
    if (n == 90) return null;
    if (n == 91) return null;
    return n;
}

fn run() void {
    var i: i32 = 0;
    while (i < 5) {
        var v = opt(i) orelse {
            return;
        };
        _ = v;
        printDigit(i);
        i += 1;
    }
}

pub fn main() void {
    run();
    _ = putchar(10);
}
