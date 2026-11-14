# Compiler Memory Optimization (Waste Elimination) Design Spec

**Date:** 2026-08-14
**Status:** Approved by operator (scope: full — bugs + all optimizations; ordering: interleaved by impact; depth: systematic all 37 collections).

## 1. Goal

Eliminate the ~2× copy-into-bump allocation waste across the compiler's growable collections, fix the two self-compile blockers, and reclaim static BSS so that **zig1 self-compiles end-to-end under 16 MB with measured margin**. This is the F-plan that follows the memory investigation (spec `2026-08-14-memory-investigation-design.md`; reports I-M1/I-M2/I-M3 in `.superpowers/sdd/`).

Success criteria (all must hold):
- Self-compile (`sf/src/main.zig`) completes: no scratch OOM, no ASan parser crash.
- 4 MD5 gates byte-identical (gol/lisp/json/mud — output preservation).
- Corpus 252 dirs: `OK=246 / FAIL=2 / ICE=0 / CRASH=0 / GG=4` (FAIL=2 = `field_store_drop` + `self_embed_optional_cycle`).
- 21-example matrix 21/21 dump/gcc/link; `test_analyzer_bin` PASS.
- `--track-memory --markers` shows reduced per-arena peaks; static BSS trimmed.

## 2. Problem Statement

Prior investigation established:
- **B1 (scratch OOM):** token array (`import_resolver.zig:16-26`) grows ×2 copy-into-bump; `c89_emit.zig` (5,866 ln) needs ≈3.49 MB scratch vs 2 MB cap. Failing alloc `3,492,060 − 1,919,196 = 1,572,864 B = 65,536×24`. Shortfall ≈1.40 MB.
- **B2 (parser ASan):** `parserParseUnionType` (fixed `fields_buf[256]`) stack-buffer-overflow, same family as `parserParseEnumType`. Latent memory-corruption, fires before the OOM.
- **Systemic waste:** `sandReallocInPlace` (`allocator.zig:55-65`) has 0 call sites → all 37 growable collections copy-into-bump (~2× waste). Hash maps (`util/hash.zig`) leak 3 arrays per grow.
- **Hidden risk:** `type_db` 128 KB stack arena (`main.zig:155-157`) OOM is `catch unreachable` panic (`type_registry.zig:128-129/148`), invisible to `--track-memory`.
- **Over-provisioning:** 14 MB static BSS; live combined peak ≈7.9 MB after F1+F2 → ~6 MB dead headroom.
- **Dead code:** module-arena `ctx.dep_graph` (`main.zig:164`) never populated.

Verdict (I-M3): self-compile *fits* in 16 MB with ~8 MB margin (memory-only) once F1+F2 land; the real RAM risk is BSS; end-to-end verification is blocked by B2.

## 3. Strategy — three levers

Growth-factor shrink (×2→×1.5) is **rejected**: cumulative copy waste is ≈2N for ×2 but ≈3N for ×1.5. The only real levers:

1. **Exact-size** — count-first or two-pass; allocate final size in one shot (no dead copies).
2. **Grow-in-place** — `sandReallocInPlace` when the array is arena-tail; else copy fallback.
3. **Per-scope reset** — reset scratch per function/phase to bound peak (dead copies reclaimed on reset).

## 4. Shared primitives (build once, reuse across all collections)

- **`sandTryReallocInPlace`** (new, `allocator.zig`): returns whether the array is arena-tail and extends in place; returns false otherwise so the caller falls back to copy-into-bump. Must include the tail-guard check (array `end == sand.pos`).
- **Exact-size helpers** for growable arrays: allocate the final size in one `sandAlloc` when the element count is known (two-pass or count-first).
- **Hash-map grow fix** (`util/hash.zig`): pre-size buckets at init from an expected-size hint OR grow-in-place; eliminate the 3-array-per-grow leak.

## 5. Per-collection assignment

Each of the 37 cataloged collections (I-M2 report) is assigned a lever. Scratch collections additionally bound via per-scope reset.

| Arena | Collections | Lever |
|---|---|---|
| scratch | token array (#1) | exact-size (two-pass) |
| scratch | lexer `string_buf` (#2) | per-scope reset / exact-size |
| scratch | parser child/decl/case buffers (#3) | in-place (parser stack arena) |
| scratch | per-phase DepGraph (#4), TypeResolver edges/worklist (#5), sema arrays (#6), analyzer defer_queue (#7), lowerer stacks/maps (#9,#10), c89 caches (#11) | per-scope reset + in-place |
| scratch | LIR insts/blocks/hoisted_temps (#8) | per-function reset + exact-size |
| module | AST nodes/extra_children/values/fn_protos (#12–16) | exact-size / pre-size |
| module | ResolvedTypeTable (#17), CoercionTable (#18), LirFunctionArray (#19), GlobalDeclArray (#20), enum/error/call maps (#21) | in-place / pre-size |
| module | `ctx.dep_graph` (#22, dead) | remove |
| perm | StringInterner entries/buckets (#23–24) | pre-size buckets (F6) |
| perm | source text + line_offsets (#25), SourceFileArray (#26), diagnostics (#27) | exact-size / pre-size |
| perm | ModuleRegistry modules/edges/queue/dirs (#28–29), path_to_id (#30) | in-place / pre-size |
| perm | SymbolRegistry tables (#31), const_alias_prepass (#32), classifyTypeEmissionGroups (#33) | in-place / exact-size |
| type_db (128 KB stack) | types/payloads/fe-em-xt-xn/caches (#34–37) | in-place + soft-OOM + peak exposure |

## 6. Task sequence (interleaved by impact)

1. **F-TOKEN** (F1) — two-pass token count → exact-size token array (`import_resolver.zig:16-47`). Unblocks scratch OOM (~1.57 MB).
2. **F-PARSER** (B2) — growable fields buffer in `parserParseUnionType` + `parserParseEnumType`. Unblocks self-compile end-to-end.
3. **F-PRIMITIVES** — `sandTryReallocInPlace` + exact-size helpers + hash-map grow fix (foundation).
4. **F-AST** (F2) — pre-size/exact-size AST store nodes/extra_children (~2.5 MB module).
5. **F-LIR** (F3) — per-function LIR scratch reset (~0.5–1 MB).
6. **F-HASHMAP** — migrate hash maps to pre-size/in-place (cross-cutting).
7. **F-TYPEDB** (S2) — expose `type_db` peak via `--track-memory`; `catch unreachable` → soft OOM (`pal.exit(1)`).
8. **F-SWEEP** — migrate remaining scratch/module/perm collections (symbol tables, source manager, diagnostics, module registry, type-registry payload arrays, interner buckets, lowerer/sema/analyzer stacks) to the three levers.
9. **F-SOURCE** (F4) — read source into perm (avoid scratch→perm double materialize).
10. **F-PARSEARENA** (F7) — enlarge parser arena 4 KB (correctness).
11. **F-DEADCODE** (S3) — remove `ctx.dep_graph` + dead buffers.
12. **F-RESIZE** (F5/S4) — re-measure, then resize arenas down (perm 4→3, module 8→6 candidates) to trim BSS.
13. **F-GATE** — final gate sweep + `--track-memory` re-measure + docs reconciliation.

## 7. Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — ⭐ SUBAGENT CHEAT-SHEET (lines 1-60). Copy exact commands.
- **Compiler under test:** `/tmp/fx_subfolder/zig1`. **`sf/build/out_release/` is WEDGED — never touch; use timeouts.**
- **Output must stay byte-identical** — every fix must preserve the emitted C89 exactly (4 MD5 gates). Any change to emitted C is a regression.
- **Editing:** `edit`/`fastedit` only. NO sed/python/bulk transforms.
- **The plan is the ONLY authority.** STOP on any issue.
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps; `@intCast` for i32↔usize; no pointer captures; switch requires `else`.
- **Memory gates mandatory:** every fix-task re-runs `--track-memory --markers` and reports the per-arena peak delta.

## 8. Out of Scope

- `rogue_mud/test/dungeon_test.zig` SEGFAULT in `generateDungeon` (pre-existing, ungated game logic).
- Any fix that changes emitted C89 (must stay byte-identical).
- Non-memory refactors unrelated to the 37 cataloged collections.
- `std.zig`/stdlib surface changes.

## 9. References

- I-M1 peak map: `.superpowers/sdd/I-M1-peakmap-report.md`
- I-M2 waste audit: `.superpowers/sdd/I-M2-wasteaudit-report.md`
- I-M3 fix model: `.superpowers/sdd/I-M3-fixmodel-report.md`
- Arena sizes / `sandReallocInPlace`: `sf/src/allocator.zig:55-79`
- Token doubling: `sf/src/import_resolver.zig:16-47`; `Token`=24 B `sf/src/token.zig:115-123`
- Type registry / type_db: `sf/src/type_registry.zig`, `sf/src/main.zig:155-157`
- Hash maps: `sf/src/util/hash.zig`
