# zig1 C89-codegen defect fixes — Design

**Status:** Approved (operator, 2026-10-09)
**Goal:** Fix five confirmed `zig1` (Z98→C89) compiler defects so the emitted C **matches proper Zig semantics** — not merely so `gcc` accepts it — and so `z9torr` can download from real swarms.
**Driver:** `examples/torrent_example_defects.md` (D1–D5).
**Sequence:** enables the parked `z9torr` M4 items (MSE real-peer diagnostics, non-blocking handshake).
**Compiler work authorized:** this lifts the z9torr M0–M4 “compiler frozen” amendment. The seed rotates at closeout.

## §1 Scope

Five defects, each fixed to reproduce **Zig semantics**:

| Id | One line | Class |
|---|---|---|
| **D1** | A C keyword as a `union(enum)` tag emits invalid C89. | C-identifier emission |
| **D2** | A slice whose element is a synthetic composite collapses onto another nested-slice C typedef. | C-type-name emission |
| **D3** | A module-global struct whose address crosses a suspension emits a frame-save from an undeclared temp. | async frame-save emission |
| **D4** | A by-value struct-return temp assigned to a module global in a suspending function emits the same undeclared-temp frame-save. | async frame-save emission |
| **D5** | A store through a slice-index aggregate lvalue is silently lost (writes into a by-value copy). | lvalue lowering + emission |

**Out of scope:** any defect not in this list; unrelated refactors; the Z98 front-end/type-checker (these are emission/lowering defects); changing Z98 surface syntax.

## §2 Zig semantics (the reference each fix must reproduce)

- **D1.** In Zig any identifier is a valid `union(enum)` tag — `int`, `long`, `switch`, … are *not* Zig keywords, so `union(enum) { int: i64 }` is legal Zig. The C89 backend must therefore C-keyword-mangle union member names (or emit stable non-keyword member names) so *every* valid Zig tag compiles.
- **D2.** In Zig `[][]const u8`, `[][20]u8`, `[][*]u8`, `[]?T`, and `[]Tuple` are five **distinct types**. The backend must give each a distinct C typedef; today all collapse to one because a slice’s element name is taken from the element’s `name_id`, which is `0` for synthetic element types.
- **D3.** In Zig a coroutine captures referenced state correctly across a suspension. The emitted frame save must declare every temp it stores; a save must never reference an undeclared `zT_N`.
- **D4.** In Zig a by-value struct-return is materialised into a real local before it is captured; the backend must not let the struct-return temp cross the suspension undeclared.
- **D5.** In Zig `arr[i].field[j] = x` writes through the **lvalue** `&arr[i].field[j]`. The backend must address the chain once, never copy the element and write into the copy.

## §3 Defect detail (Z98 current behaviour → fix)

### D1 — C-keyword `union(enum)` tag
- **Current:** `sf/src/c89_emit.zig` `~:2008-2024` writes the variant tag **verbatim** as the C union member; `int` → `struct{ long long _0; } int;` → `gcc: expected identifier before 'int'`. `@"int"` is rejected by Z98 (`error[4]`).
- **Fix:** C-keyword-mangle union member names (a stable mapping, e.g. `zM_<name>` when `<name>` is a C keyword), consistently at the declaration and every access site; or emit numeric members with a tag→name table. Every legal Zig tag must compile.
- **Repro:** `repro/mi_matrix/union_keyword_tag_xmod/` (standalone; must compile+link+run after fix).

### D2 — synthetic slice-element typedef collapse
- **Current:** `getCTypeName` slice branch **`c89_emit.zig:1028-1036`** derives the element C name from `elem_ty2.name_id` (`:1031-1032`); synthetic element types have `name_id == 0`, so `[][]const u8` / `[][20]u8` / `[][*]u8` / `[]?T` / `[]tuple` all mangle to the empty-name string and collapse to one `Slice_*` typedef. The array branch **`:959-967`** (`emitArrayType` **`:2116-2137`**) already recurses `getCTypeName(..., elem)`; the tuple branch **`:972-979`** already uses the dense type id (`Tup_<tid>`); optional/error-set use their payload idx.
- **Fix:** derive the slice element C name by **recursion** (as the array branch does) when the element is synthetic (`name_id == 0`), or reuse the dense-type-id recipe (`syntheticTypeName` **`:882`**) so distinct synthetic elements yield distinct typedefs. Primitive/named element slices (`[]u8`, `[]i32`, `[]Struct`) must stay **byte-identical**.
- **Repro:** `repro/mi_matrix/slice_of_array_xmod/` + `slice_of_slice_xmod/` (a struct with `[][]const u8` **and** `[][20]u8`; must compile **warning-free** after fix).

### D3 — undeclared frame-save temp (global struct address across a suspension)
- **Current:** frame save/restore is emitted by `sf/src/async_state_machine.zig` `saveAllFields` **`:254-265`** / `reloadAllFields` **`:267-280`** (call sites: explicit suspend `:1189-1199`, implicit yield `:563-574`, result delivery `:587-589`), lowered to the generic `.store` arm **`c89_emit.zig:7609-7643`**. Step temps are seeded at **`async_state_machine.zig:949-955`** (`base = 2`, **`:926`**), `newTemp` `:207-211`; names resolved by `resolveTempName` **`c89_emit.zig:6614-6628`**. A save references the raw shifted id (`fld.temp_id + base`, `:259`) — if that temp’s declaration was suppressed (paths at `c89_emit.zig:3709-3713` dead, `:3571` local, `:8910`/`:8998` no-decl/global-alias, `:3485` written_flag) *without* applying the matching name substitution, the emitted `*slot = zT_N` has no declaration → `gcc: 'zT_NNN' undeclared`.
- **Fix:** declare every temp the frame save/restore stores (do not rely on a sibling step function having declared it), or allocate the frame slot without a by-value struct temp.
- **Repro:** in-example patch reproducer (the D3 two-line `peer.zig` change) — not reducible to a standalone program (recorded).

### D4 — undeclared frame-save temp (struct-return temp across a suspension)
- **Current:** same frame-save machinery; the trigger is a by-value **struct-return temporary** (`g_reader = initMsgReader(...)`) assigned to a module global inside a suspending function.
- **Fix:** materialise a struct-return temporary into a named local **before** the global store / frame save, so the saved value is a declared temp.
- **Repro:** in-example patch reproducer (the D4 one-line `peer.zig` change).

### D5 — lost store through a slice-index aggregate lvalue
- **Current:** `sf/src/lower.zig` `lowerAssignLValue` `index_access` arm **`:2484-2531`** lowers the base by **value** (`lowerExpr` `:2487`) and only takes an address for the *tuple* sub-case (`:2493-2508`); the correct sibling `lowerFieldStore` addresses nested bases at **`:2878-2928`**. Emission then chains value copies (`emitBaseIdxAccess` **`c89_emit.zig:204-267`**, `load_index` `:7593-7596`, `load_field` `:7456-7513`, `assign_index` `:7226-7271`).
- **Fix:** route non-tuple index-assign bases through address-taking exactly as `lowerFieldStore` (`(slice.ptr + idx)->field[...]` addressed once).
- **Repro:** `repro/mi_matrix/slice_index_field_store_xmod/` with a **runtime** assertion (compile-only classify cannot detect a lost write); plus the z9torr `peer_id` assertion.

## §4 Correlation hypothesis (to be confirmed by the I-tasks)

The five I-tasks run **before any fix** so we can confirm/refute correlation:
- **D3 + D4** are expected to share one root cause (the async frame-save temp-declaration discipline) and may collapse to one fix.
- **D5** is a distinct **lvalue-lowering** defect (not the same subsystem as D1/D2).
- **D1** (union member naming) and **D2** (slice element naming) are both **C-identifier/type-name emission** but otherwise independent.

If the I-tasks show D3≡D4 (same site), the operator rules whether to fix once or keep two commits.

## §5 Gates (all apply to every compiler-moving F-task)

Compiler is not `main`-frozen now; the battery is:

1. **Seed rebuild:** `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` → `<out>/zig1_5_clean`; two-hop closure `hop1 == hop2`.
2. **Corpus:** `bash scripts/corpus/classify <zig1> <outfile>` → baseline **1097 = 923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH**; **FAIL must not increase**; new repros are added as corpus dirs (auto-discovered, no manifest).
3. **Stdlib:** `bash scripts/stdlib/verify_stdlib.sh <zig1>` → **283 PASS / 0 FAIL**.
4. **Examples matrix:** all `examples/z98/*/` (currently **25**) dump+gcc+link clean.
5. **Runtime goldens:** gol / lisp / json / mud byte-identical.
6. **8 `--dump-c89` MD5 pins** (4 programs × `-fsafe`/`-ffast`): **re-baselined where a fix legitimately changes emitted C** (operator-authorized per fix; runtime equivalence required). Programs: `game_of_life`, `lisp_interpreter_curr`, `json_parser`, `mud_server`.
7. **`scripts/closeout/verify_upgraded.sh`** (`CLOSEOUT OK`) + **`scripts/check_emit_support.sh`** (7/7).
8. **z9torr tiers** (after the relevant fix): `tier1`, `tier1_cli`, `tier2`, `tier1_unit`, `tier3_encrypted`, `tier_udp_tracker`, `tier_dht`, `tier_pex` all PASS; and after D5 a **new assertion** that the sent handshake carries the real `-Z9T01-…` peer_id.

**I-tasks** create their repro(s), record the pre-fix measurement, and run the battery to confirm the repro is classified as expected (a new compiler-repro dir must not increase corpus FAIL unless it is a genuine, expected reject; a D5-type runtime defect needs a runtime assertion, not classify alone).

## §6 Risks

1. **D1/D2 may move the dump-MD5 pins** (member/typedef names are in every emitted file). Each re-baseline needs operator authorization + runtime-golden proof.
2. **D3/D4 are only reproducible in-example** (temp-layout sensitive) — the fix must be validated by the in-example patch linking clean, not only by a standalone.
3. **D5’s fix touches the core lvalue path** used everywhere — the whole corpus/examples battery is the safety net; any emitted-C change must be explained.
4. **Seed rotation** at closeout changes the compiler binary; the fixed point moves and the archive is re-cut; verify the archived binary rebuilds to itself.
5. **D2 recursion** must not perturb primitive/named slices (keep `[]u8`/`[]i32`/`[]Struct` byte-identical).

## §7 Out of scope

Unrelated defects; front-end/type-checker changes; Z98 surface syntax; the parked z9torr MSE/non-blocking items (those resume after this plan); D1 is in this plan (if the operator prefers to drop it, swap is trivial).
