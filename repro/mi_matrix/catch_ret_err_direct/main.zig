// catch_ret_err_direct — minimal block-bodied statement-context catch whose arm
// directly returns the captured error payload.
//
// Pattern:
//     step(i) catch |err| {
//         return err;
//     };
// The catch is a STATEMENT (its EU result is discarded). step() always
// succeeds for i in [0,5), so the `return err` arm is never taken on the
// GREEN path and the loop must run to completion.
//
// Same false-tail-call regression as catch_return_err_tco (first-bad
// b0a53387): findTailCall() follows wrap_error_err -> unwrap_error_code back
// to the step() call, zeroCallCFG() then NOPs the call + the catch's
// check_error/branch, so `step(i)` becomes an unconditional tail return and
// run() aborts on iteration 0.
//
// zig0 oracle GREEN contract (RUNRC=0, byte-exact):
//   01234
// current zig1 (post-b0a53387): RED, prints only the trailing newline.
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
