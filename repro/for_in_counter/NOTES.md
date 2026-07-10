# for_in_counter -- RED: for-in loop counter infinite loop

## Form
Slice for-in summing array elements: `for (sl) |v| { sum_slice += v; }`.

Range for-in (`for (0..3) |i|`) also affected but blocked by type-resolution ICE (rc=2, "unhandled node kind").

## Expected
Slice for-in prints `60`.

## Actual (RED)
Timeout (rc=124) -- infinite loop. The for-in loop computes `idx = idx + 1` in `zT_N = zT_M + zT_1;`
but **never stores `zT_M = zT_N;` back**, so the loop index stays at 0 forever.

## Gate evidence (C output)
```c
    zT_26 = zT_21 + zT_25;
    goto z_bb_1;
```
`zT_21` is the loop index temp. `zT_26 = zT_21 + zT_25` computes next index, then
`goto z_bb_1` jumps back to loop head. No `zT_21 = zT_26;` store-back between them.

## Root cause
`sf/src/lower.zig`: for-in lowering emits `binary(ADD, idx, 1, nxt_idx)` for the counter
increment and stores result in a local Zig variable (`idx_temp = nxt_idx`), but emits **no LIR
`assign` instruction** to wire `nxt_idx` back into the C-declared loop counter variable.

## Cross-links
- `sf/src/lower.zig`: for-in lowering (counter assignment gap)
- `repro/for_in_array/`: related for-in bug (array .ptr/.len access)
