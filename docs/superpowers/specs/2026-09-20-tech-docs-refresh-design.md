# Z98 `zig1` technical-documentation refresh — Design

> **Status:** Approved 2026-09-20 (operator). Program-level spec for the
> `sf/docs/tech_docs/` refresh. Each refresh plan argues from this document.

**Goal:** Bring all 14 `sf/docs/tech_docs/*.md` documents and `INDEX.md` back
into agreement with the current `zig1` source, and remove the two mechanisms
that make them rot — volatile `file.zig:NNN` line references and dated
"Evidence" appendices tied to pre-upgrade examples.

## §1 The gap this closes

`sf/docs/tech_docs/` documents the compiler pipeline phase by phase. The docs
were written 2026-08-01 through 2026-09-06 (with `00_lexer_parser`,
`00_shared_infra`, `01_import_resolution`, `12_async_coroutines` and `INDEX`
refreshed 2026-09-17/18/20). Since 2026-09-06 alone, **191 commits** touched
`sf/src`; the full history is 900+ commits.

The drift is measurable:

- `INDEX.md` places `phase_ImportResolution` at `main.zig:249`; the function is
  now at `main.zig:426`.
- Two phases are absent from the pipeline entirely: `phase_FrontResolution`
  (`main.zig:538`) and `phase_AsyncFrameSize` (`main.zig:696`).
- `INDEX.md` lists `AstKind` as "97 variants"; the enum now spans 117 lines.
- The source-file coverage map omits ~17 non-std files, including whole new
  subsystems (`lir_opt_pass.zig`, `spill_store.zig`, `lir_stream.zig`,
  `front_resolution.zig`, `emit_support.zig`, `config.zig`).
- Large cross-cutting feature waves landed with no doc coverage: calling
  convention, packed struct/union, arbitrary-width ints/enums, volatile,
  `-fsafe`/`-ffast` (c89-ahead), the LIR optimization pass, emission
  compaction, the self-contained output directory + companion build scripts,
  module pruning, async/coroutines, the std_net extern target, and the seed
  bootstrap migration.
- Line references are the primary rot vector (226 in `07_lir_lowering.md`,
  178 in `08_c89_emission.md`, 130 in `05_semantic_analysis.md`, 86 in
  `03_type_resolution.md`), and dated "Evidence" traces were captured against
  the 4 working examples before those examples were upgraded (2026-09-04).

AGENTS.md §1.1.1 makes this maintenance mandatory: when compiler pipeline code
changes, the corresponding `sf/docs/tech_docs/` doc must be updated. The
accumulated plans and bug-fix rounds outran that obligation; this program pays
it down.

## §2 Refresh method (binding)

**Surgical audit + correct.** Keep each document's structure and its accurate
prose; do not rewrite it. For each document:

1. Read the document in full.
2. Read every `sf/src` file the document covers (see §6), and enumerate its
   current public types, functions, constants, error sets, and markers.
3. Read the relevant plan/spec documents dated after the document to build the
   feature list (see §5).
4. Correct the document: remove deleted symbols and features, fix renamed
   symbols and changed behavior, add missing symbols and features, update the
   Summary Table and any counts, rewrite contradicted explanations.
5. Remove all line references (§3) and dated Evidence appendices (§4).
6. Audit **Known Issues**: mark fixed ones `[FIXED <date>]` or remove them; add
   issues discovered during the audit.
7. Update the header revision marker (§7).
8. Self-review every changed claim against source, then commit (docs-only).

Preserve headings, tables, and diagrams that are still accurate. The result is
the same document, made true.

## §3 Line references (binding)

Remove every `file.zig:NNN` / `file.c:NNN` reference from prose, tables, and
diagrams. Refer to a symbol by its **name and file** (e.g. "`lowerFieldStore`
in `lower.zig`") or by its section. Drop the per-function `Line` column from
every function/type table. `INDEX.md` keeps a **symbol → file** locator, with
no line numbers.

Rationale: line numbers change on every commit; names and files are stable.
This is the single highest-leverage change for keeping the docs true.

## §4 Evidence appendices (binding)

Remove the dated "Evidence" / "Deep-Dive Evidence" sections and any
fprintf/marker trace tables captured against the 4 working examples
(`mud_server`, `game_of_life`, `lisp_interpreter_curr`, `json_parser`). They
record historical runs against pre-upgrade examples and are the fastest-rotting
content. The reference content they sit beside — types, functions, data flow,
markers, known issues — is retained.

## §5 Feature coverage (binding)

Document each new cross-cutting feature **inside the existing phase doc(s) it
touches**. Add no new tech docs. The feature waves and their target docs:

| Feature wave | Target docs |
|---|---|
| Calling convention (`extern` stdcall/cdecl, convention-aware fn-ptr typedefs, variadic rejection) | 00_lexer_parser, 03_type_resolution, 07_lir_lowering, 08_c89_emission, 10_c_runtime |
| Packed struct/union (bit layout, `load_bitfield`/`store_bitfield`, bitfield accessors) | 00_lexer_parser, 03_type_resolution, 07_lir_lowering, 08_c89_emission |
| Arbitrary-width ints + `enum(uN)` (carrier mask/sign-extend, backing widths, introspect) | 00_lexer_parser, 03_type_resolution, 04_comptime_eval, 05_semantic_analysis, 07_lir_lowering, 08_c89_emission |
| `volatile` qualifier | 00_lexer_parser, 03_type_resolution, 05_semantic_analysis, 07_lir_lowering, 08_c89_emission |
| c89-ahead `-fsafe`/`-ffast` (checked cast/div/shift/bounds/null, undefined poison, live traps) | 05_semantic_analysis, 07_lir_lowering, 08_c89_emission, 09_pipeline_orchestration |
| LIR optimization pass (copy propagation, local const-fold, expression nesting) | 07_lir_lowering |
| Emission-core compaction (copy coalescing, named-local store dedup) | 08_c89_emission |
| Self-contained output dir + companion build scripts + emitted runtime support | 08_c89_emission, 09_pipeline_orchestration, 11_build_system |
| Module pruning (needed-only std) | 01_import_resolution, 08_c89_emission |
| Async / coroutines (analysis, frame layout, state machine, `std.async`) | 00_lexer_parser, 03_type_resolution, 05_semantic_analysis, 07_lir_lowering, 08_c89_emission, 12_async_coroutines |
| std_net extern target (socket builtins removed; extern surface) | 05_semantic_analysis, 08_c89_emission, 10_c_runtime |
| Seed bootstrap migration (`release/seed/`, `build_from_seed.sh`) | 11_build_system |
| Memory refactor (arena tiers, offset-addressed spill store, Ram/Disk backends) | 00_shared_infra, 07_lir_lowering |
| Introspection / pointer / bitcast builtins, switch-range, string-literal typing, enum→int promotion, clean diagnostics | 04_comptime_eval, 05_semantic_analysis, 07_lir_lowering, 08_c89_emission |

## §6 Source-file coverage map (binding)

Every non-std `sf/src` file is assigned to **exactly one** tech doc. `std_*.zig`
modules and `std.zig` belong to the separate `sf/docs/std_lib/` program and are
out of scope here. `test_*.zig` and `sf/src/tests/` are out of scope.

| Doc | Covers |
|---|---|
| `00_shared_infra.md` | `allocator.zig`, `string_interner.zig`, `source_manager.zig`, `diagnostics.zig`, `pal.zig`, `growable_array.zig`, `panic.zig`, `config.zig`, `util/` |
| `00_lexer_parser.md` | `token.zig`, `lexer.zig`, `parser.zig`, `ast.zig`, `print_decomposition.zig`, `dump_ast.zig`, `dump_tokens.zig`, `ast_dump_main.zig` |
| `01_import_resolution.md` | `import_resolver.zig`, `module_registry.zig` |
| `02_symbol_registration.md` | `symbol_registrator.zig`, `symbol_table.zig` |
| `03_type_resolution.md` | `type_resolver.zig`, `type_registry.zig`, `const_alias_prepass.zig`, `front_resolution.zig` |
| `04_comptime_eval.md` | `comptime_eval.zig` |
| `05_semantic_analysis.md` | `semantic_analyzer.zig`, `coercion.zig`, `resolved_type_table.zig`, `constraint_checker.zig`, `assign_helper.zig` |
| `06_static_analyzers.md` | `analyzer.zig`, `state_map.zig` |
| `07_lir_lowering.md` | `lower.zig`, `lir.zig`, `lir_opt_pass.zig`, `lir_stream.zig`, `spill_store.zig` |
| `08_c89_emission.md` | `c89_emit.zig`, `name_mangler.zig`, `cinclude.zig`, `emit_support.zig` |
| `09_pipeline_orchestration.md` | `main.zig`, `main_dump.zig`, `main_exp.zig`, `strip_main.zig` |
| `10_c_runtime.md` | `sf/src/include/*`, `extern_c.zig`, `extern_c_z98.zig` |
| `11_build_system.md` | `sf/scripts/*`, `scripts/seed/*`, `release/seed/*` |
| `12_async_coroutines.md` | `async_analysis.zig`, `async_frame_layout.zig`, `async_state_machine.zig`, `std_async.zig` |

`INDEX.md` carries the same map as its coverage table. Cross-phase behavior is
documented in the doc that owns the code; other docs cross-reference it rather
than duplicating it.

## §7 Header convention (binding)

Each doc's title line carries a concise revision marker:

```
# NN — Title [updated: YYYY-MM-DD — <one-line reason>]
```

Collapse the existing multi-thousand-character changelog blobs to this
one-liner. The `[updated: …]` form satisfies AGENTS.md §1.1.1. Historical
entries are not preserved in the header; git history holds them.

## §8 `INDEX.md` refresh

Regenerate the master index against current source:

- **§A Phase Flow** — add `phase_FrontResolution` and `phase_AsyncFrameSize`;
  correct the phase table (function names, files, markers, arena tiers).
- **§B Function → File** — symbol → file, **no line numbers**.
- **§C Markers** — phase markers, runCompiler checkpoints, sub-phase markers.
- **§D Sentinel TypeId table** — verified against `type_registry.zig`.
- **§E Data Structure → File** — verified against source.
- **§F AstKind → Handling Phases** — verified against `ast.zig`.
- **§G Arena Tier → Who Uses It** — verified against `allocator.zig`/`main.zig`.
- **Tech Doc Index / coverage table** — the §6 map; refreshed
  `AstKind`/`LirInst`/`TypeKind` counts and the new/renamed files.

## §9 Conventions (binding)

- **Docs only.** No `sf/src`, `scripts/`, fixture, or `release/seed` change. The
  compiler fixed point and seed are untouched.
- **Accuracy over volume.** Every retained or added type, function, error
  member, marker, and count must match current source. Read the source; never
  invent an API.
- **Preserve structure.** Keep still-accurate headings, tables, and diagrams;
  the refresh corrects, it does not rewrite.
- **No line references** (§3) and **no dated evidence appendices** (§4).
- **Agent review only.** No accuracy-checker script is added; each doc is
  verified by its task reviewer against source, plus a final whole-branch
  review.
- **Edits only via `edit`/`fastedit`** (re-read the region immediately before
  each `fastedit`; edit bottom-to-top for multiple edits in one file). Never
  stage `mnemoria/` or `.zig1_*.tmp`.
- **STOP on a source defect:** if the audit finds a doc/source contradiction
  that is a real compiler bug, STOP and report it — do not fix `sf/src`, do not
  document around it.

## §10 Plan index

1. `docs/superpowers/plans/2026-09-20-tech-docs-refresh-plan.md` — the full
   refresh: one task per doc in pipeline order, then `INDEX.md`, then the
   whole-set consistency review. **Final plan.**
