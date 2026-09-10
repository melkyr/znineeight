// catch_ret_err_if — block-bodied statement-context catch whose arm returns
// the captured payload under a condition (the `return err` shape under test,
// with a non-returning sibling branch).
//
// Pattern:
//     step(i) catch |err| {
//         if (err != E.Full) { return err; }
//     };
// step() always succeeds for i in [0,5); the conditional return is never
// taken on the GREEN path.
//
// Same false-tail-call regression as catch_return_err_tco (b0a53387):
// wrap_error_err -> unwrap_error_code walks back to the step() call, a false
// tail call zeroCallCFG()s the catch's check_error/branch.
//
// zig0 oracle GREEN contract (RUNRC=0, byte-exact):
//   01234
// current zig1: RED (trailing newline only).
extern fn putchar(c: i32) i32;

const E = error{ Full, Fail };

fn printDigit(n: i32) void {
    _ = putchar(48 + n);
}

fn step(n: i32) E!void {
    if (n == 90) return E.Full;
    if (n == 91) return E.Fail;
}

fn run() E!void {
    var i: i32 = 0;
    while (i < 5) {
        step(i) catch |err| {
            if (err != E.Full) {
                return err;
            }
        };
        printDigit(i);
        i += 1;
    }
}

pub fn main() void {
    run() catch {};
    _ = putchar(10);
}
