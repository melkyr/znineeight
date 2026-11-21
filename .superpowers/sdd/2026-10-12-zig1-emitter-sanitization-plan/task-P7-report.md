# Task P7 report — Front-end module-scope-first name resolution (D7 root-cause)

Branch `zig1_improvements`, BASE `6f726672` (confirmed `git rev-parse HEAD`). Requirements:
`task-P7-brief.md` (binding). Shape: Investigate (read-only census + edit plan) → Implement → Runtime
battery. **Run stopped in Investigate (STOP-present, below). No source edits, no compiler-moving
commit, no battery.** Reproducer probes are tmp-only under `/tmp/p7_work/repro/` (not committed;
committing fixtures would move the frozen corpus/stdlib anchors).

## Status

**STOP-present** (binding format):

> I found the intention is P7's module-scope-first unqualified type-name resolution — with the
> mandated reproducer evidence "pre-fix `@sizeOf(Mode)` → 4 (D7), post-fix → 8" — delivered inside
> `sf/src/semantic_analyzer.zig` + `sf/src/type_resolver.zig` only, but this is impossible given that
> the observed D7 wrong answer is produced **outside both files and with no module context at all**:
> `@sizeOf(T)`'s value is folded by `comptimeEvalResolveTypeArg` (`sf/src/comptime_eval.zig:1327`),
> which builds its `TypeResolveEnv` with `module_id = MODULE_ID_NONE`, and the fold table it feeds is
> filled by `phase_ComptimeEvaluation` (`sf/src/main.zig:639`) sweeping every module's nodes through
> one module-less evaluator — so at the fold site the required order's step 2 ("module scope — the
> current module's declarations") is structurally **absent**, not merely mis-ordered: `resolveTypeExprFull`'s
> module-scope lookups are `module_id != MODULE_ID_NONE`-guarded (`type_resolver.zig:1918/:1934`) and
> cannot fire, the flat cache + all-module first-match scans run unconditionally, and the lexical
> module cannot be recovered inside the touch-set files (`AstNode` carries no file/module identity —
> `ast.zig:120-133`; spans are per-file offsets; `TypeResolveEnv` has no module registry). Reordering
> the two files therefore cannot move the reproducer's `@sizeOf(Mode)` from 4 to 8, while the brief's
> own gate demands exactly that evidence. (Secondary ambiguity, same STOP class: the brief's
> "two-module probe … pre-fix `@sizeOf(Mode)` → 4" cannot exhibit the defect at all — see I.3; and
> its "Show `@sizeOf(Mode)` == 8 … both pre/post" sentence contradicts "pre-fix → 4" for one probe.)

Decisions the operator must make before P7 can proceed (I do not rule — Authority: STOP-present):

1. **Extend P7's touch set** (the shape that root-closes D7): `sf/src/comptime_eval.zig` (`ComptimeEval`
   gains the enclosing `module_id`; `comptimeEvalResolveTypeArg` builds its env with it instead of
   `MODULE_ID_NONE`) + `sf/src/main.zig` (`phase_ComptimeEvaluation` walks each module's AST with
   `ce.module_id = mods[i].id` instead of one global module-less node sweep) + the `comptimeEvalInit`
   call sites (`sf/src/lower.zig:1807/:3782`, `sf/src/semantic_analyzer.zig` folds — the analyzer file
   is already in set) + the in-set order changes of I.4. Battery-gated as usual.
2. **Re-scope P7** to the in-set module-scope-first order changes only (I.4) and adjust the
   reproducer contract: the `@sizeOf` fold collision stays a documented residual (D7 NOT root-closed;
   "post-fix → 8" cannot be evidenced).
3. Some third shape the operator has in mind.

## Investigate (read-only; no source edits happened)

Line cites re-derived by function name at `6f726672` (brief's cites confirmed where named).

### I.1 Unqualified-type-name lookup census

**In the touch set:**

| # | site (fn) | current order | verdict |
|---|---|---|---|
| 1 | `semanticAnalyzerResolveIdent` (`semantic_analyzer.zig:880`; fallthrough `if (ncg) \|t\|` at :908) | local bindings → module symbol table (`symbolRegistryQualifiedLookup`; `type_alias` arm: `type_id` → `ncgm` → `ncg`; non-alias arm: `type_id` → `TYPE_VOID`) → flat `ncg` fallthrough → ERR_3001 | **order bug**: the fallthrough consults the flat cache **without** the module-qualified `ncgm`; module scope per the required order is `ncgm` + module symbol table, both before the flat/global fallback. Non-alias arm also drops both caches (`type_id == 0` → `TYPE_VOID`) |
| 2 | `resolveTypeExprFull` ident arm (`type_resolver.zig:1908-1947`) | local_types → module-qualified cache `ck_cur` (:1917) → **flat** (:1923) → **all-module `mkey` first-match scan** (:1925) → module symbol `symbolTypeIdOfModule` (:1934) → `symbolLookupTypeAllModules` (:1938) → arb-int → UNDEFINED | **order bug**: the module **symbol table** is module scope but sits *below* the flat cache and both global scans; required order puts `ck_cur` + module symbol together before any fallback |
| 3 | `symbolLookupAllModules` (`type_resolver.zig:1408`) | first-match symbol scan over modules 0..N | fallback helper; value-ident users (`evalConstIntFull` :1194) unchanged per brief ("value-ident behavior … unchanged unless a shared path forces it") |
| 4 | `symbolLookupTypeAllModules` (`type_resolver.zig:1427`) | first-match `type_id` scan over modules 0..N | fallback helper (post-fix: reached only when module scope misses) |
| 5 | `enumReevaluateAll` (`type_resolver.zig:1567`) | `mkey(module, enum_name)` | OK (module-qualified) |
| 6 | `registerContainerType` (`type_resolver.zig:1693`) | flat `anon_<node_idx>` | OK (unique synthesized names) |
| 7 | `resolveDeclAggregateFieldTypes` (`type_resolver.zig:2201`) | `mkey(module, name)` | OK |
| 8 | `semanticAnalyzerGateEnumModuleDecl` (`semantic_analyzer.zig:2275`) | `mkey(module, name)` | OK (gating only) |
| 9 | type-value **detection** (not resolution): `semanticAnalyzerTupleElemIsTypeValue` (`semantic_analyzer.zig:6505`), `printFmtArgIsTypeValue` (`lower.zig:1287`) | flat get + name-match heuristic | non-load-bearing (detection only) |

**Outside the touch set — load-bearing for the D7 observable:**

| # | site | role |
|---|---|---|
| 10 | `comptimeEvalResolveTypeArg` (`comptime_eval.zig:1327`; env literal :1329) | **THE D7 site.** Every `@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf`/`@intCast`/`@as` type-argument in the fold is resolved here with `module_id = MODULE_ID_NONE`, so `resolveTypeExprFull` skips `ck_cur` (:1918 guard) and the module-symbol step (:1934 guard) and returns the flat cache / all-module first-match scan result |
| 11 | `phase_ComptimeEvaluation` (`main.zig:639`; builtin_call fold :653-663) | one module-less `ComptimeEval` sweeps **all** modules' nodes; fills `ctx.comptime_folds`, consumed at lowering (`lower.zig:6100`) — the value the D7 reproducer prints |
| 12 | `comptimeEvalInit` call sites with no module: `main.zig:644`, `lower.zig:1807/:3782`, `semantic_analyzer.zig:1053/3078/3906/5703/6089/6665/6846` | module-less evaluator construction (the lowerer/analyzer *have* `module_id` but the API cannot carry it) |
| 13 | `symbol_registrator.zig:200` (`populateTypePayload` field types, `MODULE_ID_NONE`) | registration-time, module-agnostic by design (not the D7 path) |

Out-of-set, non-load-bearing: `analyzer.zig:482` (`validateSignatureType`, flat get — incomplete-type
diagnostics only), `lower.zig:5241` (type-alias member arm, `mkey`), `const_alias_prepass.zig:166-176`
(alias-RHS registration resolution).

### I.2 Registration-side key map (`nameCachePut` sites)

| site | key written | note |
|---|---|---|
| `type_registry.zig` `registerPrimitiveName` (:1106) | **bare** `name_id` | primitives + arb ints |
| `type_registry.zig` `typeRegistryRegisterNamedType` (:1205; put :1219) | `module_id<<32\|name_id` | **`module_id == 0` ⇒ the key is bit-identical to the bare key**: module-0 declarations live in the flat cache. `registerContainerType` (`type_resolver.zig:1716`) passes `module_id = 0` for `anon_<node>` names |
| `symbol_registrator.zig` `registerDecl` container arm (:286) / top-level container arm (:407/:428) | `mkey(module, name)` | `struct/enum/union/error_set` decls + `const X = <container>` |
| `symbol_registrator.zig` ident-init arm (:303) | `mkey(module, alias_name)` | only when the RHS is already cached at registration time; a **forward alias** gets **no** `mkey` put |
| `symbol_registrator.zig` arb-int arm (:318) | `mkey(module, alias)` | `const T = u7` |
| `const_alias_prepass.zig` Phase 2 (:189) / Kahn (:225) | `mkey(module, **RHS name**)` | the alias's **own** name is still not put |
| `front_resolution.zig` `frontResolveModuleInits` (:100) | `mkey(module, name)` | ident-init module var decls — **fills the forward-alias gap before the fold phases** |
| `type_resolver.zig` `resolveNamedTypeExpressions` (:2304) / `resolveImportFieldAliases` (:2358) | `mkey(module, name)` | non-container init exprs / `const x = mod.y` |
| `semantic_analyzer.zig` (:6121) | `mkey(module, **local name**)` | function-local var decls write the module-qualified key (pollution class; noted, not P7) |

### I.3 The D7 mechanism, confirmed empirically (tmp probes, pre-fix compiler `/tmp/p7_work/old/zig1_5_clean` = `7b6273ffeb8959232a552c105d891fcd`)

Topology fact: the entry file is always module 0 (`main.zig:508` `moduleRegistryAddModule` on the CLI
input; imports discovered after), and module 0's name-cache keys are bit-identical to the bare keys
(I.2). Consequences:

- **Literal two-module probe** (`mod.zig` entry declaring `Mode` (8-byte struct) + `std_file.zig`
  `Mode` (4-byte enum)) — `/tmp/p7_work/repro/modA1.zig`: prints `8422` = `@sizeOf(Mode)` **8**,
  `@sizeOf(std_file.Mode)` 4, `var m: Mode` field 22. **No steal**: every fallback (flat key, all-module
  scan mi=0-first) finds module 0's own `Mode` first. The brief's "pre-fix `@sizeOf(Mode)` → 4" cannot
  occur in this shape.
- **z9play-faithful shape** (the defects-doc reproducer: entry imports `std_file` **before** the
  `Mode`-owning module — `examples/z98/z9play/main.zig:51` imports `std_file`, `:54` imports
  `vorbis_setup`): `modB2.zig` declares `pub const Mode = struct { x: u32, y: u32 }` and imports
  `std_file.zig` (`Mode` = 4-byte enum) — `/tmp/p7_work/repro/mainB2.zig`+`modB2.zig` prints `4422224`:

  | probe item | resolution path | env | observed | verdict |
  |---|---|---|---|---|
  | `@sizeOf(Mode)` (expression) | `comptimeEvalResolveTypeArg` → `resolveTypeExprFull` | **NONE** | **4** | **D7 steal** (flat miss → all-module scan: `std_file` id 1 < `modB2` id 2) |
  | `@sizeOf(std_file.Mode)` (qualified) | field_access / module symbol | aware | 4 | correct |
  | `var m: Mode` bare annotation | `semanticAnalyzerResolveIdent` module symbol arm | aware | 22 | correct |
  | `var arr: [1]Mode` compound annotation | `resolveTypeExprFull` `ck_cur` | aware | 22 | correct |
  | `@sizeOf([1]Mode)` | fold recursion into the element ident | **NONE** | **4** | **D7 steal** |

- **Forward-alias two-module shape** (`pub const Mode = VorbisMode;` before `pub const VorbisMode =
  struct {…}`; the z9play workaround spelling) — `modC.zig` prints `882222`: no steal anywhere
  (`front_resolution.zig:100` fills `mkey(module, Mode)` before the fold phases).
- **Array-size `@sizeOf`** (`var arr: [@sizeOf(Mode)]u8`, `-fsafe`, `arr[7]`): prints `65`, rc=0 — the
  module-aware `evalConstU32Full` fold (`type_resolver.zig`) is correct (length 8). Only the
  comptime_eval fold steals.
- **FX13-F residual** (bare cross-module `OnlyT` with no local collision, signature + compound
  positions): `modD.zig` prints `42` — global-scan fallback intact.

So the D7 wrong answer is exactly: **fold-time type-arg resolution has no lexical module**, and the
global scans' first-match order (module id) picks the colliding type. The module-aware front-end
paths named in the brief's mechanism (`semanticAnalyzerResolveIdent`, `resolveTypeExprFull`) do not
produce the observed `@sizeOf` wrong answer in the z9play shape; their order bugs (I.4) are real but
masked at runtime (I.5).

### I.4 The exact order change the required semantics mandates (in-set; NOT applied)

1. `semanticAnalyzerResolveIdent` (`semantic_analyzer.zig:880`): in the no-symbol fallthrough (and
   consistently across arms) consult **`ncgm` (module-qualified cache) before `ncg` (flat)**; keep the
   `type_alias` arm's `type_id → ncgm → ncg` (already module-first) and the non-alias `type_id` return.
   Resulting order: local bindings → module symbol table + `ncgm` → flat `ncg` fallback → ERR_3001.
2. `resolveTypeExprFull` ident arm (`type_resolver.zig:1908`): move the module symbol-table consult
   (`symbolTypeIdOfModule(env.module_id)`, :1934) **up beside `ck_cur`** (:1917) so module scope is
   `ck_cur` + module symbol **before** the flat cache (:1923), the all-module `mkey` scan (:1925) and
   `symbolLookupTypeAllModules` (:1938) — those three remain the cross-module fallback (FX13-F stays
   legal, `modD` green).
3. Qualified names (`std_file.Mode`, `resolveTypeExprFull` field_access arm / `semanticAnalyzerResolveFieldAccess`)
   unchanged; value-ident paths (`evalConstIntFull` :1194, comptime_eval ident arms) unchanged per the
   brief.

### I.5 Why the in-set changes alone cannot pass the brief's gate

Both in-set order bugs are masked today for the collision shape: container decls put their `mkey` at
registration, forward aliases get theirs from `front_resolution.zig:100`, so `resolveTypeExprFull`'s
`ck_cur` already hits and `semanticAnalyzerResolveIdent`'s symbol arm already wins. The only
observable D7 site is the module-less fold (I.3), which is `comptime_eval.zig`+`main.zig`
(I.1 #10-12). No change expressible in the two touch-set files can supply a module context that
their inputs do not contain.

## Observations

- **O1:** the brief's `semanticAnalyzerResolveIdent` mechanism ("cross-module type registered under
  the bare key steals") describes the module-0/bare-key aliasing (I.2) but did not fire in the
  collision probes (module symbol arm wins). The observed steal is the all-module first-match scan in
  the fold's `resolveTypeExprFull`. The brief's own instruction ("Investigate must confirm/complete
  this census") is what surfaced the divergence.
- **O2:** `var t: OnlyT` (bare cross-module name, var-decl annotation) rejects pre-fix with
  ERR_3001 + "cannot declare variable of type void" (`mod.zig` probe A). Two pre-existing facts:
  (a) the var-decl bare-annotation arm (`semantic_analyzer.zig:5983-5994`) calls
  `semanticAnalyzerResolveIdent` first, which emits ERR_3001 before its own `resolveTypeExprFull`
  fallback runs; (b) that fallback's result is **dropped on success** (`decl_type` stays `TYPE_VOID`
  unless the fallback returns `TYPE_UNDEFINED`). FX13-F's documented bare-name domain is
  function-signature type positions (fixture `sig_known_type_ok_xmod`), which stay green (`modD`).
  Not P7 scope (and its fix would widen accept behavior — operator call if wanted).
- **O3:** debug markers (`NP:k`/`OPTVOID`/`C2:T`/…) are compiled out (`pal.zig` `g_markers_debug = 0`);
  probe evidence is behavioral only.
- **O4:** probes kept tmp-only at `/tmp/p7_work/repro/` per the brief (A1/B/B2/C/D/E + std_file.zig).

---

# Fix round 1 (Amendment 8 — operator ruled widen, option 1)

Requirements: `task-P7-fix1-brief.md` (binding). Touch set = `semantic_analyzer.zig` +
`type_resolver.zig` + `comptime_eval.zig` + `main.zig` + `lower.zig` (init/env sites only) + tech
docs. The STOP-present record above stands verbatim as history; this round executes option (1).

## Implement

Edit/fastedit only (read-region-before-edit, bottom-to-top per file; INSERT = anchor replaced with
new+original):

1. **`sf/src/comptime_eval.zig`** — `ComptimeEval` gains `module_id: u32` (init literal defaults
   `type_resolver.MODULE_ID_NONE`); `comptimeEvalResolveTypeArg` builds its `TypeResolveEnv` with
   `self.module_id` (was hardcoded `MODULE_ID_NONE`). Every folded type-arg resolution
   (`@sizeOf`/`@alignOf`/`@bitSizeOf`/`@offsetOf`/`@bitOffsetOf`/`@intCast`/`@as`/`@floatCast`/
   `@intToFloat` targets + `comptimeEvalDeclFits` declared-type annotations) is now
   module-scope-first where a module exists.
2. **`sf/src/main.zig` `phase_ComptimeEvaluation`** — per-node lexical-module attribution before the
   existing per-node fold checks (visit set and fold logic unchanged): a node's module is the module
   whose `ast_root` is the **smallest parse-chunk root ≥ the node index** (each module's parse
   appends its nodes contiguously to the shared store; `parserParseModuleRoot` appends the
   `module_root` LAST, so module m's chunk is `(prev_root, m.ast_root]`; the mapping is
   order-independent in the roots — see O1). Nodes past every root keep `MODULE_ID_NONE`
   (module-less fallback-first — disclosed residual, O2).
3. **`sf/src/lower.zig`** (init sites only) — `foldPrintArgIntExact` and `foldNodeIntExact` set
   `ce.module_id = self.module_id` on their fresh evaluators (the lowerer already had the module).
4. **`sf/src/semantic_analyzer.zig`** — `semaComptimeEvalInit` and
   `semanticAnalyzerResolveModuleVarDecl`'s direct `comptimeEvalInit` set `ce.module_id =
   self.module_id`; `semanticAnalyzerResolveIdent`'s no-symbol fallthrough consults `ncgm`
   (module-qualified cache) BEFORE the flat `ncg` (new `C2:M` marker beside the existing `C2:T`;
   all touched debug markers are compiled out — stream unchanged). The `type_alias` arm's
   `type_id` → `ncgm` → `ncg` order is unchanged (already module-first).
5. **`sf/src/type_resolver.zig`** — `resolveTypeExprFull`'s `ident_expr` arm: the module symbol
   table consult (`symbolTypeIdOfModule`) is promoted INTO the module-scope step (right after the
   `ck_cur` module-qualified cache hit, both inside the `module_id != MODULE_ID_NONE` guard),
   ahead of the flat cache, the all-module `mkey` scan and `symbolLookupTypeAllModules` — those
   three are now true cross-module fallbacks. Module-less inputs (e.g.
   `symbol_registrator.populateTypePayload`) keep today's fallback-first behavior via the kept
   guards.
6. **Tech docs** — `[updated: 2026-10-15 — P7 …]` on the changed sections of
   `sf/docs/tech_docs/03_type_resolution.md` (header + `resolveTypeExprFull` row),
   `05_semantic_analysis.md` (header + `semanticAnalyzerResolveIdent` order list) and `INDEX.md`
   (phase-5 row + `comptimeEvalInit`/`comptimeEvalResolveTypeArg` rows).

**Value-ident disclosure:** `evalConstIntFull`'s ident fold (`symbolLookupAllModules` first-match
scan) and comptime_eval's value-ident arms (all-module first-match loops) are UNCHANGED per the
brief ("value-ident behavior unchanged unless a shared path forces it"). The one shared path the
deliverables force is `semanticAnalyzerResolveIdent` (fix1 deliverable 2 names its fallthrough
explicitly; it serves value and type idents alike).

## Runtime battery

Compiler under test `/tmp/p7_work/new/zig1_5_clean`; OLD `/tmp/p7_work/old/zig1_5_clean` (md5
`7b6273ffeb8959232a552c105d891fcd` = the pre-P7 recorded fixed point).

1. **Seed two-hop closure:**
```
$ FIXED_POINT_MD5=7b6273ffeb8959232a552c105d891fcd bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p7_work/new
[seed] hop2 binary md5: f18b69ece1917bf970a036b276e5e403
[seed] two-hop closure OK: hop1 == hop2 == f18b69ece1917bf970a036b276e5e403
error: fixed-point mismatch: got 'f18b69ece1917bf970a036b276e5e403', want '7b6273ffeb8959232a552c105d891fcd'
```
hop1==hop2 proven; fixed point old `7b6273ffeb8959232a552c105d891fcd` → new
**`f18b69ece1917bf970a036b276e5e403`** (expected to move; seed NOT rotated).

2. **Corpus classify vs frozen Appendix A — 0 movers:**
```
$ bash scripts/corpus/classify /tmp/p7_work/new/zig1_5_clean /tmp/p7_work/corpus_p7.txt
wrote /tmp/p7_work/corpus_p7.txt: 1124 dirs
$ md5sum /tmp/p7_work/corpus_p7.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/p7_work/corpus_p7.txt
```
Byte-identical to the frozen `518eca1a…` class file (1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE /
0 CRASH — same file ⇒ same tallies).

3. **Runtime goldens 5/5** (dump `-fsafe` + gcc `-m32 -std=c89 -Wno-long-long -Wno-pointer-sign
   -I sf/src/include … zig_runtime.c zig_pal.c`; all 4 dump rc=0 / gcc rc=0 / 0 `error:`):

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 gold/gol > gol.out` (rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| gold/lisp` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f8974da24ddbf9d389f3d7d97322` | YES |
| json | `cd examples/z98/json_parser && gold/json` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a1ec07d14a301bc343df32bf8` | YES |
| mud srv | `bash examples/z98/mud_server/demo/session.sh gold/mud mud_srv.out mud_cli.out` (rc=0) | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0abb926cca7baf9a0d1692ab318` | YES |
| mud cli | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f0bbd983a9d844fea8b7a6fa7` | YES |

Both mud files `cmp`-IDENTICAL to `demo/canonical_expected.txt` / `demo/canonical_client_expected.txt`.

4. **mi_matrix anchors 25 + oob:**
```
$ bash scripts/stdlib/run_fixtures.sh /tmp/p7_work/new/zig1_5_clean $(cat /tmp/opencode_p6pre/mi25.list)
run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```
Trap (`-fsafe`) `slice_index_field_store_oob_xmod`: dump rc=0, build rc=0, run **rc=133**
(Trace/breakpoint trap), stdout 0 B (md5 `d41d8cd98f00b204e9800998ecf8427e`), `expected.rc=133`.
**MATCH.**

5. **examples/z98/*/ 26/26 build + 26/26 run** (CWD = example dir; `timeout 25` except mud 8;
   stdin `/dev/null` except rogue* fed `q\n`): all dump=0 / build=0 with `.c` counts identical to
   task-0 §1.4 (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38); runs **26/26 rc +
   stdout md5_16 IDENTICAL** to the §1.4 table — days_in_month `8c0d394cbc6e7f36`, fibonacci
   `b53b3a3d6ab90ce0`, func_ptr_return `f6a5477970a87a1c`, game_of_life `fcbf7e7cead5082f`,
   heapsort `8cf0a7844206319d`, hello `746308829575e17c`, json×2 `8bda3d5a1ec07d14`,
   json_parser_workaround `dc22fa473650bd3d`, lisp×4 `1c1f0a417d5e9434`, lzw `c3c7765e6faf7b70`,
   mandelbrot `d596677501e36537`, mud_server rc=124 `9545fe1d245293ef`, prime `d095a94d20dcaf7a`,
   quicksort `45d2f0fb6fc40654`, rogue×2 `3fb6709e7bbd8964`, sort_strings `c6c047cbc13cdd4f`,
   tco_defer `264ea6b106a51dde`, tco_factorial `3d70c50b5a37d549`, tco_return_try `7421137aa2d104b4`,
   z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3`. The z9play `Mode`→`VorbisMode`
   workaround is untouched (spec: examples need not change).

6. **Stdlib gate:**
```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/p7_work/new/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```

7. **The 8 `--dump-c89` pins (old → new; sequential from repo root).**
Command per row: `<compiler> <mode> --dump-c89 examples/z98/<entry>/main.zig 2>/dev/null | md5sum`.

| entry | mode | old (`7b6273ff…`) | new (`f18b69ec…`) | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `bbc02913a10af9b0b5ed0f292f4e3407` | `bbc02913a10af9b0b5ed0f292f4e3407` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `93c5e3fdc5b80b2f3db020d995abbe3f` | `93c5e3fdc5b80b2f3db020d995abbe3f` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `6da05d070acd414674b1b1ec947baa5c` | `6da05d070acd414674b1b1ec947baa5c` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `af3823fae0b29fa4d4ca58932538d631` | `af3823fae0b29fa4d4ca58932538d631` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8 — emitted C byte-identical; the old column also reproduces the P14 live table.**

8. **`--markers` telemetry:**
```
$ /tmp/p7_work/new/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol_new.c 2> mk_gol_new.bin
dump rc=0; 3,437 marker lines / 38,384 B
$ cmp mk_gol_old.bin mk_gol_new.bin  →  IDENTICAL
```
Unchanged **3437/38384** and byte-identical to the old compiler's stream (all debug markers touched
by the order change are compiled out via `pal.zig g_markers_debug = 0`).

## Reproducer (tmp only — `/tmp/p7_work/repro/`; z9play order per the corrected brief)

`mainF.zig` (entry) imports `std_file.zig` FIRST (colliding `Mode`, 4-byte enum — lower module id)
then `modF.zig` (victim: declares `Mode` = 8-byte struct, imports std_file, has `mainF` print a
qualified victim size). `modF.run()` prints (1) unqualified `@sizeOf(Mode)` (2) `@sizeOf(std_file.Mode)`
(3) `var m: Mode` field `m.y` (4) bare cross-module `OnlyT` (no module-local decl) through a
signature; `mainF` prints (5) `@sizeOf(mod.Mode)`.

| # | probe item | pre (`7b6273ff…`) | post (`f18b69ec…`) | contract |
|---|---|---|---|---|
| 1 | `@sizeOf(Mode)` (unqualified) | **4** (D7 steal at the fold) | **8** (module's own struct) | **FIXED** |
| 2 | `@sizeOf(std_file.Mode)` (qualified colliding) | 4 | 4 | unchanged |
| 3 | `m.y` (bare type-position binding) | 22 | 22 | unchanged (module struct) |
| 4 | `sig(OnlyT)` bare cross-module fallback | 42 | 42 | intact |
| 5 | `@sizeOf(mod.Mode)` (qualified victim) | 8 | 8 | unchanged |

Full runs: pre `4422428` rc=0 → post `8422428` rc=0 (`/tmp/p7_work/probeF_pre`, `/tmp/p7_work/probeF_post2`).
Controls post-fix: two-module probe A1 `8422` (module-0 bare-key shape, unchanged), forward-alias
probe C `882222` (unchanged), FX13-F probe D `42` (unchanged), array-size probe E `65` rc=0 under
`-fsafe` (module-aware size fold unchanged).

## Observations (fix round)

- **F-O1 (parse order ≠ module id order):** probe F's `IRP:m/IRP:n` pairs (new compiler) are
  `m0→22, m3→97, m2→106, m1→133, …` — imports are enqueued/parsed in reverse discovery order, so
  module-array (id) order does NOT order the parse chunks. The first attribution implementation
  (id-order root cursor + monotonicity guard) correctly refused to attribute on the anomaly and
  silently reproduced the pre-fix fold (reproducer unchanged at `4422428`); replaced by the
  order-independent derivation (per node: smallest `ast_root` ≥ node index) before any battery run.
- **F-O2 (residual module-less shapes):** nodes after the last `ast_root` (failed-parse partial
  chunks absorbed into the next chunk's attribution; empty-entry root 0 sentinel) keep
  `MODULE_ID_NONE` and today's fallback-first resolution. No battery fixture exercises them.
- **F-O3:** value-ident fold scans unchanged (O3 above) — the only behavior changes are (a) folded
  type-arg resolution with a module context, (b) `semanticAnalyzerResolveIdent`'s
  module-qualified-before-flat fallthrough, (c) `resolveTypeExprFull`'s module-symbol promotion;
  all three are invisible to the frozen battery (corpus 0 movers, pins 0/8) and visible on the
  collision reproducer only.
- **F-O4:** the earlier `b403d2cd25f8c9aebe239e355fe12254` two-hop point (mid-round, id-order
  cursor build) is superseded; the recorded post-fix point is `f18b69ece1917bf970a036b276e5e403`
  (the battery above ran on it).
