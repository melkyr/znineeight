# Field Store Drop Bug - RED Repro

## Bug Description

`lower.zig:926` `findLocalTemp` returns `0` as "not found" sentinel.
`lower.zig:322` `nextTemp` counter starts at `0` (first call returns 0, then increments).
At `lower.zig:4011`, first function parameter gets `p_temp = nextTemp(self, TYPE_UNDEFINED)` → temp 0.

Collision: `findLocalTemp` for first param returns `0` — indistinguishable from "not found".

At `lower.zig:1376` in `plain_assign`:
```zig
var src = lowerExpr(self, node.child_1);
if (src == @intCast(u32, 0)) {
    return @intCast(u32, 0);  // store SILENTLY DROPPED
}
```

If any code path causes `lowerExpr` to return 0 for the first param, the store is skipped.

## Current Behavior (C89 Output)

The `make` function shows all three stores present:
```c
zT_5 = a;     // load_local created because arr_temp==0 fails line 1677 check
t.a = zT_5;   // store via intermediate temp (extra copy — symptom of temp collision)
t.b = b;      // second param (temp 1) returned directly via line 1677 path
t.c = c;      // third param (temp 2) returned directly
```

Evidence: first param requires `load_local` → `store_field`; second/third return temp directly → `store_field`.
This extra copy is a symptom of the `findLocalTemp` sentinel collision.

## Latent Bug

The `plain_assign` check at line 1376 WILL drop stores if `lowerExpr` returns 0.
Currently avoided because ident_expr handler (line 1678) creates load_local for arr_temp==0.
But any refactoring or code path change that returns arr_temp directly when it equals 0
would trigger the silent store drop.

## Compile Issues

`main` function C89 output has undeclared variable references (zT_11, zT_16, zT_20, zT_25, zT_29, zT_34)
likely from the same temp counter / TYPE_VOID collision affecting function pointer temps.
These prevent the binary from compiling and running.

## Root Cause

`nextTemp` starts at 0, making the first allocated temp ID 0.
`findLocalTemp` uses 0 as "not found" sentinel.
`plain_assign` treats src==0 as skip-store sentinel.

Three overlapping sentinels on the same value (0) cause this class of bugs.
Fix: either start `nextTemp` at 1, or use a different sentinel for `findLocalTemp`.
