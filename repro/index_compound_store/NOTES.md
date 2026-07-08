# RED repro: indexed compound store `a[0] += ...` — Task 1

**Status:** RED on parent `007f605d`. Compiles + runs but prints WRONG value
(store dropped).

- Form: `var a:[1]i32 = [1]i32{ @intCast(i32,10) }; a[0] += @intCast(i32,5);`
- Expected: `a[0]` becomes `15`.
- ACTUAL (RED): prints `10` — the increment is never written back to `a[0]`.

## Build/run

```
--dump-c89 rc=0
gcc ok
run: 10   (expected 15)   run rc=0
```

## Emitted-C evidence (dropped store)

The compound assign on the index l-value lowers to a load into a scalar temp,
compute, and write-back **into that temp** instead of back to `a[zT_4]`:

```
zT_4 = 0;
zT_5 = a[zT_4];         /* load COPY of a[0] */
zT_6 = 5;
zT_7 = zT_5 + zT_6;
/*==MARKER_ASSIGN dst=zT_5 src=zT_7==*/
zT_5 = zT_7;            /* writes back to the COPY, not a[zT_4] */
```

The subsequent read `zT_10 = a[zT_9];` still sees `10`. The compound-assign
write-back dispatch does not emit an indexed store for the `index_access` l-value,
so the store is dropped.
