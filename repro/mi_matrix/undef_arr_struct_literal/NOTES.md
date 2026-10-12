# undef_arr_struct_literal — FAIL (emission defect, zero-fill loop on struct array)  [I-task: rogue_mud build attempt, 2026-08-07]

## What it tests
A struct literal with an array-of-struct field initialized to `undefined`:
`Server{ .listen_socket = 3, .clients = undefined }` where
`clients: [5]Client`. The emitted C expands the `undefined` initializer of
the `[5]Client` field into a zero-fill loop
`clients[_j] = 0;` — assigning integer `0` to a `Client` struct element,
which gcc rejects with `incompatible types when assigning to type
'zT_..._Client' from type 'int'`.

## Origin (rogue_mud)
`examples/z98/rogue_mud/main.zig:54` (`server = net_mod.Server
{ .listen_socket = -1, .clients = undefined };`) and `lib/net.zig:53`
(`Server{ .listen_socket = sock, .clients = undefined };`). Both emit
`zT_XX.clients; { unsigned int _j = 0; while (_j < 5) { zT_XX.clients[_j] =
0; _j++; } }` — a `[5]Client` zero-fill — and gcc fails. For an array of
PRIMITIVES (`[5]i32`) the same `= 0` zero-fill is valid, so `undefined`
array fields of primitive arrays work but struct arrays don't.

## The compiler gap
The `undefined` initializer for an array-typed field is lowered to a
zero-fill loop that stores `0` into each element. That only type-checks when
the element is an integer type; for struct/union elements the emitted
`= 0` is ill-typed C. `undefined` should emit no initialization at all
(uninitialized memory), not a zero-fill.

## Measured result (2026-08-07, /tmp/zrg/zig1)
- dump rc=0, 1 `.c` emitted.
- gcc per-file `-c` rc=1: `error: incompatible types when assigning to type
  'zT_..._Client' from type 'int'`.
- Classification: **FAIL** (emission defect; not a green-guard; not an ICE).

## Oracle verification (zig0)
`./sf/build/zig0 -o /tmp/.../out.c repro` accepts the struct literal
(rc=0, emits C) — `undefined` array-of-struct fields are valid Z98.

## Expected classification
FAIL until the `undefined` array initializer emits nothing (or a
type-correct fill) instead of `arr[i] = 0` for non-integer element types.
