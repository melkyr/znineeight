# switch_mixed_case_argtype — FAIL (emission defect, call-arg temp mis-typed)  [I-task: rogue_mud build attempt, 2026-08-07]

## What it tests
A `switch` with a MIX of case bodies — an assignment case
(`'k', 'K' => dx = 0,`) followed by an empty-block case
(`'e', 'E' => {},`) — followed by a case that calls a cross-module function
with pointer and string-literal arguments
(`persist.saveDungeon(&arena, dungeon, "save.dat") catch {};`). The call's
argument temps for `&arena` (should be `Sand*`) and `"save.dat"` (should be
`Slice_u8`) are emitted as `unsigned int` / `char*` respectively, producing
gcc `error: incompatible type for argument` (arg1/arg3).

## Origin (rogue_mud)
`examples/z98/rogue_mud/main.zig:236-256` — the local-input `switch (c)` has
assignment cases (`'w','W' => dy = -1`, etc.), a `break :game_loop` case
(`'q','Q'`), empty cases, and block cases calling
`persistence.saveDungeon(&arena, dungeon, "save.dat")` /
`persistence.loadDungeon(&arena, &dungeon, "save.dat")`. In the emitted C
the `&arena` arg temp is `unsigned int` and the string literal temp is
`char*` instead of `Sand*` / `Slice_u8`. (The `dungeon` ident arg is typed
correctly — the mis-typing only hits args that need the sema `call_arg_types`
param-type mapping.)

## The compiler gap
The presence of a mixed case-body switch *before* the call causes the call's
arg-slot type lookup (`lower.zig` `call_arg_types` map / `slot_tid_b`
fallback at `:2480-2482`) to miss the expected param types for the
address-of and string-literal args, so the emitted slot temps fall back to
the lowered expression type (`unsigned int` for `&local`, `char*` for a
string literal). Control cases with empty-block/break bodies in the same
switch perturb the per-case lowering such that the arg temp types are not
recorded. Only args needing coercion (pointer/string-literal) are affected.

Trigger matrix (measured 2026-08-07, /tmp/zrg/zig1):
- all-assignment cases OR all-empty cases alone → arg temp typed correctly.
- ANY mix of assignment-case + empty/break-case → arg1 (`&arena`) and arg3
  (string literal) temps mis-typed `unsigned int`/`char*`.
- Single saveDungeon call suffices; the `break :game_loop` on the labeled
  loop after the switch is not required.

## Measured result (2026-08-07, /tmp/zrg/zig1)
- dump rc=0, `.c` emitted (frontend + lowering + emission OK).
- gcc per-file `-c` rc=1: `error: incompatible type for argument 1/3 of
  'zF_..._saveDungeon'` (and warnings `assignment to 'unsigned int' from
  'zT_3E40CD83_Sand *'`).
- Classification: **FAIL** (emission defect; not a green-guard; not an ICE).

## Oracle verification (zig0)
`./sf/build/zig0 -o /tmp/.../out.c repro` accepts the mixed-case switch and
the call (rc=0, emits C) — valid Z98, genuine compiler gap.

## Expected classification
FAIL until the call-arg temp typing records the expected param types for
address-of and string-literal args regardless of preceding switch case-body
mix in the same function.
