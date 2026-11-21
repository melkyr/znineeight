# GREEN repro: address-of scalar parameter (`&param`) — Task 7

**Status:** GREEN (Task 7). Prints `15` (RED on parent `bf8b3fd1`: `10`).

`bump(p: *i32)` does `p.* += 5`. `outer(x: i32)` takes `&x` (a scalar param),
mutates through it, and returns `x`. Correct semantics: `outer(10) == 15`.

Same root cause/fix as `repro/deref_store_scalar_addr`: address-of a scalar param
previously took `&(load copy)`; the `lowerLValueAddr` helper now emits
`addr_of{ findLocalTemp(name_id) }` → `&x` (params are named locals registered via
`addLocalDecl`).
