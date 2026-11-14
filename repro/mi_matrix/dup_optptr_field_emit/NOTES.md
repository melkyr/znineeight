# dup_optptr_field_emit — FAIL (emission defect, gcc unknown type name)  [I-task: rogue_mud build attempt, 2026-08-07]

## What it tests
A plain struct with TWO fields of the SAME self-referential optional-pointer
type — `left: ?*Node, right: ?*Node`. This is the exact shape of
`examples/z98/rogue_mud/lib/bsp.zig`'s `BspNode` struct:
`left: ?*BspNode, right: ?*BspNode, room: ?*room_mod.Room_t`.
A single `?*Node` field compiles fine; two fields of the same type do not.

## Origin (rogue_mud)
Discovered attempting to build `examples/z98/rogue_mud/main.zig` with the
current zig1 (`/tmp/zrg/zig1`, bootstrap 2026-08-07). The frontend dump
SUCCEEDS (rc=0, 20 `.c` emitted) — the previous `labeled_stmt` blocker
(`error[3020]`) is fixed. The build now fails in C89 emission: gcc reports
`unknown type name 'zT_32DE77E2_BspNode'` in every emitted file. The
`BspNode` struct body is NEVER emitted — no `ZIG_STRUCT_...` block and no
forward decl (`typedef struct zT_32DE77E2_BspNode ...;`) in
`zig_special_types.h` — while the struct IS referenced by value in the
emitted C (`scenario.c:71: zT_32DE77E2_BspNode zT_71;`).

## The compiler gap
`tstTopologicalSort` (`sf/src/c89_emit.zig:935-971`) uses Kahn's algorithm
on the type-dependency graph. It computes `indegree[ti] = tstEdgesCount(...)`
(`:799-839`), which counts **one edge per field occurrence**: a struct with
two `?*Node` fields gets `indegree = 2` for the edge to the `?*Node` optional
type. But the dequeue loop (`:960-968`) iterates **per dependent type**, not
per field: `tstIsDep(reg, tj, cur)` returns true once, so indegree is
decremented by 1, leaving 1. The struct type never reaches indegree 0, is
never enqueued, and is therefore absent from the `sorted` array
(`:970`). `emitSharedHeader`/`emitModuleHeaderFile` iterate `sorted`, so the
struct body and forward decl are silently dropped — but the sema/lowerer
still reference the type by name in emitted C, producing the gcc
`unknown type name` errors.

Also affected: ANY struct with 2+ fields of the same edge-requiring type
(optional, struct, tagged_union, union, array, enum, error_set, error_union
— the `c89NeedsEmitEdge` kinds). See `dup_val_field_emit` for the by-value
duplicate-field variant (`a: Point, b: Point`).

## Measured result (2026-08-07, /tmp/zrg/zig1)
- dump rc=0, 1 `.c` emitted (frontend + lowering + emission all run).
- gcc per-file `-c` rc=1: 7 `error:` lines, all `unknown type name
  'zT_3468032D_Node'`.
- Classification: **FAIL** (emission defect — real compiler gap; not a
  green-guard; not an ICE).

## Oracle verification (zig0)
`./sf/build/zig0 -o /tmp/.../out.c repro` accepts the struct (rc=0, emits
C) — duplicate self-referential optional-pointer fields are valid Z98, so
this is a genuine compiler gap.

## Expected classification
FAIL until `tstTopologicalSort`'s decrement loop decrements by the true
edge count (one per field occurrence of each target type) instead of once
per dependent type, or `tstEdgesCount` dedups edges per target type.
