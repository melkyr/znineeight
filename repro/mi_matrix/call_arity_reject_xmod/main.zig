// call_arity_reject_xmod — Task 14 (S2) arity reject fixture.
//
// DEFECT (before the fix): a wrong-arity call compiled rc=0 and failed only at
// gcc (`too few`/`too many arguments to function`). Official Zig 0.15.2
// rejects each shape (`expected N argument(s), found M`; variadic too-few:
// `expected at least N argument(s), found M`).
//
// FIX (Task 14): `semanticAnalyzerResolveFnCall` enforces the callee's arity
// at the call site (new level-0 `error[3061]`
// ERR_3061_WRONG_ARGUMENT_COUNT, Zig's "expected N argument(s), found M"
// wording; a variadic callee reports "expected at least N ...") on both the
// direct-call and the fn-value paths, so the program rejects with rc=2 and 0
// emitted `.c`.
//
// Sites (every one independently rejected by official Zig 0.15.2):
//   * `add(2)`          too few    (Zig: expected 2 argument(s), found 1)
//   * `add(1, 2, 3)`    too many   (Zig: expected 2 argument(s), found 3)
//   * `one(1, 2)`       too many   (Zig: expected 1 argument(s), found 2)
//   * `one()`           too few    (Zig: expected 1 argument(s), found 0)
//   * `std.io.print()`  variadic too few (Zig: expected at least 1
//                                      argument(s), found 0)
//
// EXPECTED: dump rc=2, 0 `.c`, exactly one `error[3061]` per site (5 total);
// no `error[3000]`, so this dir buckets as FAIL under the corpus classifier.
// Valid forms stay accepted — see `stdlib_call_arity_types_ok_xmod` and the
// standalone `repro/call_arity_types.z98`.
const std = @import("std");

fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn one(a: i32) i32 {
    return a;
}

pub fn main() void {
    var s: i32 = add(2);
    _ = s;
    var t: i32 = add(1, 2, 3);
    _ = t;
    var v: i32 = one(1, 2);
    _ = v;
    var w: i32 = one();
    _ = w;
    std.io.print();
}
