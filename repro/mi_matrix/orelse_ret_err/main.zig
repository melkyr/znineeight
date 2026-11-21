// orelse_ret_err — statement-context block-bodied `orelse` whose arm returns
// an error (the optional analogue of the false-tail-call catch shape).
//
// Pattern:
//     opt(i) orelse {
//         return E.Fail;
//     };
// opt() always yields a payload for i in [0,5), so the orelse arm is never
// taken on the GREEN path. zeroCallCFG() NOPs `check_optional`+branch (the
// same rewrite site as `check_error`), so this pins whether the false-match
// also fires for optionals.
//
// NOTE: Z98 rejects the payload-capture form `orelse |v| { ... }` with a
// syntax error, so the closest supported analogue is used.
//
// zig0 oracle GREEN contract (RUNRC=0, byte-exact):
//   01234
extern fn putchar(c: i32) i32;

const E = error{ Full, Fail };

fn printDigit(n: i32) void {
    _ = putchar(48 + n);
}

fn opt(n: i32) ?i32 {
    if (n == 90) return null;
    if (n == 91) return null;
    return n;
}

fn run() E!void {
    var i: i32 = 0;
    while (i < 5) {
        opt(i) orelse {
            return E.Fail;
        };
        printDigit(i);
        i += 1;
    }
}

pub fn main() void {
    run() catch {};
    _ = putchar(10);
}
