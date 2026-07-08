# Anonymous `.{ ... }` tagged-union return — RED repro

## Form
Anonymous struct init `.{ .Go = n }` used as the return value of a function whose return type is a tagged union (`Command = union(enum) { Quit: void, Go: i32 }`).

## Expected output
`5`

## Actual output (RED)
Garbage value, non-deterministic across runs (e.g., `-159708592`, `-254068144`).

## Emitted-C evidence

Generated C for `parse()` (verbatim from `/tmp/ar.c`):
```c
zT_C67C8F52_Command zF_423B42EC_parse(int n) {
    zT_C67C8F52_Command zT_1;
    unsigned int zT_2;
    zT_2 = n;
    return zT_1;
}
```

The return temp `zT_1` is declared but NEVER written:
- No `zT_1.tag = zT_C67C8F52_Command_Go;`
- No `zT_1.payload.Go._0 = zT_2;`

The entire union is returned uninitialized. The anonymous `.{ .Go = n }` init is resolved to `TYPE_VOID` because `node.child_0` is 0 (no explicit type node), so the sema never records the target tagged-union type and the lowerer's tagged-union payload store path is never reached.

By contrast, an explicit `Command{ .Go = n }` return WOULD set both `.tag` and `.payload.Go._0` (fixed in Task 3).

## Cross-reference
- **Task 3**: Fixed explicit `Type{ .Variant = v }` tagged-union payload store. The lowerer path that emits `.payload.<Variant>._0` is correct.
- **Task 4 (this)**: Remaining gap — anonymous `.{ .Variant = v }` returns need sema inference of the target type (`current_fn_return`) so the lowerer produces the same correct code.
