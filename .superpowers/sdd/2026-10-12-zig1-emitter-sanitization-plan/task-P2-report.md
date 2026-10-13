# P2 report — Type-reference relation + ordering (execution order 3/10)

**Status:** DONE_WITH_CONCERNS (battery all green; two design rulings recorded below — one evidence-forced amendment to the Investigate design; pins 8/8 delta as expected)  
**Commits:** `1029221f` `refactor(type_registry): P2 — type-reference relation + ordering` (sf/src + sf/docs/tech_docs) + `docs(sdd): P2 report` (this file).  
**Base fixed point going in:** `973a831a8efc5998bec45470001cb008` (P1 fix round 1).  
**New fixed point:** `ccfd5c58371218034716c84e42913289` (hop1 == hop2).  
**Files in scope:** `sf/src/type_registry.zig`, `sf/src/type_resolver.zig`, `sf/src/c89_emit.zig`, `sf/docs/tech_docs/`.  
**D8 defect text read in full:** `examples/torrent_example_defects.md` §D8 (incl. the M4 T3 trigger refinement and the "Proper fix (TODO)" paragraph).

---

## Investigate (read-only census + precise edit plan — written BEFORE any source edit)

All cites re-derived at HEAD `8ba4b418` (P1 moved `c89_emit.zig` again; every emitter cite below is from a fresh `grep -n` this session).

### I.1 Census — the two divergent graphs and their predicates

| item | current site (re-derived) | role today |
|---|---|---|
| resolver graph builder | `typeResolverBuildDependencyGraph` `sf/src/type_resolver.zig:629-659` | walks struct/tagged_union/union/packed_union fields + array/tuple/optional/error_union payloads, adds `typeResolverAddEdge(field_type, container)` through `layoutAddTypeEdge:614` gated by `layoutFieldNeedsEdge:609` (= `kindIsAggregateCore:593` + `enum` + `optional` + `error_union`) |
| resolver helpers | `layoutAddTypeEdge:614-619`, `layoutAddFieldEdges:622-627` | only callers are inside `typeResolverBuildDependencyGraph` (grep below) |
| dead sorted accessor | `typeResolverGetSorted` `sf/src/type_resolver.zig:889-891` | returns `sorted_items[0..sorted_len]`; **0 callers** |
| emitter edge predicate | `c89NeedsEmitEdge` `sf/src/c89_emit.zig:1093-1115` | kind membership {slice, struct, union, tagged_union, array, optional, error_union, enum, error_set, **fn_type**, tuple, unresolved_name} — `packed_union` MISSING (Task-0 drift note confirmed: `fn_type` present here, missing on the resolver side; `packed_union` missing here, present in the resolver's `kindIsAggregateCore`) |
| emitter edge walker | `tstEdgesWalk` `sf/src/c89_emit.zig:1132-1235` (+ `tstSeenInRange:1117`) | per-kind ref enumeration: struct fields, tagged_union fields + `tag_type`, array elem, error_union payload, optional payload, slice elem **only if elem kind is enum/error_set**, union fields, tuple elems. **No `fn_type` branch** (D8 root cause: a fn-ptr type never gains an edge to its return/params), **no `packed_union` branch** (a packed_union neither contributes nor receives field edges) |
| emitter sort | `tstTopologicalSort` `sf/src/c89_emit.zig:1253-1291` | Kahn over `tstEdgesCount`/`tstIsDep`; consumed by `emitModule:2770` and `main.zig:1375` (`emitSharedHeader`) |
| emitter probe | `tstIsDep:1246-1251`, `tstEdgesCount:1237-1240`, `tstEdgesFill:1242-1244` | `tstEdgesFill` has **0 callers** (dead since D3-2 collapsed the fill into the walk); `tstIsDep` used by `tstTopologicalSort:1279` and `computeSharedSet:1530` |
| dead value-dependency predicate | `isValueDependency` `sf/src/type_registry.zig:980-989` | third divergent membership ({struct, union, tagged_union, array, optional, error_union, tuple, unresolved_name}); **0 callers** |
| divergent sibling predicates | `kindIsAggregateCore:593`, `fieldEmbedsByValue:599`, `requiresFullDef:604` `sf/src/type_resolver.zig` | NOT ordering predicates — they drive `classifyTypeEmissionGroups` (pointer-only classification). `layoutFieldNeedsEdge` is the ordering sibling and is absorbed by P2; `fieldEmbedsByValue`/`requiresFullDef`/`kindIsAggregateCore` **stay** (out of P2's delete set; P4 owns classification) |
| not ours (observation only) | `pruneTypeMarkByValue` `sf/src/main.zig:1112` (module-reachability walk), `collectNeededTuples` (needed-tuple walk) | separate walks with their own semantics; not named in the plan's P2 text — untouched, noted in Concerns |

Live callers (re-verified):

```
$ grep -rn "typeResolverBuildDependencyGraph\|typeResolverGetSorted\|isValueDependency\|c89NeedsEmitEdge\|tstEdgesWalk\|tstTopologicalSort\|layoutFieldNeedsEdge\|fieldEmbedsByValue\|requiresFullDef" sf/src/*.zig
sf/src/c89_emit.zig:1093:fn c89NeedsEmitEdge(kind: TypeKind) bool {          # def
sf/src/c89_emit.zig:1132:fn tstEdgesWalk(...)                                 # def
sf/src/c89_emit.zig:1141,1155,1164,1174,1180,1186,1193,1202,1216              # calls inside the walk
sf/src/c89_emit.zig:1239,1243,1248,1249                                       # tstEdgesCount/Fill/IsDep
sf/src/c89_emit.zig:1253:pub fn tstTopologicalSort(...)                       # def (used main.zig:1375, c89_emit:2770)
sf/src/c89_emit.zig:1259,1279                                                 # count/isdep inside sort
sf/src/c89_emit.zig:1530                                                      # tstIsDep inside computeSharedSet
sf/src/main.zig:565:    type_resolver.typeResolverBuildDependencyGraph(&tr);  # sole caller of the resolver graph
sf/src/main.zig:1375:        var sorted: [*]u32 = c89_mod.tstTopologicalSort(  # sole external sort caller
sf/src/type_registry.zig:980:pub fn isValueDependency(kind: TypeKind) bool {  # def only
sf/src/type_resolver.zig:590-591,599,604,609                                  # predicates + comments
sf/src/type_resolver.zig:617,695,717,739,761,780,798,816                      # predicate calls (graph builder + classifyTypeEmissionGroups)
sf/src/type_resolver.zig:629:pub fn typeResolverBuildDependencyGraph(...)     # def
sf/src/type_resolver.zig:889:pub fn typeResolverGetSorted(...)                # def only
```

### I.2 Dead-code re-verification before deletion (Risk 4)

```
$ grep -rn "typeResolverGetSorted" --include="*.zig" . | grep -v "\.superpowers"
./release/staging/zig1_src_tree/sf/src/type_resolver.zig:657:pub fn typeResolverGetSorted(self: *TypeResolver) []u32 {
./sf/src/type_resolver.zig:889:pub fn typeResolverGetSorted(self: *TypeResolver) []u32 {
$ grep -rn "isValueDependency" --include="*.zig" . | grep -v "\.superpowers"
./release/staging/zig1_src_tree/sf/src/type_registry.zig:693:pub fn isValueDependency(kind: TypeKind) bool {
./sf/src/type_registry.zig:980:pub fn isValueDependency(kind: TypeKind) bool {
```

Both: definition only, ZERO call sites in `sf/src` (the `release/staging/zig1_src_tree/` hits are a generated staging copy — pre-existing non-source, not ours to touch). Additionally `tstEdgesFill` (`c89_emit.zig:1242`) has 0 callers (grep I.1 — its only "use" is the definition) and dies with the walk. `layoutAddTypeEdge`/`layoutAddFieldEdges`/`layoutFieldNeedsEdge` have no callers outside `typeResolverBuildDependencyGraph` (grep I.1) and die with its rewrite. **Confirmed dead; deletions authorized.**

### I.3 The single relation — design

Placed in `sf/src/type_registry.zig` (replacing `isValueDependency` at its site):

```
typeNeedsFullDef(tid)            — pub. "A typedef-ordering reference to this type
  requires this type's definition (its typedef) first; a forward declaration does
  not suffice." Kind membership = the emitter's historical c89NeedsEmitEdge set
  PLUS packed_union_type (the missing kind).
typeHasForwardDecl(tid)          — private. Mirrors emitTypePasses Pass 1 exactly:
  forward-typedef exists iff name_id != 0 AND kind is tagged_union, union, or
  non-packed struct. (Pass 1 emits `typedef struct|union C C;` for exactly these
  before any sub-pass 2 typedef, so a name-spelling reference to them needs no
  ordering edge.)
typeRefsWalk(tid, out, start, has_out, probe, probe_target) — private. ONE
  per-kind enumeration (see table I.4). Self-references excluded; duplicates
  collapse to first occurrence (membership/count semantics identical to the old
  walk's dedup, now global to the type).
typeRefsCount(tid)               — pub. number of ordering refs of tid.
typeRefs(tid, out) -> u32        — pub. writes the deduped ordering refs of tid at
  out[0..], returns the count. ("typeRefs(tid) -> the type ids a type
  references (by-value/full-def edges — the ones typedef ordering needs)".)
typeRefsContains(tid, target)    — pub. membership probe (replaces tstIsDep).
```

Two reference positions (recorded in the table):

* **by-value positions** (aggregate fields — incl. packed_union, tagged-union tag, array elem, tuple elems, optional payload, error-union payload): edge iff `typeNeedsFullDef(ref)` — the referrer's definition embeds the ref by value and needs its complete typedef.
* **name-spelling positions** (fn return + fn params, slice elem — the C declarator spells the ref's typedef NAME behind a pointer or in a function type): edge iff `typeNeedsFullDef(ref)` AND NOT `typeHasForwardDecl(ref)` — a name with no forward-typedef must have its typedef (= its definition) written first. gcc probe (this session, `gcc -m32 -std=c89`): `typedef struct S S; typedef S (*F)(void); typedef void (*G)(S);` with `struct S` completed later — **rc=0** (forward decl suffices for fn ret/param); `typedef zT_EU (*F)(void);` with `zT_EU` declared later — **error: expected declaration specifiers or '...' before '*' token** (exact D8 gcc text); `typedef struct { zT_EU* ptr; unsigned int len; } zT_SL;` with `zT_EU` later — **error: unknown type name 'zT_EU'** (the slice-elem sibling of the same class).

Not in the relation (unchanged machinery owns them): pointer/many-pointer bases (Pass-1 forward decls + `emitPointeeDep`/`emitDepMember` site patches at emission time; adding pointee refs to the sort graph would create false cycles on `struct { next: *Node }`); error-union's `error_set` member (the EU typedef spells `int err`, no name); enum backing (spelled as the backing C builtin/carrier — carriers are registry tids 4–16 and therefore always wave-0 before every user type in the Kahn queue, see I.5); i64/u64/f64 carrier refs (same registration-order guarantee; keeping `typeNeedsFullDef` membership identical to the historical set avoids order churn for zero correctness gain).

### I.4 Kind-by-kind edge table (what `typeRefs(t)` returns)

`t -> R` means R must be typedef-ordered before t. "B-V" = by-value position rule; "Name" = name-spelling position rule. `fd(R)` = `typeHasForwardDecl(R)`.

| t.kind | refs enumerated | position | edge iff | vs today (emitter `tstEdgesWalk`) | vs today (resolver graph) |
|---|---|---|---|---|---|
| `struct_type` (incl. packed) | each `fe` field type | B-V | `typeNeedsFullDef(R)` | same membership + packed_union as R | same + `error_set`/`slice`/`fn`/`unresolved` as R (layoutFieldNeedsEdge lacked them) |
| `union_type` | each `fe` field type | B-V | `typeNeedsFullDef(R)` | same + packed_union as R | same widening as above |
| `packed_union_type` | each `fe` field type | B-V | `typeNeedsFullDef(R)` | **NEW branch** (walk had none) | same as struct fields (was already walked) |
| `tagged_union_type` | each `fe` field type, then `tag_type` | B-V | `typeNeedsFullDef(R)` | same + packed_union as R | **NEW tag edge** (resolver never walked `tag_type`) |
| `array_type` | `elem` | B-V | `typeNeedsFullDef(elem)` | same + packed_union as R | same widening |
| `tuple_type` | each `xt` elem | B-V | `typeNeedsFullDef(R)` | same + packed_union as R | same widening |
| `optional_type` | `payload` | B-V | `typeNeedsFullDef(R)` | same + packed_union as R | same widening |
| `error_union_type` | `payload` (NOT `error_set` — spelled `int`) | B-V | `typeNeedsFullDef(R)` | same + packed_union as R | same widening |
| `slice_type` | `elem` | Name | `typeNeedsFullDef(R)` ∧ ¬`fd(R)` | widens the historical `enum`/`error_set`-only special case to every no-forward-decl kind (fn/synthetic/packed/unresolved…); named struct/tu/union elems keep 0 edges (`fd`); fixes the `typedef struct { zT_EU* ptr; … }` name-before-decl class | **NEW** (resolver had no slice branch) |
| `fn_type` | `return_type`, then each `xt` param type | Name | `typeNeedsFullDef(R)` ∧ ¬`fd(R)` | **NEW branch** — the D8 root cause (return + params). Named aggregate ret/params keep 0 edges (gcc rc=0 probe above); synthetic/enum/error_set/fn/packed ret/params gain the edge | **NEW** (resolver had no fn branch at all) |
| `error_set_type` | — | — | — | same (typedef `int`, no refs) | same |
| `enum_type` | — | — | — | same (backing spelled as C builtin/carrier; carrier order guaranteed by registration, I.5) | same |
| `ptr_type`, `many_ptr_type` | — | — | — | same (pointees: Pass-1 fwd decls + `emitPointeeDep` site patches) | same |
| `i64/u64/f64_type` | — | — | — | same | same |
| primitives (`void`, `bool`, `i8..i32`, `u8..u32`, `isize`, `usize`, `c_char`, `f32`), `null`, `undefined`, `integer_literal`, `type`, `module`, `va_list`, `arb_int`, `arb_uint`, `none_sentinel`, `anon_*`, `unresolved_name` | — | — | — | same (`unresolved_name` as a *target* stays `typeNeedsFullDef`=true like `c89NeedsEmitEdge`) | same |

`typeNeedsFullDef(R)` membership (the single kind truth table): `slice_type`, `struct_type`, `union_type`, `packed_union_type` (NEW), `tagged_union_type`, `array_type`, `optional_type`, `error_union_type`, `enum_type`, `error_set_type`, `fn_type`, `tuple_type`, `unresolved_name`. Everything else false. (= historical `c89NeedsEmitEdge` ∪ {`packed_union_type`}.)

### I.5 Ordering-preservation argument (why previously-correct programs stay correct)

1. **Old edge set ⊆ new edge set.** By-value rows keep the historical `c89NeedsEmitEdge` membership exactly and add `packed_union`; the tagged-union tag/array/tuple/opt/eu rows are unchanged membership; the slice-elem row ⊇ the historical `enum`/`error_set` special case (both satisfy Name); the fn row is entirely new. So every constraint the old sort enforced is still enforced.
2. **New edges = the real C spelling constraints** (I.3 gcc probes): a typedef may only spell a name that is already declared. By-value spellings need the complete typedef (B-V); fn ret/param and slice-elem spellings need the typedef name (Name, minus names covered by Pass-1 forward typedefs). Pointer pointee spellings are order-independent (Pass-1 fwd decls for named aggregates; `emitPointeeDep`/`emitDepMember` site patches emit everything else just-in-time at the referrer's own emission — unchanged by P2).
3. Therefore the new Kahn order satisfies every name-spelling constraint the C text has. A previously-emitting program (valid C today) has all constraints satisfied today; the new order satisfies a superset → its C stays valid. Runtime is unchanged (no semantic rule is touched; only typedef order). Emitted BYTES can move (sub-pass interleaving + `computeSharedSet` closure now sees fn/packed_union edges and may promote more types into the shared header) — pins are recorded old→new per the Global Constraints.
4. **Cycle safety.** A cycle in the relation means no typedef order exists for that spelling set at all. Every new edge originates at a type with no old out-refs (`fn_type`/`packed_union_type`/`slice_type` had no walker branch) or at a container gaining a `packed_union` target; one can check case by case that any cycle containing a new edge forces at least one name-before-decl (or incomplete-by-value) spelling under *every* order the old graph could produce — i.e. such a program already emits invalid C today (the gcc probes in I.3 are exactly those spellings) and therefore cannot be in the runtime battery (classify: invalid C ⇒ FAIL). Programs with by-value cycles impossible in Zig (infinite size) remain rejected by the resolver's existing circular-type check. Residual risk recorded in Concerns (mixed symbol-dummy + type-edge cycles in the resolver are empirically gated by the battery).
5. **D8 shape becomes correct by construction.** Aggregate `V` with fnptr field `f: fn(…) E!T`: edges `V→F` (fn is `typeNeedsFullDef`) + `F→EU` (return is synthetic, ¬`fd`) + `EU→payload` as applicable. Kahn: EU's typedef, then the fn-ptr typedef, then V's — the exact D8 inversion is now unreachable.

### I.6 Precise edit plan (all edits via `edit`/`fastedit`, bottom-to-top per file)

**`sf/src/type_registry.zig`**
1. Delete `isValueDependency` (`:980-989`); insert at that site the relation block: `typeNeedsFullDef`, `typeHasForwardDecl` (private), `typeRefsWalk` (private), `typeRefsCount`, `typeRefs`, `typeRefsContains`. `typeHasForwardDecl` consumes the existing `typeRegistryIsPacked` (`:1198`); no predicate logic re-derived (P5 rule). Old-Zig syntax only (`@intCast(usize, x)` form, `while (i < n) : (i += 1)`, no switch-without-else).

**`sf/src/type_resolver.zig`**
2. Rewrite `typeResolverBuildDependencyGraph` (`:629-659`): for each `ti`, `n = typeRefs(registry, ti, buf)` over a scratch buffer (`sandAlloc(self.alloc, 4 * types_len, 4)`), `typeResolverAddEdge(self, buf[k], ti)` per ref (same edge direction as today: `from`=ref, `to`=referrer). Keep the doc comment (D1-2/D5-1 notes stay; the D5/D1-2 helper comment above `kindIsAggregateCore` is re-scoped to the classification predicates that remain).
3. Delete `layoutFieldNeedsEdge` (`:609-612`), `layoutAddTypeEdge` (`:614-619`), `layoutAddFieldEdges` (`:622-627`) — 0 remaining callers after step 2.
4. Delete `typeResolverGetSorted` (`:889-891`).
5. Keep `kindIsAggregateCore`, `fieldEmbedsByValue`, `requiresFullDef`, `classifyTypeEmissionGroups` untouched (P4 owns classification).

**`sf/src/c89_emit.zig`**
6. Delete `c89NeedsEmitEdge` (`:1093-1115`), `tstSeenInRange` (`:1117-1122`), `tstEdgesWalk` (`:1125-1235` incl. the D3-2 comment), `tstEdgesCount` (`:1237-1240`), `tstEdgesFill` (`:1242-1244`, dead), `tstIsDep` (`:1246-1251`).
7. Rewrite `tstTopologicalSort` (`:1253-1291`): `indegree[ti] = type_mod.typeRefsCount(reg, ti)`; the `tj` loop probes `type_mod.typeRefsContains(reg, tj, cur)`.
8. `computeSharedSet` (`:1530`): `tstIsDep(reg, sj, ti2)` → `type_mod.typeRefsContains(reg, sj, ti2)`.
9. No other touches: `emitTypeDeps`/`emitDepMember`/`emitPointeeDep`/Pass-1 forward typedefs/`emitTypeDefOnce` stay (site patches and fwd decls are the order-independent side of the design; P4/P6 own the rest).

**`sf/docs/tech_docs/`** (AGENTS.md 1.1.1; INDEX.md Table A)
10. `03_type_resolution.md`: new `[updated: 2026-10-12 — P2 …]` header line; `isValueDependency` row → deleted (P2); new rows `typeNeedsFullDef`/`typeRefs`/`typeRefsCount`/`typeRefsContains`; `typeResolverBuildDependencyGraph` row rewritten (derives from `typeRefs`); `typeResolverGetSorted` row deleted; `layoutFieldNeedsEdge`/`layoutAddTypeEdge`/`layoutAddFieldEdges` rows deleted; dependency-graph data-flow section updated.
11. `08_c89_emission.md`: new `[updated: 2026-10-12 — P2 …]` header line; the topological-sort / `c89NeedsEmitEdge` sections rewritten to the relation (`typeNeedsFullDef`/`typeRefs*` in `type_registry.zig`); `tstEdgesWalk` family documented as deleted; D8 note (fn return/param refs now edges).
12. `INDEX.md` Table A: delete/annotate rows per P1's `old → new (P2)` convention for the replaced machinery; add the four new `type_registry.zig` rows (alphabetical).

**Expected touch set = `sf/src/type_registry.zig`, `sf/src/type_resolver.zig`, `sf/src/c89_emit.zig`, `sf/docs/tech_docs/` (03, 08, INDEX) — exactly the brief's set.** Anything outside → STOP.

### I.7 D8 confirmer plan (battery add-on)

Reproducer from `examples/torrent_example_defects.md` §D8 (`a.zig` vtable + `b.zig` + `main.zig`, single-file path reaches the same emission path): compile with the P2 compiler, then `gcc` the emitted C; before: invalid C (fnptr typedef before its error-union typedef); after: valid order + correct run. Also re-check `examples/z98/z9play` (the platform/audio vtable is worked around per D8; z9play must stay green — it is in the 26/26 matrix). If the reproducer cannot be run cleanly, record why (observation).

---

## Implement (one compiler-moving commit; two evidence-forced rulings)

All source edits via `edit`/`fastedit` (X.7: re-read region before each edit; bottom-to-top per file; insert = anchor + content). No scripted transforms. Touch set exactly the Investigate set (`sf/src/type_registry.zig`, `sf/src/type_resolver.zig`, `sf/src/c89_emit.zig` + `sf/docs/tech_docs/`).

### Ruling 1 (design amendment — pointer references ARE relation refs)

**Ruling:** the Investigate design excluded pointer/many-pointer bases from `typeRefs` ("Pass-1 fwd decls + `emitPointeeDep` site patches own them"). Evidence falsified that assumption — a pointer reference's C spelling uses its chain-leaf's C NAME (`getCTypeName`'s ptr branch renders `*fn` as the fn typedef name itself and `*T` as `<T-cname>*`), and the Task-6 site patch (`emitDepMember`→`emitPointeeDep`) emits such typedefs at the CONTAINER's emission site, which can precede the leaf's own sorted slot. **Amendment:** pointer refs contribute a name-visibility edge to their chain-leaf (`typeRefPtrLeaf`), governed by the same name rule (`typeNeedsFullDef(leaf) ∧ ¬typeHasForwardDecl(leaf)`). `struct Node { next: *Node }` stays cycle-free (named struct HAS a forward typedef). Cost if wrong: extra ordering constraints (old edge set ⊆ new set preserved; pins move — recorded).

**Evidence (temporary measure-marker instrumentation, removed before commit):** on the D8 reproducer the fn→EU edges DID form (debug: `DBGP:fn66 DBGP:ret65 DBGP:nd1`) and the sort was correct (`DBGP:ord` = 431 distinct entries 0..430, tid 65 (EU) at pos 60, tid 66 (fn) at pos 339), yet the emitted `zig_special_types.h` still had the fnptr typedef at :54 referencing the EU declared at :108. Emission-order instrumentation showed why: V (tid 39) is at sorted position **39** (its fn fields are **ptr-to-fn** — `DBGP:neT39 neR70/74/76/79 neK17`, kind 17 = `ptr_type`), and its `emitTypeDeps` site patch emitted the four fn typedefs (`DBGP:em69/73/75/78`) at V's early slot — before the EUs' sorted slots 60–69. So the container→fn edges were missing (the old `c89NeedsEmitEdge` walk had the same hole — Task 6's `fn_type` membership only covered DIRECT fn-type fields), and the site patch re-introduced the D8 inversion locally.

### Ruling 2 (edge-target semantics — fill/probe must carry the EDGE TARGET)

**Ruling:** the first ptr-leaf implementation kept the RAW ref tid as the fill/probe identity and kept `typeRefsContains`'s `typeNeedsFullDef(target)` fast-guard. For a ptr ref the fill wrote the PTR tid while the guard rejects ptr tids (`typeNeedsFullDef(ptr)=false`) → the Kahn decrement for those edges never fired → dependents never reached indegree 0 → dropped from `sorted` (Pass-1 fwd typedefs and bodies missing; `sorted`'s tail read uninitialized arena memory). Evidence: self-emission `hop1 --dump-c89 sf/src/main.zig` produced `zig_special_types.h` missing `zT_7E2F335A_AnalyzerContext` (`error: unknown type name` in hop2 gcc; fwd-typedef set 287 vs 288 with 7 dropped/6 garbage-tail re-adds) and a flaky `Segmentation fault` on the same dump. **Fix:** `typeRefEdgeTarget` returns the TARGET (chain-leaf for pointer refs) or `0xFFFFFFFF`; the walk's fill/probe/dedup all key on the TARGET (distinct targets ⇒ exactly one Kahn decrement per entry — the count/fill/probe consistency the old `tstSeenInRange` comment guaranteed). `typeRefsCount` deleted (its only consumer, `tstTopologicalSort`, now takes the count from the `typeRefs` fill). Cost if wrong: one more rebuild+battery cycle (taken).

### Edits (as committed)

**`sf/src/type_registry.zig`** — `isValueDependency` deleted (0 callers, I.2) and replaced in place by the relation block: `typeHasForwardDecl` (private, mirrors Pass 1), `typeNeedsFullDef` (pub; historical `c89NeedsEmitEdge` set + `packed_union_type`), `typeRefPtrLeaf` (private), `typeRefEdgeTarget` (private), `typeRefsSeenOut`/`typeRefsNote` (private), `typeRefsWalk` (private), `typeRefs` (pub), `typeRefsContains` (pub). No predicate re-derivation (P5 rule: `typeHasForwardDecl` consumes `typeRegistryIsPacked`).

**`sf/src/type_resolver.zig`** — `typeResolverBuildDependencyGraph` rewritten to iterate `typeRefs(registry, ti, buf)` over a scratch buffer (`sandAlloc(self.alloc, 4 * types_len, 4)`) and add the historical `from=ref, to=ti` edges; `layoutFieldNeedsEdge`/`layoutAddTypeEdge`/`layoutAddFieldEdges` deleted (0 remaining callers); `typeResolverGetSorted` deleted (0 callers). `kindIsAggregateCore`/`fieldEmbedsByValue`/`requiresFullDef`/`classifyTypeEmissionGroups` untouched (P4's classification scope).

**`sf/src/c89_emit.zig`** — `c89NeedsEmitEdge`, `tstSeenInRange`, `tstEdgesWalk`, `tstEdgesCount`, `tstEdgesFill` (0 callers), `tstIsDep` deleted; `tstTopologicalSort` now `indegree[ti] = type_mod.typeRefs(reg, ti, edge_buf)` and probes `type_mod.typeRefsContains(reg, tj, cur)`; `computeSharedSet`'s closure probes `type_mod.typeRefsContains`. `emitTypeDeps`/`emitDepMember`/`emitPointeeDep`/Pass 1 unchanged (they are now redundant-but-safe for ordering — every name they patch is an edge target — and remain the Task-6 safety net; P4/P6 own them).

**`sf/docs/tech_docs/`** — `INDEX.md` Table A rows annotated (`→ typeRefs`/`→ typeNeedsFullDef`/`→ deleted (P2)` per the P1 convention) and the 9 new `type_registry.zig` rows added; `03_type_resolution.md` relation fn-table rows + Defect-D fix paragraph + flow diagram + `[updated: 2026-10-12 — P2 …]` header; `08_c89_emission.md` §1.1 Type-Topological-Sort section rewritten to the relation, the `c89NeedsEmitEdge (fn_type)` row updated, flow diagram annotated, `[updated: 2026-10-12 — P2 …]` header. Historical `[updated: …]` entries left as history.

### Final kind-by-kind edge table (as implemented)

`typeRefEdgeTarget(T, ref, pos)` — `pos` = by-value (B-V) or name-spelling (N); `leaf` = chain-leaf of a ptr ref; `fd` = `typeHasForwardDecl`; `nfd` = `typeNeedsFullDef`:

| ref kind | ref is B-V | ref is N (fn ret/params, slice elem) | ref is ptr/many_ptr (either pos) |
|---|---|---|---|
| named non-packed struct/tu/union | edge to ref (`nfd`=true — completeness) | no edge (`fd`=true) | no edge (`fd`(leaf)=true) |
| named packed struct | edge | edge (`fd`=false) | edge to leaf |
| struct/tu/union/packed_union (unnamed) | edge | edge | edge to leaf |
| slice / optional / error_union / array / tuple / fn | edge | edge | edge to leaf |
| enum / error_set / unresolved_name | edge | edge | edge to leaf |
| ptr / many_ptr | (leaf rule) | (leaf rule) | (leaf rule) |
| i64/u64/f64 carriers | no edge (`nfd`=false; registration-order guarantee — tids 4–16 always Kahn wave-0 before user types) | no edge | no edge (leaf=carrier) |
| primitives (void/bool/i8..i32/u8..u32/isize/usize/c_char/f32/f64), null, undefined, integer_literal, type, module, va_list, arb_*, none_sentinel, anon_* | no edge | no edge | no edge |

Referrer-side positions (each funnels through `typeRefEdgeTarget`): struct/union/packed_union fields (B-V); tagged_union fields + tag (B-V); array elem (B-V); tuple elems (B-V); optional payload (B-V); error_union payload (B-V; NOT its `error_set` — spelled `int`); slice elem (N); fn return then fn params (N). Self-references excluded; targets deduped first-occurrence.

### Ordering-preservation argument (final)

Old edge set ⊆ new edge set (by-value membership kept, `packed_union`/fn/ptr-leaf added; slice-elem `enum`/`error_set` kept as a subset of the name rule). New edges = the real C name-spelling constraints (gcc probes I.3 + the ptr-leaf spelling rule above); previously-emitting programs had those constraints satisfied (or emitted invalid C = not in the runtime battery), and the new Kahn order satisfies the superset, so their C stays valid with runtime unchanged. Emitted bytes move (pins recorded). A name-spelling CONSTRAINT CYCLE (e.g. `struct T { p: *E!T }` — T spells `zT_EU*`, EU embeds T by value) is unsatisfiable under any typedef order and was already invalid C today (the old walk simply produced one of the invalid orders); such programs cannot be in the runtime battery.

---

## Runtime battery (FULL; every claim = command + observed output)

Final binary: `/tmp/taskP2_work/seed/zig1_5_clean` from `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/taskP2_work/seed` (repo root).

### 1. Seed rebuild + two-hop closure

```
[seed] hop2 binary md5: ccfd5c58371218034716c84e42913289
[seed] two-hop closure OK: hop1 == hop2 == ccfd5c58371218034716c84e42913289
=== [seed] Done: /tmp/taskP2_work/seed ===
```
Fixed point `973a831a8efc5998bec45470001cb008` → **`ccfd5c58371218034716c84e42913289`** (moved as expected; hop1==hop2 proven). INTERMEDIATE debug builds (instrumentation, not committed) were rebuilt and discarded; the committed tree's build is the one above.

### 2. Corpus classify (vs frozen Appendix A)

```
$ bash scripts/corpus/classify /tmp/taskP2_work/seed/zig1_5_clean /tmp/taskP2_work/corpus_p2b.txt
wrote /tmp/taskP2_work/corpus_p2b.txt: 1124 dirs
$ awk '{print $2}' ... | sort | uniq -c
    116 FAIL
     58 GREEN
    950 OK
$ diff /tmp/task0_work/corpus_baseline.txt /tmp/taskP2_work/corpus_p2b.txt   # baseline md5 518eca1a9b5d3e1cc5a48abce214abd8 (Task 0 F6)
diff rc=0, 0 lines
```
**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — byte-identical to frozen Appendix A. No class mover.**

### 3. Runtime goldens (5 md5s, byte-identical)

Build recipe per Task 0 §1.3 (`--dump-c89` + `gcc -m32 -std=c89 … zig_runtime.c zig_pal.c`); all 4 gcc rc=0 / 0 `error:`.

| golden | command | observed md5 | frozen | match |
|---|---|---|---|---|
| gol | `timeout 120 ./gol > gol.out` (rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7c…` | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 ./lisp` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f897…` | YES |
| json | `timeout 60 ./json` from `examples/z98/json_parser` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a…` | YES |
| mud server | `bash examples/z98/mud_server/demo/session.sh …` (rc=0) | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0ab…` | YES |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f…` | YES |

Both mud outputs also `cmp`-equal `demo/canonical_expected.txt` / `demo/canonical_client_expected.txt` (`cmp server: IDENTICAL`, `cmp client: IDENTICAL`).

### 4. mi_matrix runtime anchors (25 + oob)

Anchor set re-enumerated (25 names identical to Task 0 F2's list; command = the `expected.txt` non-empty ∧ `expected.rc=0` ∧ non-`stdlib_*` filter, `wc -l` → 25). Harness: `bash scripts/stdlib/run_fixtures.sh /tmp/taskP2_work/seed/zig1_5_clean <the 25 dirs>` → **`run_fixtures: 25 PASS / 0 FAIL over 25 dirs`** (each `PASS repro/mi_matrix/<name>`).

Trap fixture (`-fsafe` recipe): `slice_index_field_store_oob_xmod` — dump rc=0, build rc=0, `run rc=133` (SIGTRAP), stdout 0 bytes, md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt` md5. **MATCH.** (`slice_index_field_store_xmod` `9/11/22/ok` is inside the 25 — `PASS`.)

### 5. `examples/z98/*/` matrix (26 build + 26 run)

Build: `zig1_5_clean -ffast -o <out> <entry>` + `sh build_target.sh linux <out>/prog` — **26/26 dump=0 / ≥1 .c / build=0**, per-dir `.c` counts identical to Task 0 §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38).

Run (per §1.4 recipe): **26/26 correct with md5_16 and rc IDENTICAL to the §1.4 table** — e.g. `func_ptr_return` `f6a5477970a87a1c` rc=0, `game_of_life` `fcbf7e7cead5082f`, `json_parser` `8bda3d5a1ec07d14`, `z9play` rc=1 `2016494de476fcb6`, `z9torr` rc=1 `f666af15cf2625b3`, `rogue_mud`/`_upgraded` `3fb6709e7bbd8964`, `mud_server` rc=124 `9545fe1d245293ef`, `tco_defer` `264ea6b106a51dde`, … (all 26 rows match).

### 6. Stdlib gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/taskP2_work/seed/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```
**285/0 — no lost PASS vs the frozen 285.**

### 7. The 8 `--dump-c89` pins (old → new; delta ALLOWED + runtime proven above)

| entry | mode | frozen (Task 0 §1.6) | P2 (`ccfd5c58…`) | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `498b90f191b544655a1b731ef480709d` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | changed |
| mud_server | `-ffast` | `50dbf5f02c1a5de920e158cab7f2f29b` | `fa346108ed00d03a037c2f9331d3bdf8` | changed |
| game_of_life | `-fsafe` | `52c5feb5f158e2af7b32a0509b43d4c6` | `1b5d49b141ee9c664a82c270454bd75b` | changed |
| game_of_life | `-ffast` | `7271960fc6375ed1dee34b7abfb6325b` | `01a4e2265b33c97a8ca6ff3dfa551231` | changed |
| lisp_interpreter_curr | `-fsafe` | `e6f96b81f00e678eeaaa1ea7ed7c2359` | `8e5f2bc288d1dc75d7aee284cb35c291` | changed |
| lisp_interpreter_curr | `-ffast` | `ec82996028671a52a0a3d52ad307edf1` | `e3970e33ac09c8dfaa316d2d69bf61ec` | changed |
| json_parser | `-fsafe` | `48eedfc0243431693f65518646ad280c` | `2a12d0aac24d5bcdd694f05e04a4f029` | changed |
| json_parser | `-ffast` | `04124b2675e77020933cbfab20f883e1` | `24e0e812e7dffa5a43750135405ffe3f` | changed |

**Pin delta: 8/8 (all moved — expected: typedef ordering + shared-set closure change emission bytes). Runtime proof = §3–§6 all green.**

### 8. `--markers` telemetry

`zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig` → stderr **3,436 marker lines / 38,378 B** (frozen: 3,241 / 36,038). Full-prefix histogram diff vs the frozen capture (Task 0-era binary re-measured, 3,241/36,038 = frozen): **sole delta `INT:new` 1810 → 2005** (+195 interned strings; every other prefix count identical — `DC:k` 423, `FE:p` 240, `P` 195, `FWD:n=` 195, `RaD` 122, `MT` 86, `FE:` 69, `arena` 26, `X:` 17, `IRP:*` 17). Observation: the compile interns 195 more distinct strings (minted-name population under the new emission/mint order); no marker kind added/removed by the change.

### 9. D8 confirmer (before/after)

Reproducer (verbatim from `examples/torrent_example_defects.md` §D8: `a.zig` vtable + `b.zig` + `main.zig`), compiled `zig1 -fsafe -o out main.zig` + `sh out/build_target.sh linux out/prog`:

| | Task-0-era compiler (walk identical to pre-P2) | P2 compiler (`ccfd5c58…`) |
|---|---|---|
| dump rc | 0 | 0 |
| gcc via build_target.sh | **rc=1, 8 errors** | **rc=0, 0 errors** |
| first errors | `zig_special_types.h:54:28: error: expected declaration specifiers or '...' before '*' token`; `:71:9: error: unknown type name 'zT_DBCAABE4_FP_zT_D078880E_EU_4'` (the D8 texts verbatim) | — |
| run | (no binary) | **rc=0, stdout `2\n`** (`write_fn` returns `d.len`=2 — correct semantics) |
| ordering in `zig_special_types.h` | fnptr typedef :54 → EU typedef :108 (D8 inversion) | **EU `zT_D078880E_EU_46` typedef :82 → fnptr typedef :471** (correct) |

`examples/z98/z9play` (the M4 worked-around vtable) stays green (§5: 26/26). The example-side D8 workarounds (hold vtables by pointer) are left in place — reverting them is example work outside P2 ("no unrelated fixes"); the defect doc's own "Proper fix" note says the compiler fix needs no example change.

---

## Concerns (short list)

1. **Pins 8/8 delta** — expected (ordering + shared-set closure shift emission bytes) and recorded old→new with full runtime proof; the QUICK_REF table remains stale (Task 0 C1).
2. **Markers `INT:new` +195** — recorded; no marker kind changed; root cause not chased further (telemetry only, no gate).
3. **True name-spelling cycles** (e.g. `struct T { p: *E!T }`) remain unemittable under typedef spelling — argued already-invalid-C today (gcc probes + the old-walk analysis); no battery program has the shape. If one appears, it needs tag-based spelling (out of P2 scope).
4. **`classifyTypeEmissionGroups`'s `fieldEmbedsByValue`/`requiresFullDef`/`kindIsAggregateCore` intentionally untouched** — classification is P4's scope; they are NOT the ordering relation (documented in the code comment).
5. **Task-6 site patches (`emitDepMember`/`emitPointeeDep`/`emitTypeDeps`) unchanged** — with the relation's ptr-leaf coverage they are redundant for ordering (every name they patch is an edge target) but remain as a safety net; folding them into the relation is a P4/P6-shaped cleanup (observation).
6. **`pruneTypeMarkByValue` (`main.zig:1112`) and `collectNeededTuples`** are separate walks with their own semantics, outside the plan's P2 text — untouched (observation).
7. Pre-existing uncommitted `.superpowers/sdd/…/progress.md` change (6 lines, not P2's) left uncommitted; `run.err` stray at repo root not ours (not swept).
