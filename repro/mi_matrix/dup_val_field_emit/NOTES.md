# dup_val_field_emit — FAIL (emission defect, gcc unknown type name)  [I-task: rogue_mud build attempt, 2026-08-07]

## What it tests
A plain struct with TWO fields of the SAME struct type embedded BY VALUE —
`a: Point, b: Point`. A single `Point` field compiles fine; two fields of
the same type do not.

## Origin (rogue_mud)
Same root cause as `dup_optptr_field_emit` (the `BspNode` blocker in
`examples/z98/rogue_mud/lib/bsp.zig`), generalized to by-value fields. Any
struct with 2+ fields of the same edge-requiring type is affected; this
repro proves the bug is NOT specific to optional-pointer self-reference.

## The compiler gap
`tstTopologicalSort` (`sf/src/c89_emit.zig:935-971`): `tstEdgesCount`
(`:799-839`) counts one dependency edge per field occurrence, so a struct
with two `Point` fields has `indegree = 2`. The Kahn dequeue loop
(`:960-968`) calls `tstIsDep` per dependent type and decrements by 1 once,
so indegree never reaches 0. The `Line` struct is dropped from the `sorted`
array and its body/forward-decl are never emitted, while lowerer output
references it by name (`unknown type name 'zT_..._Line'`).

## Measured result (2026-08-07, /tmp/zrg/zig1)
- dump rc=0, 1 `.c` emitted.
- gcc per-file `-c` rc=1: 5 `error:` lines, all `unknown type name`.
- Classification: **FAIL** (emission defect; not a green-guard; not an ICE).

## Oracle verification (zig0)
`./sf/build/zig0 -o /tmp/.../out.c repro` accepts the struct (rc=0, emits
C) — duplicate by-value fields are valid Z98, so this is a genuine compiler
gap.

## Expected classification
FAIL until `tstTopologicalSort`'s decrement loop decrements by the true
edge count (one per field occurrence of each target type) instead of once
per dependent type, or `tstEdgesCount` dedups edges per target type.
