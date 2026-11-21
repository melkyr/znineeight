# RED repro: tagged-union payload store is dropped

## Form
`Value{ .Int = n }` payload-carrying tagged-union construction, exercised two ways:
- direct struct-init at a `var` site: `var a: Value = Value{ .Int = @intCast(i64, 42) };`
- fn-returns-tagged-union: `fn make_int(n: i64) Value { return Value{ .Int = n }; }`
  (mirrors mud `.Go`), then `var b: Value = make_int(@intCast(i64, 100));`

`Value` is `union(enum) { Nil: void, Int: i64, Flag: i32 }`. The `i64` payload matches
lisp `Value.Int` and exercises the i64-on-32-bit path. Both values are read back via a
`switch` with all prongs; result is `ra + rb`.

## Expected vs actual
- Expected correct output: **142** (42 + 100).
- Actual RED output on parent `f2b8da61`: **88** (payload never stored → read-back sees garbage;
  the `88` is whatever happened to be in the uninitialized C union).

## Build / run (current binary, not rebuilt)
```
sf/build/out_release/zig1 --dump-c89 repro/tagged_union_payload/main.zig > /tmp/tu.c 2>/tmp/tu.err  # dump rc=0
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/tu.c \
    sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/tu && /tmp/tu                       # prints 88, run rc=0
```
`--dump-c89` succeeds (rc=0) and gcc links with 0 errors, so the failure is purely a
runtime-correctness defect, not a compile/link error.

## Emitted-C evidence (construction writes tag, never the payload)
`make_int` in the emitted C:
```c
zT_D147F96A_Value zF_967D0961_make_int(zT_C69B2266_i64 n) {
    zT_D147F96A_Value zT_1;
    zT_C69B2266_i64 zT_2;
    unsigned int zT_3;
    zT_2 = n;          /* payload value computed ... */
    zT_3 = 1;
    zT_1.tag = zT_3;   /* only the tag is stored */
    return zT_1;       /* ... but zT_2 is NEVER assigned to zT_1.payload.Int._0 */
}
```
Direct construction of `a` in `main`:
```c
    zT_2 = 42;
    zT_3 = 1;
    zT_1.tag = zT_3;   /* tag only; .payload.Int._0 never written */
    a = zT_1;
```
The union type itself is emitted correctly (`struct { zT_C69B2266_i64 _0; } Int;` inside the
`payload` union), and the READ path does reference it — `v = a.payload.Int._0;` /
`zT_18 = b.payload.Int._0;`. That confirms the defect is on the WRITE/construction side only:
the payload field exists and is read, but construction never assigns `.payload.Int._0`
(nor `.payload` at all). Reading it therefore yields uninitialized garbage.

## Consumer impact notes
- **man / gol**: byte-identical-safe — their unions carry only `void` payloads, so there is no
  payload word to store; fixing the write path cannot change their emitted bytes.
- **mud**: this is a runtime-correctness change (its `.Go`-style fn-returns-tagged-union path
  currently drops the payload); output/behavior will change once the store is emitted.

## Deliberately avoided variant
The `.Nil` prongs use `@intCast(i32, 0)`, NOT `@intCast(i32, -1)`. A negative-literal cast
triggers a SEPARATE, unrelated compiler ICE (`PANIC: integer overflow in @intCast`, rc=134):
zig1's comptime `negate` fold computes `nv = 0 - v` in `u64`, so `-1` becomes `0xFFFF...`, which
the `@intCast` fold then overflows. That defect is out of scope here and captured by **Task 6**.
Using `0` keeps this repro isolating ONLY the payload-store defect.
