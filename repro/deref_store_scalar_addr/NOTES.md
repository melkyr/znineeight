# KNOWN-FAILING repro: address-of scalar local (`&n`)

**Status:** KNOWN-FAILING (documents a latent gap). NOT a gate. Do not "fix" by
swapping the form.

- Expected-correct output: `15`
- Actual (current) output: `10` — the store through `&n` writes a *loaded copy*, so
  the caller's `n` is never updated.

## What it does

`bump(p: *i32)` does `p.* += 5`; `main` does `var n = 10; bump(&n); print(n)`.
Correct semantics: `n` becomes 15. Current zig1 prints 10.

## Root cause (separate zig1 lowering gap — NOT the deref-store bug)

Address-of a SCALAR local lowers to the address of a *loaded copy* of that local:

- The `address_of` handler (`sf/src/lower.zig:1332-1351`) special-cases
  `index_access` (`:1334` → `&arr[i]` computes a real address) but has **NO
  scalar-ident case**. For a scalar ident operand it does
  `operand_temp = lowerExpr(node.child_0)` then emits `addr_of{ operand=operand_temp }`
  → `&operand_temp`.
- For a scalar `ident_expr`, `lowerExpr` returns a **LOAD-LOCAL copy** temp
  (`sf/src/lower.zig:1642-1644`: `emitInst(load_local); return tid;`). So `&n` =
  address of the loaded copy, not of `n`.
- A store through that pointer writes the copy; the caller's `n` is unchanged.

Aggregate idents (array / slice / struct / tagged_union) return the **REAL** local
temp directly (`sf/src/lower.zig:1625-1628`), so `&arr`, `&pr`, `&slice`, `&tagged`,
and `&arr[0]` all yield real addresses and work correctly. This gap is therefore
scalar-local-only.

## Emitted C evidence (`--dump-c89`, current binary)

`main` (note lines: load `n` into copy `zT_3`, take `&zT_3`):

```c
/* main */
void zF_EA90E208_main(void) {
    int zT_3;
    int* zT_4;
    int n;
    ...
    n = zT_1;            /* n = 10 */
    zT_3 = n;            /* LOAD-LOCAL COPY of n */
    zT_4 = &zT_3;        /* &(copy), NOT &n  <-- BUG */
    zT_2 = zT_4;
    zF_623C0FB5_bump(zT_2);
    zT_6 = n;            /* reads original n, still 10 */
    __bootstrap_print_int(zT_6 ...);
}
```

`bump` stores correctly through its pointer — the store itself is fine; the pointer
just aims at the copy:

```c
/* bump */
void zF_623C0FB5_bump(int* p) {
    zT_2 = *zT_1;        /* *p */
    zT_4 = zT_2 + zT_3;  /* + 5 */
    zT_5 = p;
    *zT_5 = zT_4;        /* *p = ...  (writes the copy) */
}
```

## Relationship to the deref-store fix (which IS correct)

This is a SEPARATE gap from the deref-store-through-pointer fix. The deref-store fix
(`lowerDerefStore`, commits `5090d25a` / `55c20ff5` / `9d44671e`) correctly emits
`*ptr = ...` — verified GREEN by:

- `repro/deref_store_aggregate` → `16`
- `repro/deref_store_compound` (`&arr[0]`) → `15`

Both pass because they take `&` of an **aggregate** (real address). The store LIR is
correct; only scalar-local address-of is broken.

## Impact

Not exercised by lisp / man / gol / mud today (they only take `&` of structs/arrays),
so it does not currently block them. It is a real latent correctness gap.

## Handoff

Deferred to plan **Task 6** (investigate `&n`) and **Task 7** (fix `&n`). Do NOT fix
here.
