# GREEN repro: address-of a deref (`&(p.*)`) — Task 7

**Status:** GREEN (Task 7). Prints `15` (RED on parent `bf8b3fd1`: `10`).

`&(p.*)` is semantically the pointer `p` itself. Previously `address_of` lowered
`lowerExpr(deref)` (a `load` of `*p` into a copy) then `addr_of` → `&(copy)`, so a
store through it no-op'd the caller's `n`. The `lowerLValueAddr` helper now treats
`deref` as an identity — it returns the pointer temp directly (no `addr_of`) — and
`paren_expr` recurses into its inner l-value. Result: `n` becomes 15.
