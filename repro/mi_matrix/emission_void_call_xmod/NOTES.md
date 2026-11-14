# emission_void_call_xmod — RED fixture for root cause D (indirect `.call` arm has no void guard)

Task R (2026-08-20). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Minimal reproducer of **root cause D** from the Task D discovery report: the
indirect-call LIR `.call` arm (`sf/src/c89_emit.zig:5233-5258`) writes
`result = callee(args);` **unconditionally**, with no void-return check —
unlike `call_direct` (`:5259-5348`) which guards with
`if (c.return_type != type_mod.TYPE_VOID)` at `:5372`. A void-returning
fn-ptr called as a statement therefore emits `f = f();` → gcc class-5
`void value not ignored`. Matches the D-report evidence
`analyzer_2FA863C8.c:5531: ctx = visit_fn(zT_21, zT_22, zT_23);` and
`ast_2FA12982.c:2380: store = callback(zT_24, zT_25);`.

## Fixture (verbatim)
```zig
const std = @import("std");

fn foo() void {}

pub fn main() void {
    var f: fn () void = foo;
    f();
    std.io.printInt(0);
}
```

## RED baseline (measured 2026-08-20, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rfx main.zig
rc=0
$ cd /tmp/rfx && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc error (class 5, `void value not ignored`):
```
main_910D56A0.c:19:7: error: void value not ignored as it ought to be
```
Emitted C (the missing void guard):
```
    zT_08C0D7CE_FP_void f;
    ...
    zT_1 = zF_A9F37ED7_foo;
    f = zT_1;
    f = f();          // ← void fn-ptr call assigned → "void value not ignored"
```

## Root cause pinned
`sf/src/c89_emit.zig:5233-5258` (indirect `.call` arm — unconditional
`result = callee(args)` write, no void check). Compare the void guard in
`call_direct` at `c89_emit.zig:5372`. Root cause D of the D report.

## Expected post-fix result
After adding the same void-return guard to the `.call` arm that `call_direct`
has, the void fn-ptr call emits as `f();` with no assignment; gcc `-c` rc=0
and the binary prints `0`.
