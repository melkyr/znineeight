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
