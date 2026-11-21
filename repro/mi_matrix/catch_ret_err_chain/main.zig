// catch_ret_err_chain — nested catch chains feeding a single `return`.
//
// Pattern:
//     outer(i) catch |e1| {
//         inner(i) catch |e2| {
//             _ = e2;
//             return e1;          // draws the payload from the OUTER catch
//         };
//     };
// A return of the outer catch payload sits inside a nested (inner) catch
// block, so the wrap_error_err -> unwrap_error_code walk used by
// findTailCall() must traverse two catch unwraps.
//
// zig0 oracle GREEN contract (RUNRC=0, byte-exact):
//   01234
extern fn putchar(c: i32) i32;

const E = error{ Full, Fail };

fn printDigit(n: i32) void {
    _ = putchar(48 + n);
}

fn outer(n: i32) E!void {
    if (n == 90) return E.Full;
    if (n == 91) return E.Fail;
}

fn inner(n: i32) E!void {
    if (n == 88) return E.Full;
    if (n == 89) return E.Fail;
}

fn run() E!void {
    var i: i32 = 0;
    while (i < 5) {
        outer(i) catch |e1| {
            inner(i) catch |e2| {
                _ = e2;
                return e1;
            };
        };
        printDigit(i);
        i += 1;
    }
}

pub fn main() void {
    run() catch {};
    _ = putchar(10);
}
