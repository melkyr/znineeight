// catch_ret_err_nested_fn — the block-catch-return shape inside an inner
// error-union function that is itself called (and re-propagated) by an outer
// error-union function.
//
// Pattern:
//   fn inner() E!void { step(i) catch |err| { return err; }; ... }
//   fn run() E!void { inner() catch |err| { return err; }; ... }
// Both the inner catch and the outer re-propagation catch are exercised.
//
// zig0 oracle GREEN contract (RUNRC=0, byte-exact):
//   01234
extern fn putchar(c: i32) i32;

const E = error{ Full, Fail };

fn printDigit(n: i32) void {
    _ = putchar(48 + n);
}

fn step(n: i32) E!void {
    if (n == 90) return E.Full;
    if (n == 91) return E.Fail;
}

fn inner() E!void {
    var i: i32 = 0;
    while (i < 3) {
        step(i) catch |err| {
            return err;
        };
        printDigit(i);
        i += 1;
    }
}

fn run() E!void {
    inner() catch |err| {
        return err;
    };
    var i: i32 = 3;
    while (i < 5) {
        step(i) catch |err| {
            return err;
        };
        printDigit(i);
        i += 1;
    }
}

pub fn main() void {
    run() catch {};
    _ = putchar(10);
}
