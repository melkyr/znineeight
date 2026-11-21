// catch_return_err_tco — block-bodied `catch |err| { ... return err; }` mis-lowered
// by a false tail-call classification in the lowerer.
//
// Pattern (statement-context catch, error path NOT taken at runtime):
//     step(i) catch |err| {
//         if (err == E.Full) { }   // ignore
//         else { return err; }      // propagate
//     };
// The catch must leave the loop running while step() returns success.
//
// zig1 REGRESSION at b0a53387 "fix: F-S2 AMENDMENT 7 try-CFG elimination"
// (2026-08-03): the new `wrap_error_ok` / `wrap_error_err` arms added to
// findTailCall() walk `return err`'s wrap chain back through
// unwrap_error_code to the step() call, so the catch is FALSELY classified as
// a tail call to step(). zeroCallCFG() then NOPs the catch's check_error and
// branch, deleting the error-union check; the call's EU result is returned
// unconditionally and run() aborts after the first iteration.
//
// Good emission (zig0 oracle AND zig1 pre-b0a53387, e.g. 9d029c2e):
//     zT = step(i); zT_e = zT.is_error;
//     if (zT_e) goto err_bb; else goto ok_bb;   // check_error + branch present
//     err_bb: err = zT.err;  ...if (err == Full) {} else { return <EU w/ err>; }
//
// std-free (extern putchar) so the frozen zig0 bootstrap is a clean oracle:
//   zig0   : dump rc=0, gcc rc=0, GREEN stdout byte-exact (RUNRC=0)
//   01234
//   zig1 current (post-b0a53387): check_error/branch NOP'd -> run() aborts on
//   iteration 0 -> no digits printed (only the trailing newline).

extern fn putchar(c: i32) i32;

const E = error{ Full, Fail };

fn printDigit(n: i32) void {
    _ = putchar(48 + n);
}

fn step(n: i32) E!void {
    // Error paths deliberately unreachable for n in [0,5) — the catch's
    // `return err` arm is present but never executed on the GREEN path.
    if (n == 90) return E.Full;
    if (n == 91) return E.Fail;
}

fn run() E!void {
    var i: i32 = 0;
    while (i < 5) {
        step(i) catch |err| {
            if (err == E.Full) {
            } else {
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
