# d14_sync_tail_ok — synchronous tail call inside an async frame

Phase 3.5 Task 7 probe for the `copyTailCall` name-id fix.

`main.zig` is a suspending wrapper that tail-returns a *synchronous* callee of
the same `E!u32` type:

```zig
fn syncTail(c: *u32, id: u32) E!u32 {
    if (c.* != 0) return E.Boom;
    return id + 1;
}
fn asyncWrapper(c: *u32, id: u32) E!u32 {
    @asyncSuspend(null);
    return syncTail(c, id);
}
```

TCO suppression (D14 fix a) applies only to suspending callees, so this genuine
tail call survives into the async transform and reaches `copyTailCall`. Before
the fix, `copyTailCall` added the step temp base to the callee's interned name
id, so the emitted step called an unrelated symbol. The probe fails to build or
prints the wrong value when that rebase is reintroduced.

The transform lowers the surviving tail call to an ordinary direct call and
routes its result through the standard step result epilogue (the step must
return `Opt`, not the callee's `E!u32`), preserving the step ABI.

`expected.txt`/`expected.rc` encode the runnable contract: `c = 0` prints
`42 0`; `c = 1` takes the error path and prints `0 1`.

Sibling `sibling_void.zig` covers the same path with a void wrapper and a void
synchronous tail callee; it prints `12` (`3 + 9`).
