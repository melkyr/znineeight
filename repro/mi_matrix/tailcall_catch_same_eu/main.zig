// tailcall_catch_same_eu — genuine same-EU-type tail-call shape
//
// Pattern (Task-8 semantics-preservation fixture):
//     fn f(n) E!i32 { return g(n) catch |e| return e; }
// `g` and `f` share the SAME error-union type (`E!i32`); the catch arm
// re-propagates the payload `e` unchanged. Pre-b0a53387 `findTailCall()` did
// NOT follow this chain, so the shape never TCO'd. b0a53387 added the
// `wrap_error_*` / `unwrap_error_code` arms, which made the walk reach the
// `g()` call: zeroCallCFG() then NOP'd `check_error` + `branch` and returned
// `g()`'s EU result directly. Task-8 (43d3f113) rejects any chain that
// traverses `unwrap_error_code`, so this shape is correctly de-optimized: the
// `g()` call is lowered normally and the catch CFG
// (`unwrap_error_code` -> `wrap_error_err` -> `check_error` -> `branch`) is
// RETAINED (no `zeroCallCFG` NOP).
//
// The de-opt is OPTIMIZATION-ONLY: for this genuine same-EU shape, TCO vs
// call+propagate produce identical behavior (success value passes through;
// error `e` is returned unchanged). Pre-b0a53387 it was not TCO'd either.
//
// std-free (`extern fn putchar`) so the frozen zig0 bootstrap is a clean
// oracle. GREEN contract (byte-exact stdout, RUNRC=0):
//     f(65) -> g(65)=65 success -> value 65 -> putchar(65) = 'A'
//     f(-1) -> g(-1)=E.Neg error -> catch e -> return e -> main's catch
//              observes E.Neg -> putchar(78) = 'N'
//     trailing newline (putchar(10))
//   => "AN\n"  (bytes 65 78 10)

extern fn putchar(c: i32) i32;

const E = error{ Neg, Big };

fn g(n: i32) E!i32 {
    if (n < 0) return E.Neg;
    if (n > 90) return E.Big;
    return n;
}

fn f(n: i32) E!i32 {
    return g(n) catch |e| return e;
}

pub fn main() void {
    const a = f(65) catch 63;
    _ = putchar(a);
    const b = f(-1) catch |e| {
        if (e == E.Neg) {
            _ = putchar(78);
        } else {
            _ = putchar(66);
        }
        return;
    };
    _ = putchar(b);
    _ = putchar(10);
}
