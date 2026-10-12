# parsergap_shadow_local_xmod — Task R4 exploration notes

Root cause under test: local-decl scan (LDS, `sf/src/lower.zig` ~2066-2086) forward-scans and
breaks on the FIRST/outermost match with no scope filter, vs `findLocalTemp`
(lower.zig ~1188-1196) backward-scans + scope-filters.

Compiler under test: `/tmp/fx_subfolder/zig1` (built from HEAD `830c5691`). Do NOT rebuild —
no source change in this task.

## Baseline: plain block shadowing (main.zig) — REPRODUCES

```zig
const std = @import("std");
pub fn main() void {
    var x: i32 = 1;
    {
        var x: i32 = 2;
        std.io.printInt(x);
    }
    std.io.printInt(x);
}
```

Recipe (run from this dir):
```
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```
Results:
- `dump rc=0`, `/tmp/x.c` = 10362 bytes, `/tmp/x.err` empty.
- `gcc rc=0` (command per QUICK_REF.md).
- Runtime output: `22` (printInt emits no separator).
- **Correct expectation: `21`** (inside block prints inner `x=2`, after block prints outer `x=1`).

**REPRODUCES.** Generated C (`zF_EA90E208_main`) declares ONE `int x;`:
```
x = 1;      // outer var x = 1
x = 2;      // inner var x = 2  -> clobbers the SAME slot
printInt(x) // prints 2 (inner, correct)
printInt(x) // prints 2 (WRONG — outer should be 1, but slot was clobbered)
```
Both the inner decl and the post-block reference bind to the same C storage as the outer decl
(the LDS first/outermost-match problem), so the inner `var x = 2` clobbers the outer slot and
the post-block read sees 2. This is the Site B mis-resolution, reproduced with the simplest
general block-shadowing shape. main.zig is kept as the minimal repro.

## Exploration shapes (scratch under /tmp, not committed)

### Shape 1: shadowing inside a while-loop body — REPRODUCES
```zig
const std = @import("std");
pub fn main() void {
    var x: i32 = 1;
    var i: i32 = 0;
    while (i < 1) : (i += 1) {
        var x: i32 = 2;
        std.io.printInt(x);
    }
    std.io.printInt(x);
}
```
- `dump rc=0`, `/tmp/x.c` = 10818 bytes, stderr empty; `gcc rc=0`.
- Runtime output: `22`. Correct expectation: `21`. Same clobber mechanism — REPRODUCES.

### Shape 2: capture name shadowing an outer local — REPRODUCES (binding dropped)
```zig
const std = @import("std");
pub fn main() void {
    var x: i32 = 1;
    var opt: ?i32 = 2;
    if (opt) |x| {
        std.io.printInt(x);
    }
    std.io.printInt(x);
}
```
- `dump rc=0`, `/tmp/x.c` = 10720 bytes, stderr empty; `gcc rc=0`.
- Runtime output: `11`. Correct expectation: `21` (capture binds `x=2`, prints 2 inside;
  outer `x=1` after).
- Generated C: the `|x|` capture binding is entirely DROPPED (`opt.value` is computed into a
  temp but never stored into any `x`); the inner `printInt` reads the outer `x` (value 1). So
  capture-shadow also mis-resolves — the inner use resolves to the outer decl, and the capture
  payload is lost. REPRODUCES (different flavor: capture binding not applied).

### Shape 3: json for-index shape (index shadows outer local) — REPRODUCES
```zig
const std = @import("std");
pub fn main() void {
    var arr = [3]i32{ 5, 6, 7 };
    var i: i32 = 0;
    for (arr) |item, i| {
        std.io.printInt(i);
    }
    std.io.printInt(i);
}
```
- `dump rc=0`, `/tmp/x.c` = 11206 bytes, stderr empty; `gcc rc=0`.
- Runtime output: `0123`. Correct expectation: `0120` (loop index 0,1,2 then outer `i=0`).
- Generated C: loop runs on its own `unsigned int i_1` (prints 0,1,2 inside — fine), but the
  POST-LOOP `printInt` reads `i_1` (final value 3) instead of the outer `var i` (0). The
  post-loop reference resolves to the for-index variable, not the outer local. REPRODUCES —
  this is the json for-index shape the plan flagged as the fallback repro; it reproduces too.

## Summary

| Shape | Actual | Correct | Reproduces |
|---|---|---|---|
| plain block shadow (main.zig) | `22` | `21` | YES |
| while-loop body shadow | `22` | `21` | YES |
| capture `\|x\|` shadow | `11` | `21` | YES |
| for-index shadow (json shape) | `0123` | `0120` | YES |

No escalation needed: the SIMPLE general block-shadow case already reproduces Site B, so
main.zig (verbatim from plan) is the minimal repro. All four shapes confirm the same root
cause family: an inner shadowed local does not get its own scope storage — the LDS
first/outermost match binds it to the outer slot (clobber), or the post-block/post-loop
reference binds to the inner slot (for-index case), instead of innermost-resolution semantics.
