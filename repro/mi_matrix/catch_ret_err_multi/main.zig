// catch_ret_err_multi — two sequential statement-context block catches in the
// same loop body, each re-propagating its captured payload.
//
// Pattern:
//     a(i) catch |e1| { return e1; };
//     b(i) catch |e2| { return e2; };
// Both calls always succeed for i in [0,5); the false-tail-call rewrite
// should be visible on both, and the second must not swallow the first.
//
// zig0 oracle GREEN contract (RUNRC=0, byte-exact):
//   01234
extern fn putchar(c: i32) i32;

const E = error{ Full, Fail };

fn printDigit(n: i32) void {
    _ = putchar(48 + n);
}

fn a(n: i32) E!void {
    if (n == 90) return E.Full;
    if (n == 91) return E.Fail;
}

fn b(n: i32) E!void {
    if (n == 88) return E.Full;
    if (n == 89) return E.Fail;
}

fn run() E!void {
    var i: i32 = 0;
    while (i < 5) {
        a(i) catch |e1| {
            return e1;
        };
        b(i) catch |e2| {
            return e2;
        };
        printDigit(i);
        i += 1;
    }
}

pub fn main() void {
    run() catch {};
    _ = putchar(10);
}
