// catch_ret_err_value_ctx — block-bodied catch whose arm returns the payload,
// but in EXPRESSION context (the catch's OK payload is bound then discarded).
//
// Pattern:
//     const r = step(i) catch |err| {
//         return err;
//     };
//     _ = r;
// Neighbouring shape to catch_return_err_tco (same false-tail-call rewrite),
// testing whether the VALUE context of the catch changes the outcome.
//
// zig0 oracle GREEN contract (RUNRC=0, byte-exact):
//   01234
extern fn putchar(c: i32) i32;

const E = error{ Full, Fail };

fn printDigit(n: i32) void {
    _ = putchar(48 + n);
}

fn step(n: i32) E!i32 {
    if (n == 90) return E.Full;
    if (n == 91) return E.Fail;
    return n;
}

fn run() E!void {
    var i: i32 = 0;
    while (i < 5) {
        const r = step(i) catch |err| {
            return err;
        };
        _ = r;
        printDigit(i);
        i += 1;
    }
}

pub fn main() void {
    run() catch {};
    _ = putchar(10);
}
