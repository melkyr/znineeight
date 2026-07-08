# FIXED repro: address-of scalar local (`&n`) — Task 7

**Status:** FIXED (Task 7, 2026-07-08). Prints `15` (was `10`). This is now a
GREEN regression guard, not a known-failing case.

- Expected/actual output: `15` (= 10 + 5).

## What it does

`bump(p: *i32)` does `p.* += 5`; `main` does `var n = 10; bump(&n); print(n)`.
Correct semantics: `n` becomes 15.

## Root cause (pre-fix)

Address-of a SCALAR local lowered to the address of a *loaded copy*: the
`address_of` handler did `operand_temp = lowerExpr(child_0)`, and for a scalar
`ident_expr` `lowerExpr` returns a `load_local` COPY temp, so `&n` = `&(copy)`.
A store through that pointer wrote the copy; the caller's `n` was never updated.

Emitted C (pre-fix): `zT_3 = n; zT_4 = &zT_3;` — `&` of the copy.

## The fix (Task 7)

The `address_of` handler was consolidated into a `lowerLValueAddr(self, lv_node,
result_type)` dispatch (`sf/src/lower.zig`), symmetric to the assignment-side
l-value dispatch:

- **scalar local/param `ident_expr`** → `addr_of{ operand = findLocalTemp(name_id) }`,
  the REAL decl temp. It resolves via the emitter `fl_temps`/`resolveTempName` →
  `mangleLocalName` to `&<name>`. **No new LIR was needed** — Task 7 Step 1
  verified empirically that `addr_of` of the scalar's decl temp (even temp id 0)
  emits `&n`, not `&zT_0`. Emitted C (post-fix): `zT_4 = &n;`.
- **aggregate ident / global ident** → unchanged (`lowerExpr` + `addr_of`), so
  `&struct`/`&slice`/`&tagged`/`&array` stay byte-identical.
- **`index_access` (`&arr[i]`)** → the exact `base + idx` logic, moved verbatim.
- **`deref` (`&(p.*)` / `&p.*`)** → identity: returns the pointer temp, no `addr_of`.
- **`paren_expr` (`&(expr)`)** → recurses into the inner l-value.
- **`field_access` (`&base.field`)** → ICE (`iceAddrOfLValueUnsupported`); there is
  no `&base.field` emit and it has zero corpus occurrences (documented gap).

## Related GREEN repros

- `repro/deref_store_param_addr` — `&scalar_param` → `15` (was `10`).
- `repro/addr_of_deref` — `&(p.*)` (paren + deref identity) → `15` (was `10`).
- `repro/deref_store_aggregate` → `16`; `repro/deref_store_compound` (`&arr[0]`) → `15`.

## Regression evidence (Task 7)

- man/gol/mud `--dump-c89` BYTE-IDENTICAL vs parent `bf8b3fd1` (no broken form used).
- Corpus `117/14/1`. mandelbrot + game_of_life compile and run rc=0.
