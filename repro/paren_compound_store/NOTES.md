# RED repro: parenthesized compound deref store `(p.*) += ...` — Task 1

**Status:** RED on parent `007f605d`. Compiles + runs but prints WRONG value
(store dropped).

- Form: `(p.*) += @intCast(i32,5);` (paren-wrapped deref, compound assign), with a
  real pointer via `&arr[0]`.
- Expected: `arr[0]` becomes `15`.
- ACTUAL (RED): prints `10` — the increment is never written back through `*p`.

## Build/run

```
--dump-c89 rc=0
gcc ok
run: 10   (expected 15)   run rc=0
```

## Emitted-C evidence (dropped store)

In `zF_623C0FB5_bump` the compound assign lowers to a load into a scalar temp,
compute, and write-back **into that temp** rather than through `*p`:

```
zT_1 = p;
zT_2 = *zT_1;            /* load COPY of *p */
zT_3 = 5;
zT_4 = zT_2 + zT_3;
/*==MARKER_ASSIGN dst=zT_2 src=zT_4==*/
zT_2 = zT_4;             /* writes back to the COPY, not *zT_1 */
```

The write-back target is the loaded scalar `zT_2`, so `*p` (and thus `arr[0]`) is
never updated. The compound-assign write-back dispatch does not handle a
`paren_expr` wrapping a `deref` l-value, so it silently drops the store.
