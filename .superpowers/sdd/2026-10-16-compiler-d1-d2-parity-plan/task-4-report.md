# Task 4 report — conditional `@import` (Zig idiom)

Branch `zig1_improvements`. BASE `2b0cd2cf`. Gate compiler
`/tmp/d1d2_t4/zig1_5_clean` (seed-built, fixed point
`e7099859f44e8050e7738be8545e8a58`). Commits: (a) `a7828e5e`
`feat(semantic_analyzer): conditional @import (comptime module selection)`,
(b) this report.

## Investigate

Measured pre-fix on the T3 fixed point `67abd038…` (seed-built `/tmp/d1d2_t4`)
and probed further before edits:

1. **Expr-position `@import` path.** `semantic_analyzer.zig`'s
   `semanticAnalyzerResolveExpr` mapped `AstKind.import_expr` to `TYPE_VOID`
   (the `SVO`-era hole; `semantic_analyzer.zig:5320` pre-edit). The decl/member
   positions were already live: `semanticAnalyzerResolveFieldAccess`'s
   `import_expr`-base arm + `SymbolKind.module` registration
   (`symbol_registrator.zig:259/443`), `type_resolver.zig`'s import-alias
   walks, `lower.zig`'s `resolveModuleBase` direct-import arm. So `const std =
   @import("std")` worked, but `const impl = if (...) @import(...) else
   @import(...)` typed `void` and `impl.ping()` lowered to a garbage temp
   (`(void)zT_1();`; the if form emitted `zG_impl = zT_4294967295` — the exact
   T0 red).

2. **T3's fold × module side effects.** Registration is a **PARSE-time**
   effect (`parserParseImportExpr` → `moduleRegistryResolveImport` at
   `parser.zig:780` — module entry + import edge + queue enqueue happen while
   PARSING the importer), so the context's "analysis-time effect" model is
   REFUTED: both arms' modules are parse-registered regardless of the fold.
   What the fold CAN and does control is analysis + emission: T3's
   `TYPE_NORETURN` stamp keeps the untaken arm un-analyzed, and the T3
   reachability closure (`main.zig` value-ref closure + `emitter.prune_active`)
   emits only reachable modules — dead modules get no `.c`/`.h`, so their
   `@cInclude`s cannot leak (measured: pre-fix NEITHER `a_*` NOR `b_*` was
   emitted; post-fix exactly the live module is). Emission-level pruning is the
   load-bearing gate; parse-level non-registration (true Zig: the file is never
   opened) needs a pipeline restructure (import queue timing / main.zig phase
   order) — out of T4's touch set (see Concerns C1).

3. **Phase timing.** `phase_FrontResolution` (which types module-scope
   `const` inits via `semanticAnalyzerResolveModuleVarDecl`) runs BEFORE
   `phase_ComptimeEvaluation` (which stamps `@isWindows()` into the shared fold
   table with target-correct polarity). So at decl-typing time the T3 probe
   cannot fold `@isWindows()`; a foldless resolve of the if form unifies two
   DIFFERENT module types and lands on the `SIF:FN` `void` tail (harmless —
   the symbol keeps no type), while a foldless switch would have poisoned the
   symbol with the FIRST prong's module (handled — see Implement).

4. **Switch-form root cause (parser).** Instrumented probes (temporary
   `stderr_write` traces, removed after) showed a two-prong `@import` switch
   reading back `prongs_n == 1` — always the LAST prong. Root cause:
   `parserParseBuiltinCall`'s `@import` arm does `self.child_buf_len = 0`
   (`parser.zig:712`, added `f18a16ed` "Diagnostics kept"), which DESTROYS the
   enclosing `child_buf` list in progress — the switch's prong list — before
   the second prong is appended; `parserListEnd` then attaches just the last
   one. (Pre-fix `conditional_import_switch_xmod` therefore parsed as a
   ONE-prong switch; its "OK class + link-fail" red is a consequence.) Case
   items were immune (`parserParseSwitchProng` already uses a parser-local
   list).

5. **Call/lower paths (no change needed).** `impl.ping()` types through
   `semanticAnalyzerResolveFieldAccess`'s `module_type` base arm once `impl`
   carries the live `module_type`, and lowers through the typed-callee path
   (`lower.zig` fn_type `call_direct` with the fn type's owner `module_id`) —
   so the call is a direct cross-module call and the live module gets its
   value-ref edge. `resolveModuleBase` already treats "module-typed global"
   as a module base; it just needs the type to exist.

## Implement

Touch set (all inside the plan's T4 list; `type_resolver.zig` and
`module_registry.zig` needed nothing): `sf/src/parser.zig`,
`sf/src/semantic_analyzer.zig`, `sf/src/lower.zig` + tech docs
(`docs/sf/Design_p2.md` §7.4, `docs/sf/AST_LIR_Lowering_p2.md` §3.1 note) +
fixture flip records.

1. **`semantic_analyzer.zig` — expr-position `import_expr` → `module_type`**
   (`semanticAnalyzerImportExprModuleType`: path payload →
   `moduleRegistryPathToIdGet` → `typeRegistryGetOrCreateModule`; unresolved
   path keeps `void` so error[3048] stays single-shot).
2. **`semantic_analyzer.zig` — T3 probe factored** (`semanticAnalyzerCondComptimeBool`,
   behavior-identical extraction of `semanticAnalyzerIfComptimeCondition`'s
   body: table-first → literal → local-const stamp fallback) and reused by the
   switch idiom + the alias fold.
3. **`semantic_analyzer.zig` — switch import-idiom selection**
   (`semanticAnalyzerSwitchIsImportIdiom`: every prong body an `import_expr`,
   paren-transparent). Comptime-known condition: only the LIVE prong (bool case
   item match, else fallback) is analyzed; untaken bodies `TYPE_NORETURN`-
   stamped (T3 coherence); switch type = live module type. Not-comptime-known:
   `void`, nothing analyzed (runtime-selected imports out of scope; keeps the
   pre-T4 observable). No-else still reports `error[3068]`.
4. **`semantic_analyzer.zig` — module-alias fold in `semanticAnalyzerResolveIdent`**
   (`semanticAnalyzerModuleAliasInitType`: bare `import_expr` / `if_expr` /
   `swt_ex` over imports with a comptime-known condition → live module type,
   cached on the symbol). This is the selection point for MODULE-SCOPE
   `const impl = …` — the decl fixpoint ran before the fold table was stamped,
   so the USE-site fold (table-backed, target-correct in later phases) types
   `impl` exactly like `const std = @import("std")`. Front-resolution stays
   foldless → `void` → symbol keeps no type → no wrong-module poisoning.
5. **`parser.zig` — switch prongs in a parser-local list** (the case-items
   pattern), bypassing the `@import` `child_buf` clobber. Ruling: `parser.zig`
   is in the plan's T4 file list and the switch form is unbuildable without it;
   the fix is scoped to the switch construct (the clobber itself is untouched —
   Concerns C2).
6. **`lower.zig`** — (a) `lowerModuleInit` skips module-alias inits
   (`lowerInitIsImportAliasShaped`: bare/if/switch-of-imports — no runtime
   value; previously emitted a garbage `zG_impl = zT_4294967295` store); (b)
   `lowerExprImpl`: an `if_expr`/`swt_ex` whose resolved type is `module_type`
   lowers to NO value (exactly the bare `import_expr` arm); (c)
   `resolveModuleBase` folds a module-alias init through
   `lowerModuleAliasInitModule` (shared-table `comptimeFoldBool` → live
   `@import` → module id) so value-position `impl.member` resolves even before
   the symbol cache settles.

T1/T2/T3 behavior preserved: `semanticAnalyzerIfComptimeCondition` semantics
byte-identical (pure extraction); every new path is gated on the
all-arms-`import_expr` shape or `module_type` result, which pre-T4 could not
occur (imports typed `void`).

## Runtime battery

8 items; every claim = command + observed output. Gate compiler
`/tmp/d1d2_t4/zig1_5_clean`. Sequential runs (spill-file race).

### 1. Seed two-hop / fixed point
```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_t4
→ hop2 == hop3 == e7099859f44e8050e7738be8545e8a58
  three-hop closure OK (moving point)
```
Fixed point old→new: `67abd038909ae211c839e493e895ba72` → **`e7099859f44e8050e7738be8545e8a58`**
(hop1≠hop2 is the script's recorded moving-point shape; T3 verdict (a) stands).

### 2. Corpus classify (universe 1132 = frozen 1124 + 8 designed)
```
bash scripts/corpus/classify /tmp/d1d2_t4/zig1_5_clean /tmp/d1d2_t4work/corpus_t4.txt
→ wrote …: 1132 dirs
frozen 1124 subset (8 designed fixture lines removed): md5 518eca1a9b5d3e1cc5a48abce214abd8
  diff vs T0 anchor (518eca1a9b5d3e1cc5a48abce214abd8) EMPTY → byte-identical, 0 movers
tally: 958 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH
```
**Frozen 1124 class-identical, 0 movers.** Ruling (set arithmetic): T3's
classify ran over 1131 dirs — its own `comptime_if_noelse_deadarm_xmod`
landed after that run — so the designed set is 8 (`fnptr_opt_aggregate_{coerce,emit}`,
`iswindows_deadarm_{errunion,prune,cond_if}`, `conditional_import_{if,switch}`,
`comptime_if_noelse_deadarm`); 1132−8=1124 and the md5 pins confirm it. Tally
delta vs a 1132-universe T3 snapshot = exactly the designed
`conditional_import_if` FAIL→OK flip.

Designed lines (all 8 OK):
`conditional_import_if_xmod` **FAIL→OK**, `conditional_import_switch_xmod`
OK→OK (class; link-red→links-and-runs at run level — the compile-only
classifier stays blind, per T0 ruling C4's run/link requirement), T0/T1/T2/T3
flips stable (`coerce`/`emit`/`errunion`/`prune`/`cond_if`/`comptime_if_noelse` OK).

### 3. Goldens 5/5
`zig1_5_clean -ffast --dump-c89 <ENTRY> > g.c` +
`gcc -m32 -std=c89 -O0 -Wno-long-long -Wno-pointer-sign -I sf/src/include g.c
sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o g`:

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 ./gol < /dev/null` rc 0 | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | same | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 ./lisp` rc 0 | `b3d9f8974da24ddbf9d389f3d7d97322` | same | YES |
| json | `cd examples/z98/json_parser && timeout 60 …/json` rc 0 | `8bda3d5a1ec07d14a301bc343df32bf8` | same | YES |
| mud server | `bash examples/z98/mud_server/demo/session.sh …` rc 0 | `66c8f0abb926cca7baf9a0d1692ab318` | same | YES |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | same | YES |

**5/5 MATCH.**

### 4. mi_matrix frozen-25 + oob trap
```
bash scripts/stdlib/run_fixtures.sh /tmp/d1d2_t4/zig1_5_clean <the frozen 25 dirs>
→ run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```
oob trap `slice_index_field_store_oob_xmod` (`-fsafe`): dump rc 0, build rc 0,
run **rc 133** (Trace/breakpoint trap), stdout 0 B md5
`d41d8cd98f00b204e9800998ecf8427e`. **MATCH.**

### 5. Examples 26/26 build + 26/26 run
Build per dir (`zig1_5_clean -ffast -o <out> <entry>` + `sh build_target.sh
linux <out>/prog`; `func_ptr_return`/`mandelbrot`/`quicksort`/`sort_strings`
take `<name>.zig` entries): **26/26 OK**. Run (CWD=example dir, `timeout 25`,
mud `timeout 8`, stdin `/dev/null`, rogue* fed `q\n`): **26/26 correct** —
stdout md5 prefixes match the T0/T3 table exactly: days_in_month `8c0d394c`,
fibonacci `b53b3a3d`, func_ptr_return `f6a54779`, gol `fcbf7e7c`, heapsort
`8cf0a784`, hello `74630882`, json `8bda3d5a`×2, workaround `dc22fa47`, lisp
`1c1f0a41`×4, lzw `c3c7765e`, mandelbrot `d5966775`, mud rc 124 `9545fe1d`,
prime `d095a94d`, quicksort `45d2f0fb`, rogue `3fb6709e`×2, sort_strings
`c6c047cb`, tco `264ea6b1`/`3d70c50b`/`7421137a`, z9play rc 1 `f35b7ef7`,
z9torr rc 1 `f666af15`.

### 6. Stdlib
```
bash scripts/stdlib/verify_stdlib.sh /tmp/d1d2_t4/zig1_5_clean
→ run_fixtures: 285 PASS / 0 FAIL over 285 dirs
  STDLIB GATE OK
```
**285/0 MATCH.**

### 7. The 8 `--dump-c89` pins (old→new)
| entry | `-fsafe` | `-ffast` | vs T3 table |
|---|---|---|---|
| `examples/z98/mud_server/main.zig` | `bbc02913a10af9b0b5ed0f292f4e3407` | `fa346108ed00d03a037c2f9331d3bdf8` | unchanged |
| `examples/z98/game_of_life/main.zig` | `93c5e3fdc5b80b2f3db020d995abbe3f` | `01a4e2265b33c97a8ca6ff3dfa551231` | unchanged |
| `examples/z98/lisp_interpreter_curr/main.zig` | `6da05d070acd414674b1b1ec947baa5c` | `e3970e33ac09c8dfaa316d2d69bf61ec` | unchanged |
| `examples/z98/json_parser/main.zig` | `af3823fae0b29fa4d4ca58932538d631` | `24e0e812e7dffa5a43750135405ffe3f` | unchanged |

**old→new: 0/8 movers.**

### 8. Markers telemetry
```
zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk.c 2> mk.bin
→ marker_lines=3436 bytes=38371
```
old→new: 3436/38371 → **3436/38371** (unchanged — the gate programs touch no
switch/import-idiom path). Recorded (telemetry, not a gate).

### Fixture flip-time evidence (designed flips)
```
bash scripts/stdlib/run_fixtures.sh --capture /tmp/d1d2_t4/zig1_5_clean \
  repro/mi_matrix/conditional_import_if_xmod repro/mi_matrix/conditional_import_switch_xmod
→ CAPTURED conditional_import_if_xmod (stdout 25 B, rc 0)
  CAPTURED conditional_import_switch_xmod (stdout 29 B, rc 0)
  2 PASS / 0 FAIL   (non-capture re-check: 2 PASS / 0 FAIL)
```
| fixture | pre-T4 (measured `67abd038…`) | post-T4 (measured `e7099859…`) | designed? |
|---|---|---|---|
| `conditional_import_if_xmod` | FAIL (gcc `zT_4294967295` undeclared; neither module emitted) | **OK** (`b_958020B9.c` only on linux / `a_67A30D4C.c` only on `-osw`; runs `b ping\ncond import if ok\n` / `a ping\n…` rc 0, 3x) | YES — FAIL→OK |
| `conditional_import_switch_xmod` | OK class, LINK-FAIL `undefined reference to 'zT_1'` | **OK** (`b_819BF014.c` / `a_2F9C6941.c`; links clean; runs `b ping\ncond import switch ok\n` / `a ping\n…` rc 0, 3x) | YES — link-red→links-and-runs |

Cross-build both ways (the point of the idiom): `-osw` dumps select `a_*`,
`build_target.sh mingw` (i686-w64-mingw32-gcc) clean, **wine** runs print
`a ping` rc 0; linux dumps select `b_*`, `build_target.sh linux` clean, native
runs print `b ping` rc 0. `@isWindows()` polarity follows the CLI target
through the sema fold AND the alias selection. `__module_init` is empty for
both (no garbage store).

## Concerns

- **C1 (parse-time module registration vs Zig's lazy open).** The untaken
  arm's `@import` file is still READ and PARSED (`parserParseImportExpr` →
  `moduleRegistryResolveImport`, `parser.zig:780`); only analysis and emission
  honor the fold (dead module: no `.c`/`.h`, no `@cInclude` leak — T3 closure).
  Zig would not open the file at all, so a dead-arm `@import("missing.zig")`
  still reports error[3048] and a dead-arm syntax error still surfaces. Full
  parity needs import-resolution deferred past the comptime fold (pipeline
  restructure: import queue timing / `main.zig` phase order / `import_resolver`
  — outside T4's file list; STOP-present if the operator wants it).
- **C2 (`@import` `child_buf` clobber is still live for other shapes).**
  `parserParseBuiltinCall`'s `self.child_buf_len = 0` (`parser.zig:712`) still
  corrupts any OTHER in-progress shared list containing `@import` (call-arg
  lists, tuple/array literals, fn-param flat lists). The switch prong list is
  fixed locally (parser-local list). The general fix is deleting that one line
  — deliberately NOT taken here (it changes non-idiom shapes = unrelated fix;
  corpus-mover risk). Recommend T6/final-review own it.
- **C3 (dead storage slot).** `const impl = if/switch …` still emits an unused
  `int zG_<hash>_impl;` global — `main.zig`'s `gv_is_storage` only exempts
  bare-`@import`/member-of-`@import` inits and `main.zig` is outside T4's file
  list. `__module_init` no longer initializes it (T4 skip) and nothing reads
  it; zero battery observability. A `main.zig` touch (exempt module-typed
  inits) would remove the slot.
- **C4 (switch case-item scope).** The idiom's live-prong match handles bool
  case items (`true`/`false` — the fixture spelling) and the `else` prong.
  Int-const case items in an import-idiom switch fall to the else/void path
  (narrow per "comptime-selected idiom ONLY"; trivially extensible via
  `lowerSwitchCaseItemValue`-style folding if ever needed).
- **C5 (foldless front-resolution analyzes both if-arms).** For module-scope
  bindings the strict Zig "untaken arm not analyzed" holds only from
  `phase_ComptimeEvaluation` onward (the decl fixpoint runs earlier with no
  fold table). For `@import` arms this is inert (post-parse imports have no
  sema diagnostics; registration is parse-time anyway), but a mixed-shape
  if (`if (c) @import("a") else 5`) now types `void` where it typed `INT_LIT`
  pre-T4 (imports used to be `void`) — no corpus fixture exercises it
  (frozen 1124 byte-identical) and Zig would reject the shape outright.
- **Rulings.** (1) `parser.zig` prong-list fix is in-scope: `parser.zig` is in
  the plan's T4 file list and the switch form cannot parse without it — the
  context's "parser untouched if `@import` already parses in expr position"
  held only grammatically; the list data was destroyed (measured `prongs_n==1`).
  Cost if wrong: one construct-local revert. (2) The context's "module
  registration is an analysis-time effect" is REFUTED (it is parse-time,
  `parser.zig:780`); the "skipped arm must not register/queue" requirement is
  met at the emission layer only — recorded as C1. (3) Battery set arithmetic:
  universe 1132 = frozen 1124 + 8 designed (T3's classify predated its own
  `comptime_if_noelse` fixture); md5 pin confirms. (4) Markers unchanged at
  3436/38371.
- **Deferred minors.** (none raised this round — the temporary debug probes
  were removed before the canonical build; the `true`/`false`-no-else switch
  spelling observation stays T0's, out of scope).

## Fix round (C1b + C2)

Operator rulings (Amendment 2, `8c1733ca`): C1b implement true Zig laziness
(touch set += `sf/src/main.zig`); C2 fix the `child_buf` clobber now; C3/C4
stay disclosed, unfixed. Gate compiler `/tmp/d1d2_t4/zig1_5_clean`, fixed
point **`20bd1a526abaf837190a53ae9f1b2f1a`** (old `e7099859f44e8050e7738be8545e8a58`).

### Mechanism

**C1b — dead-arm `@import` never loads its file.** `parserParseImportExpr`
skips `moduleRegistryResolveImport` when `Parser.dead_import_depth > 0`
(an `@import` inside a comptime-untaken `if`/`switch` arm body). The arm
context is tracked at the only place the condition is visible while the arm
parses — the parser itself:

- `parserParseIfExpr`/`parserParseIfStmt`: fold the condition with
  `parserFoldComptimeBool` (capture-free); untaken then/else bodies parse at
  `dead_import_depth+1` (nested structures inherit it; restore on exit).
- `parserParseSwitchExpr`/`parserParseSwitchProng`: the folded switch value
  selects ONE live prong (bool case items + `else`, first match wins — the
  C4 idiom spelling); every other prong body parses at `dead_import_depth+1`.
- `parserFoldComptimeBool` folds exactly what is knowable before any module
  analysis: `true`/`false` literals, `!`/`and`/`or` compounds, zero-arg
  `@isWindows()` (text-compared; target polarity via
  `ModuleRegistry.target_is_windows`, set from `cli.target_is_windows` in
  `main.zig`), and already-parsed immutable `const` bindings (a parse-time
  const map — block-scoped via `parserParseBlock`'s watermark). Anything
  else returns null → eager loading (conservative: a live import is never
  under-loaded).
- The `import_expr` node is still created (T3's fold stamps the dead arm
  `TYPE_NORETURN`; consumers of an unregistered path fall back to `void`).
- Module-scope conditional bindings: `semanticAnalyzerResolveModuleVarDecl`
  returns `void` for the if/switch-of-imports shape (module values have no C
  spelling — the storage slot keeps its disclosed-C3 `int` form); the SYMBOL
  is typed at use sites by T4's `semanticAnalyzerResolveIdent` module-alias
  fold.

**C2 — `parserParseBuiltinCall` `@import` `child_buf_len = 0` clobber
deleted.** The `@import` arm appends nothing to `child_buf`, so the standard
saved/append/listEnd protocol is correct without the reset. T4's switch-local
prong list stays.

**Investigation finding (id-order dependence).** The first implementation
interned `"@isWindows"` in `parserInitCommon` for the probe. The interner
assigns ids in INSERTION ORDER (`stringInternerIntern` returns the entry
index) — an extra intern before source lexing shifts EVERY later identifier
id. Measured: that shift ALONE flips `stdlib_crypto_modpow_xmod` OK→GREEN
(`error[3000]: unable to infer array size`, attributed to `std_io.zig:64`):
`git archive a7828e5e` baseline rebuilt clean → + 5 dummy `Parser` struct
fields (PASS) → + one extra early intern of ANY string ("@isWindows" OR a
never-used "@isWindowz") → FAIL. The latent id-order dependence is
pre-existing (out of scope); the fix avoids it entirely — the probe
recognizes `@isWindows` by TEXT, so the compiler interns nothing new and
interner ids stay byte-identical to T4. (Bisect artifacts: probe body /
const-map recording / C2 delete / semantic gate were each individually
suspect until the interning confound was isolated; all are restored and the
battery below is the authoritative evidence.)

### Probes (before → after)

| probe | before (T4 `e7099859…`) | after (fix round `20bd1a52…`) |
|---|---|---|
| dead-arm pin `if (false) @import("missing.zig") else @import("real.zig")` | `error[3048] … 'missing.zig'` rc 2 | silent rc 0; runs `real ping\ncond import lazy ok\n` |
| target polarity `if (@isWindows()) @import("missing.zig") else @import("real.zig")` | rc 2 both targets (eager) | linux silent rc 0 (`real ping\npolar ok\n`); `-osw` rc 2 `error[3048] missing.zig` (LIVE arm must resolve — target-selected, not suppression) |
| switch form `switch (false) { true => @import("missing.zig"), else => @import("real.zig") }` | rc 2 (eager) | silent rc 0; runs `real ping\nlazy sw ok\n` |
| C2 call args `three(1, @import("real.zig").k, 3)` | `error[3061]: expected 3 argument(s), found 2` rc 2 | rc 0, runs `c2 ok` |
| C2 tuple `.{ 1, @import("real.zig").k, 3 }` | silently 2 elements (`._0=7; ._1=3` in C) | 3 elements |
| C2 array `[_]i32{ 1, @import("real.zig").k, 3 }` | `error[3062]: index 2 outside array of length 2` rc 2 | rc 0, runs `c2 array ok` |

Fixture pin added (T0 R1 convention): `repro/mi_matrix/conditional_import_lazy_xmod`
(`if (false)` + `switch (false)` twins over a MISSING dead-arm file;
`missing.zig` deliberately absent). RED record `expected_error.txt`=`3048 2`
(pre-C1b rc 2 ×2), goldens captured at the flip (`expected.txt` 40 B
`real ping\nreal ping\ncond import lazy ok\n`, `expected.rc` 0). Both T4
fixtures stay green and now hold "only the live module is resolved/emitted"
at PARSE level too (`a_*`/`b_*` hashes unchanged on `-osw`:
`a_67A30D4C`/`a_2F9C6941`).

### Runtime battery

8 items, command + observed output. Sequential runs (spill-file race).

| # | gate | command | observed | verdict |
|---|---|---|---|---|
| 1 | seed two-hop | `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_t4` | hop2 == hop3 == `20bd1a526abaf837190a53ae9f1b2f1a` (old `e7099859…`) | MATCH (moving point) |
| 2 | corpus | `bash scripts/corpus/classify /tmp/d1d2_t4/zig1_5_clean …corpus_fix2.txt` | 1133 dirs; frozen 1124 md5 `518eca1a9b5d3e1cc5a48abce214abd8` (diff vs T0 EMPTY); tally 959 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH | frozen 0 movers; designed +1 (`conditional_import_lazy` FAIL→OK); 9/9 designed OK |
| 3 | goldens 5/5 | gol/lisp/json/mud builds + runs | `fcbf7e7c…`, `b3d9f897…`, `8bda3d5a…`, `66c8f0ab…`, `93147d0f…` | 5/5 MATCH |
| 4 | mi frozen-25 + oob | `run_fixtures.sh <25>`; oob `-fsafe` | 25 PASS / 0 FAIL; oob rc 133, 0 B, `d41d8cd9…` | MATCH |
| 5 | examples | build+run 26 dirs (CWD=example-dir) | 26/26 build; 26/26 md5s match the T0/T3 table (`8c0d394c`…`f666af15`) | MATCH |
| 6 | stdlib | `bash scripts/stdlib/verify_stdlib.sh …` | 285 PASS / 0 FAIL, STDLIB GATE OK | MATCH |
| 7 | 8 pins | `zig1_5_clean <mode> --dump-c89 <ENTRY> \| md5sum` | all 8 digests == T3 table | 0/8 movers |
| 8 | markers | `--markers --dump-c89 examples/z98/game_of_life/main.zig` | 3436 lines / 38371 B | unchanged |

Fixture cross-checks (green contracts, both targets): `conditional_import_if_xmod`
linux `b ping\ncond import if ok\n` rc 0 / `-osw`+mingw+wine `a ping\n…` rc 0
(`a_*`/`b_*` only); `conditional_import_switch_xmod` likewise (`…switch ok`);
`conditional_import_lazy_xmod` run_fixtures 3x byte-identical rc 0.

### Concerns (fix round)

- **F1 (latent interner id-order dependence — pre-existing, disclosed).** An
  intern added before source lexing shifts every later identifier id and
  deterministically flips `stdlib_crypto_modpow_xmod` OK→GREEN (measured on
  the pristine baseline: dummy fields pass, one extra intern of ANY text
  fails). Root channel unidentified (candidates: id-keyed caches/mangling
  internals); out of T4 scope. The T4 code interns nothing new (probe is
  text-compared) and the frozen-1124 gate is byte-clean, but any future code
  that interns early will re-trip it. Recommend a dedicated investigation.
- **F2 (probe coverage boundary, disclosed).** `parserFoldComptimeBool` folds
  literals/compounds/`@isWindows`/same-module in-order `const` bools; a
  cross-module const condition (`if (cfg.flag) @import("missing.zig") …`) or
  a forward-referenced local const is NOT folded at parse time → the dead
  arm's import still loads (and a missing one still errors). Conservative
  direction (never under-loads a live import); full Zig parity for those
  shapes needs symbol-aware folding later in the pipeline (touch-set widen).
- **F3 (C3/C4 unchanged, per ruling).** `int zG_impl` storage slot remains;
  switch live-prong match remains bool-case+else only.
- **F4 (fn-param flat `child_buf` protocol).** `parserParseFnDecl`'s param
  list uses a flat `child_buf_len = 0` protocol that clobbers an enclosing
  list when a fn-type appears inside one (same class as C2, different site).
  Pre-existing; not fixed here (no unrelated fixes).
