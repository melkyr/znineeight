# T6 report — Docs + defect ledger (D1/D2 FIXED + D4 entry)

Plan: `docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md` Task 6 + operator
D4 directive (brief `task-6-brief.md`).
Branch `zig1_improvements`. Docs/defects-only task: **zero `sf/src` edits** (git diff
evidence below). Status: **DONE**.

---

## Docs inventory

Tech docs under `sf/docs/tech_docs/**` gained the landed T1–T4 mechanisms, all stamped
`[updated: 2026-10-17 — …]`, append-only (every pre-existing dated entry/stamp preserved;
new stamps appended beside the old; no history rewritten). Files changed = the doc homes of
the milestone's modified pipeline files (INDEX Table A mapping: `type_registry`/`type_resolver`/`front_resolution` → 03, `semantic_analyzer` → 05, `lower` → 07, `c89_emit` → 08,
`parser` → 00, `module_registry` → 01, `main` → 09) + INDEX:

| doc | section(s) stamped | mechanism documented |
|---|---|---|
| `03_type_resolution.md` | `Type Caches` (new dated block), `typeRegistryIsAssignable` rule 7, `typeRegistryGetOrCreateOptional`/`GetOrCreateArray` fn rows, Known Issues #3 | (c) T1 canonical synthetic composites: unconditional key-cache (model `GetOrCreatePtr`), cache-hit in-place completion (`optionalCompleteIfReady`/`arrayCompleteIfReady`, `state==2` guard), structural `fn_type` compare (`typeRegistryTypesEquiv`/`typesEquivRec`, return+params, depth cap 16); Known Issues #3 marked FIXED-by-T1 |
| `05_semantic_analysis.md` | `semanticAnalyzerResolveIfExpr` (new dated block), `if_stmt` worklist bullet, dispatch arm 40 (`import_expr`), `semanticAnalyzerResolveIdent` (new dated block), `@isWindows()` paragraph | (a) T3 comptime-if folding: Zig rule — untaken arm NOT analyzed (`semanticAnalyzerIfComptimeCondition` gate, `TYPE_NORETURN` stamp); trigger = evaluator-folded `KIND_BOOL` incl. compounds (`ctx.comptime_folds` + local-const stamps); else-less Variant B (`3059` kept, census 10/10). (b) T4 conditional `@import`: expression-position `@import` → `module_type` (live module), use-site alias fold (`semanticAnalyzerModuleAliasInitType`, `T4AM` marker), if/switch idiom; `@isWindows` flip point truth-up (`cli.target_is_windows`) |
| `07_lir_lowering.md` | Control Flow / If (two new dated blocks), `lowerModuleInit` fn row | (a) T3: untaken arm NOT lowered (`if_fold`/`ie_fold`, sema/lowering coherence; noreturn-typed folded `if` one-arm path supersedes the old `TYPE_NORETURN` skip note). (b) T4: `import_expr`/module-typed `if`/`switch` lower to NO value; `lowerModuleInit` skips module-alias inits; `resolveModuleBase` folds to the live module |
| `08_c89_emission.md` | §1.1 Pointer-only vs Value-embedding split (new dated block), §6.2 Module pruning (new dated block) | (c) T2 typedef ordering: 2a/2b sub-pass + `emitDefDeps`/`emitDepRef` spelling deps (fn return/params, slice elem, `?T`/`E!T`/`[N]T`/tuple closure) — every composite typedef before every spelling reference; residuals C1/C2 recorded (docs already discuss the relation). (a) T3 module closure: reachability-consistent runtime-init root edge (`prune_active`), `pruneTypeMarkByValue` type-owner pin named as the D2 channel |
| `00_lexer_parser.md` | `parserParseBuiltinCall`, `parserParseImportExpr` fn rows | (b) T4 `dead_import_depth` parse gate + `parserFoldComptimeBool` probe (dead arm's `@import` never loads its file); C2 `child_buf_len=0` clobber deleted (F4 sibling noted); D3 gap class cross-ref |
| `01_import_resolution.md` | `ModuleRegistry` struct row, `moduleRegistryResolveImport` fn row | (b) T4: `ModuleRegistry.target_is_windows` polarity wire; dead-arm `@import` never reaches the resolver (lazy load), live-module selection cross-ref to 05/07 |
| `09_pipeline_orchestration.md` | `target_is_windows` cli row + flip-point paragraph, `phase_ComptimeEvaluation` arm 3, `phase_C89Emission` reachability paragraph | (a) T3: if-condition sweep widened to every capture-free `if_expr`/`if_stmt` (supersedes the old "deliberately not stored" scope); (a) closure edge; (b) T4 target polarity into the parse gate |
| `INDEX.md` | `Tech Doc Index` (new dated block) | milestone map: which doc carries which mechanism + defects-ledger state |

Commands + observed (touch set / no code):

```
$ git diff --numstat
43	5	examples/torrent_example_defects.md
2	2	sf/docs/tech_docs/00_lexer_parser.md
2	2	sf/docs/tech_docs/01_import_resolution.md
6	4	sf/docs/tech_docs/03_type_resolution.md
7	3	sf/docs/tech_docs/05_semantic_analysis.md
5	1	sf/docs/tech_docs/07_lir_lowering.md
4	0	sf/docs/tech_docs/08_c89_emission.md
5	3	sf/docs/tech_docs/09_pipeline_orchestration.md
2	0	sf/docs/tech_docs/INDEX.md
$ git status --short
 M examples/torrent_example_defects.md
 M sf/docs/tech_docs/{00,01,03,05,07,08,09,INDEX}.md
?? examples/z98/z9play/platform/audio_win9x.zig      # left alone (M6 WIP)
?? examples/z98/z9play/platform/audio_win9x_pal.zig  # left alone
?? run.err                                           # left alone
```

git diff = docs/defects only. **Zero `.zig` hunks.** Untracked `run.err` + `audio_win9x*.zig`
untouched (not added, not modified).

## Defects doc deltas

`examples/torrent_example_defects.md` (history preserved: every pre-fix symptom/reproducer/
workaround paragraph stays; status lines flipped; dated fix blocks appended; D3 byte-identical):

- **D1 → FIXED at root cause.** Status line → `FIXED at root cause (2026-10-17 … T1+T2)`; new
  dated block: confirmed mechanism (identity: `optional_cache`/`array_cache` `MapPut` guarded
  on `state==2` → duplicate synthetic ids + raw-id `fn_type` compare; ordering: 2a/2b split
  emitting the fn-pointer typedef before its `?Aggregate` spelling) + fix commits
  (`5a56b501`, `1c5247b9`) + fixtures `fnptr_opt_aggregate_{coerce,emit}_xmod` green +
  **`Key.none` workaround RETAINED per operator ruling** + "Compiler fix (not authorized)"
  paragraph marked superseded.
- **D2 → FIXED at root cause.** Status line → `FIXED at root cause (2026-10-17 … T3+T4)`; new
  dated block with the **truthful mechanism** (module-reachability type-owner pin —
  `pruneTypeMarkByValue` by-value-named-type owner module pin + all-fn edge scan; explicitly
  supersedes the "dead `func_ref` survives LIR" framing, which task-0 measured wrong) + fix
  commits (`58c4cb1c`, `3583668b`, `a7828e5e`, `d568880c`) + 7 green fixtures + cross-target
  contract + D3 residual pointer.
- **D3 → UNTOUCHED** (OPEN/deferred; `git diff` shows its text only as unchanged context).
- **D4 → NEW** (see next section).
- Intro line stamped `[updated: 2026-10-17 …]` summarizing the ledger state (the "tracks only
  open defects" sentence is now qualified; pre-reset history untouched).

Fixture evidence (command + observed output; gate compiler = T5 post-fix seed build
`/tmp/t5_work/post/zig1_5_clean`, md5 `2c48fa702393032c2b711a8d982bd388` — behavior-identical
to HEAD for these fixtures since T6 is docs-only):

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/t5_work/post/zig1_5_clean \
    repro/mi_matrix/fnptr_opt_aggregate_coerce_xmod \
    repro/mi_matrix/fnptr_opt_aggregate_emit_xmod \
    repro/mi_matrix/iswindows_deadarm_errunion_xmod \
    repro/mi_matrix/iswindows_deadarm_prune_xmod \
    repro/mi_matrix/iswindows_deadarm_cond_if_xmod \
    repro/mi_matrix/comptime_if_noelse_deadarm_xmod \
    repro/mi_matrix/conditional_import_if_xmod \
    repro/mi_matrix/conditional_import_switch_xmod \
    repro/mi_matrix/conditional_import_lazy_xmod
PASS repro/mi_matrix/fnptr_opt_aggregate_coerce_xmod
PASS repro/mi_matrix/fnptr_opt_aggregate_emit_xmod
PASS repro/mi_matrix/iswindows_deadarm_errunion_xmod
PASS repro/mi_matrix/iswindows_deadarm_prune_xmod
PASS repro/mi_matrix/iswindows_deadarm_cond_if_xmod
PASS repro/mi_matrix/comptime_if_noelse_deadarm_xmod
PASS repro/mi_matrix/conditional_import_if_xmod
PASS repro/mi_matrix/conditional_import_switch_xmod
PASS repro/mi_matrix/conditional_import_lazy_xmod
----------------------------------------
run_fixtures: 9 PASS / 0 FAIL over 9 dirs
```

## D4 entry

`examples/torrent_example_defects.md` §**D4 — Static-analyzer issues cluster (inert base,
dead-arm parity, residual walks)**: status **OPEN**; operator framing quoted in essence
("require its own plan to fix whatever is good to fix, but there are several defects worth
fixing"); T5's landed revivals stated as STANDING (`5cc7107f` — Lifetime provenance
substrate, capture `if_stmt` wiring, Signature surface). Known-defect list enumerated
(a)–(g) exactly per the brief/context: (a) full comptime-dead-arm parity missing
(`comptime_folds` not plumbed into `AnalyzerContext`), (b) NullPointer return/init walk gap +
params unseeded (44 false WARN_6002 on self-source), (c) DoubleFree capture alias chains,
(d) symbol-table provenance structurally dead for fn locals/params (T5 analyzer-internal
`Provenance` substrate is the workaround; proper fix = register locals / pass a scope map),
(e) vacuous hand-fed-symbol unit-test pattern (revival illusion), (f) docs residue
(design-doc C++-era prose, p2 §5.3 aspirational slice row), (g) `Symbol` test-init missing
`file_id`. Provenance line → T5 report Concerns/§1 + `docs/tech_debt/static_analyzers.md`
§4.1–§4.3 + T5 review minors.

## Concerns

- **Battery NOT run — justified (docs-only).** Docs cannot change emission/classification/
  runtime: zero `sf/src` (or any `.zig`) edits in this diff (`git diff --numstat` above shows
  only `sf/docs/tech_docs/**` + `examples/torrent_example_defects.md`). Spot-check that
  nothing moves = the 9-fixture run above (9 PASS / 0 FAIL) + the docs-only diff. Per the
  brief, a full battery would be required only if any `.zig` were touched.
- **Header stamps left in place (append-only reading).** Doc H1 lines (`# 03 — … [updated:
  2026-10-15 — P7 …]` etc.) were NOT rewritten; the new `[updated: 2026-10-17 — …]` stamps
  live at the changed sections (docs/sf/AGENTS.md convention: "top of changed section"). Prior
  commit practice sometimes replaced the H1 stamp; the brief's "period-accurate dated entries
  stay" + "append-only" won. Cost if wrong: one-line H1 refresh later.
- **Tech-doc homes beyond the plan's four.** The plan names "type registry / semantic analysis
  / lowering / emission"; the brief's fact list (T4 `dead_import_depth` parse gate, live-module
  selection; T3 module closure) lives in 00/01/09 per INDEX Table A (those files' code WAS
  modified by T3/T4: `parser.zig`, `module_registry.zig`, `main.zig`). Small dated stamps were
  added there so no tech doc carries stale claims (e.g. 05 arm 40 "import_expr → TYPE_VOID",
  09 arm 3 "if_stmt conditions deliberately not stored", 03 Known Issues #3). All within the
  mandated touch set `sf/docs/tech_docs/**`. If the controller scopes T6 to exactly five files,
  the 00/01/09 hunks are independently drop-able.
- **D2 mechanism wording.** The pre-fix Symptom paragraph keeps its (wrong) "dead `func_ref`
  survives LIR" sentence as history; the fix block explicitly supersedes it with the measured
  channel (type-owner pin) per the task-0 truth-up. No Symptom text was deleted (append-only).
- **D4 scope is intake-only.** No analyzer fix attempted (operator: own plan). The docs
  residue in (f) and the `file_id` rot in (g) are recorded, not fixed.
- **Fixtures "green" quoted from a T5-era binary** (`/tmp/t5_work/post/zig1_5_clean`), since
  T6 changes no code — a fresh seed build of HEAD would be behavior-identical for these
  fixtures; the run above is the observed evidence.
