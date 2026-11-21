# RED repro: parenthesized deref store `(p.*) = ...` — Task 1

**Status:** RED on parent `007f605d`. `--dump-c89` ICEs.

- Form: `(p.*) = @intCast(i32,7);` (paren-wrapped deref l-value) and nested
  `((p.*)) = @intCast(i32,9);` (a second fn to prove recursion into paren is needed).
- Expected: `set(&a)` → `a==7`, `setNested(&b)` → `b==9`, combined print `16`.
- ACTUAL (RED): `--dump-c89` fails, rc=3, no usable C emitted.

## Emitted-C evidence

None emitted. `--dump-c89` aborts with:

```
error[48]: internal: unsupported assignment l-value (node 15)
```

This is `ERR_9001_ICE` ("internal: unsupported assignment l-value (node N)"),
raised from `sf/src/lower.zig:606`. The assignment-side l-value dispatch does not
recognize a `paren_expr` wrapping a `deref`, so it hits the unsupported fallthrough
ICE. The nested `((p.*))` case would require recursion through the paren even once
the single-paren case is handled.
