# T5 report — Static analyzers: adapt + truth-up

Plan: `docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md` Task 5.
Branch `zig1_improvements`. Gate compiler: seed-built
`/tmp/t5_work/post/zig1_5_clean` (hop2 == hop3 == `b0e5f3b4e580f69eacdac7bd0e07dda1`).
Status: **DONE_WITH_CONCERNS**.

## Investigate

### 1. T0 inventory (iii) re-verified against the current tree

T0 (`task-0-report.md` §1.3) claims `validateSignatureType` "has no rules at
all" for fn-ptr returns of `?Aggregate`/`E!Aggregate`, arbitrary-width ints,
`.tag` member access, packed-union members, and that Lifetime/NullPointer/
DoubleFree miss captures (tech-debt §2.1). Re-probed with the PRE-change
compiler (`/tmp/t5_work/pre/zig1_5_clean`, fixed point `8a9ea90a…` — built to
isolate behavior):

```
$ /tmp/t5_work/pre/zig1_5_clean -ffast --dump-c89 --output-dir out p8d_d1_shape.zig
rc=0 nc=4, stderr EMPTY            # `fn f(x: *void) ?Key` accepted (vacuous fall-through)
$ … p2b_arb.zig            # i7/u48/i3/u33 signatures
rc=0 nc=4, stderr EMPTY            # arb ints accepted (vacuous)
$ … p9/main.zig            # cross-module `m.Key`/`m.PU`/`?m.Key` signatures
rc=0 nc=5, stderr EMPTY            # member type exprs accepted (vacuous)
```

So the SignatureAnalyzer "gap" is acceptance-by-fall-through: non-ident type
nodes (`optional_type`, `error_union_type`, `fn_type`, `field_access`) are
never walked — the completeness/void/size rules do not reach nested bases and
`packed_union_type` is missing from the incomplete-type set
(`sf/src/analyzer.zig` old `validateSignatureType`, ident-only). Additional
measured gaps (not in T0's inventory):

```
$ … p0c_lifetime.zig       # `fn f() *i32 { var x; return &x; }` + capture shape
rc=0 nc=4, stderr EMPTY            # LifetimeAnalyzer INERT on real compiles
$ … p0b_free2.zig          # sandFree(s,p) twice + free-through-capture
rc=2, error[3035] double free 'p'; warning[3039] freeing untracked 'q' x2
$ … p7c_dead_arm           # `if (false) { sandFree(s,p); sandFree(s,p); }`
rc=2, error[3035] double free 'p'  # analyzer walks comptime-DEAD arms
```

Root causes found:
- **Lifetime inert on real code**: `symbol_registrator.zig` inserts only
  module-level symbols (globals/functions/modules/type aliases —
  `symbolTableInsert` callers all in `symbol_registrator.zig`); function
  locals/params are never in the `SymbolTable` the analyzer queries, so
  `classifyProvenance`'s `symbolTableLookup` always misses and returns
  `unknown`. The unit tests pass because they insert symbols manually.
- **Capture wiring miss-keyed**: `visitStatement`'s if/while capture used
  `astStoreNodePayload(node_idx)` as a state-map KEY; for `if_stmt` the payload
  is the `if_capture` NODE INDEX (cf. `lower.zig` `bindOptionalCapture`, which
  resolves capture node → payload = name id). The SAFE state was stored under
  the wrong key (vacuous `testIfCaptureRefinement` never noticed — it tests
  `stateMapFork` directly).
- **Dead-arm walk**: `runAllAnalyzers` walks the raw AST; T3's fold lives in
  the side `comptime_folds` table consumed by sema/lower only. Post-T3 the
  analyzer firing in a comptime-untaken arm is a false positive vs the Zig
  rule ("untaken arm does not exist for analysis").

### 2. Doc drift inventory

- `docs/design/static_analyzers.md` §1 "C89 Compatibility Rules" predates
  arb ints / packed unions / member type exprs / wrapper recursion; §2 "Known
  Limitations" lists "No Capture Propagation" (wrong post-T5); C++-era
  diagnostic names (`ERR_NON_C89_FEATURE`).
- `docs/sf/STATIC_ANALYZERS_p2.md`: `PtrState` discriminants documented 0–3
  (code: 10–13); SignatureAnalyzer checks table lacks the wrapper/wrapper-base
  rules; no capture propagation rows; pseudo-code sketches pre-self-hosting.
- `docs/tech_debt/static_analyzers.md` §2.1 "Status: Deferred" (the T5
  deliverable).

### 3. Change set stated up front (this section)

1. `validateSignatureType` → recursive (optional/error_union/ptr/many_ptr/
   slice/array/fn_type + `field_access` member type exprs); position codes
   (0=direct param → void rule; 1=direct/fn-ptr return → size rule; 2=nested);
   `packed_union_type` added to the incomplete-type reject set; explicit
   arbitrary-width-int acceptance (`parseArbIntWidth` family).
2. Capture propagation (`bindCaptureState` + `captureNameIdOf`) for
   if/while/for/switch-prong/`catch |e|` captures in all three passes; fixes
   the miss-keyed SAFE binding.
3. Lifetime base classification (§2.1's example needs it): address_of
   classification from analyzer state when the symbol table lacks the name
   (bare `&name` = call-frame slot; interior follows pointee provenance);
   `Provenance.external = 6` for pointer-like params (seeded at
   `runLifetimeAnalyzer` entry) so `&self.items[i]`-class returns stay safe.
4. Comptime-dead arms: `analyzerFoldComptimeBool` (bool-literal family,
   mirroring the parse-time probe's core) — capture-free `if` walks only the
   live arm (T3 Zig rule).
5. Tests: 10 new unit tests + 5 `tests/analyzers/**` fixtures + `testFixture`
   runner in `test_analyzer_bin.zig`; 3 docs truth-upped with
   `[updated: 2026-10-17 — …]` stamps.

## Implement

All edits in `sf/src/analyzer.zig` (bottom-to-top `edit`):
- `Provenance` + `external = 6`.
- `classifyProvenance` address_of arm: bare-vs-interior split; sym-kind path
  unchanged for test/global symbols; fallback (no symbol) = stateMap
  (`param`/`external` seeds, tracked value provenance) else conservative
  local; interiors map `external`/`heap`/`global` safe, `local`/`param*`/
  untracked → error classes. (`return &pool` (module `var`) stays `global`;
  `return &self.items[i]` (`*SymbolTable` self) stays `external` — both in the
  compiler self-source; measured self-emission clean.)
- `validateSignatureNamed` (new) + recursive `validateSignatureType`
  (`optional_type` child_0; `error_union_type` child_0/child_1; ptr/many/slice/
  array child_0; `fn_type` return at position 1 + param type list at position
  2 with `rejectAnytypeType`; `field_access` → member name via name cache).
  Void rule only at position 0; size rule only at position 1 (matches prior
  behavior for existing callers 0/1).
- `captureNameIdOf`/`bindCaptureState`/`analyzerFoldComptimeBool`/
  `paramTypeIsPointerLike` (new); `visitStatement` if/while/swt/for capture
  binding + dead-arm skip; `analyzeExpr` `if_expr` fold skip + `catch_expr`
  capture binding; `runLifetimeAnalyzer` param seeding (external vs param).

D1 acceptance re-proven on the POST compiler:

```
$ /tmp/t5_work/post/zig1_5_clean -ffast --dump-c89 … p8d_d1_shape.zig → rc=0 nc=4 stderr EMPTY
$ … p2b_arb.zig → rc=0 nc=4 EMPTY     $ … p9/main.zig → rc=0 nc=5 EMPTY
$ … p0c_lifetime.zig → rc=2 error[3030] 'x' + warning[3032] 'ptr'   # §2.1 flagged
$ … p7c → rc=0 (dead arm skipped; live leak warning 'p' correct — the frees are dead)
$ … p0b_free2.zig → error[3035] via capture q; 'q' untracked on the `var op = p` alias chain (tech-debt §4.3)
```

## Analyzer tests

Invocation (established; `sf/scripts/build_test.sh` is pre-existing 0/9 rot —
zig0 dialect drift — and was NOT used):

```
/tmp/t5_work/post/zig1_5_clean -ffast --dump-c89 --output-dir /tmp/t5_work/gate \
    sf/src/tests/test_analyzer_bin.zig                    # dump rc=0
sh /tmp/t5_work/gate/build_target.sh linux test_analyzer_bin   # build rc=0
(cd /workspace/znineeight && /tmp/t5_work/gate/test_analyzer_bin)   # run rc=0
→ 59 × "  ok …" then "Analyzer tests passed."
```

(`-ffast` is required: default emission instruments integer overflow and the
embedded lexer's `parseU64` `max_u64 -= 1` traps on the first number literal —
toolchain semantics, pre-existing.)

59/59 green: 44 pre-existing unit tests + 10 new
(`testSignatureFnPtrOptAggregate`, `testSignatureFnPtrErrUnionAggregate`,
`testSignatureNestedIncomplete`, `testSignatureArbIntAccepted`,
`testSignaturePackedUnionIncomplete`, `testSignatureMemberTypeAccepted`,
`testCaptureLifetimePropagation` (§2.1), `testCaptureNullSafe` (wiring fix),
`testCaptureDoubleFree`, `testDeadArmSkipped`) + 5 fixtures run by the new
`testFixture` runner (`tests/analyzers/{fnptr_opt_aggregate,capture_lifetime,
capture_double_free,dead_arm,surface_types}.zig`, contracts in
`tests/analyzers/NOTES.md`).

## Docs

- `docs/design/static_analyzers.md` — §1 C89 rules truth-up (wrappers, arb
  ints, packed unions, member types, real diagnostic names), §2 limitations
  (captures RESOLVED + base classification), §3 captures row, §4 capture
  limitation row. Stamps `[updated: 2026-10-17 — D1/D2 surface + drift
  truth-up]`.
- `docs/sf/STATIC_ANALYZERS_p2.md` — §3.2 checks table rewritten (+ accepted
  surface; ERR 2013 marked reserved), §3.3 sketch note, §4.2 `PtrState`
  discriminants corrected to 10–13, §4.3 capture rows, §5.2 `external = 6`,
  §5.3 capture rule row, §5.6 limitations, §6.3 capture row.
- `docs/tech_debt/static_analyzers.md` — §2.1 Deferred → RESOLVED (mechanism +
  fixture), new §4.1 (partial dead-arm fold probe), §4.2 (return/init exprs
  not walked + param-not-seeded false warnings), §4.3 (capture aliasing
  limits).

## Runtime battery

Gate compiler `/tmp/t5_work/post/zig1_5_clean` (seed-built from the fixed
tree; `three-hop closure OK (moving point): hop2 == hop3 ==
b0e5f3b4e580f69eacdac7bd0e07dda1`). Sequential runs.

| # | item | command | observed | verdict |
|---|---|---|---|---|
| 1 | corpus | `bash scripts/corpus/classify /tmp/t5_work/post/zig1_5_clean /tmp/t5_work/corpus_t5.txt` | 1133 dirs; frozen 1124 subset (9 designed lines removed) md5 **`518eca1a9b5d3e1cc5a48abce214abd8`**; tally 959 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH; designed 9/9 OK | frozen **byte-identical, 0 movers**; no designed flips |
| 2 | goldens 5/5 | `-ffast --dump-c89` + `build_target.sh linux` + runs | gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`, lisp `b3d9f8974da24ddbf9d389f3d7d97322`, json `8bda3d5a1ec07d14a301bc343df32bf8`, mud srv `66c8f0abb926cca7baf9a0d1692ab318` / cli `93147d0f0bbd983a9d844fea8b7a6fa7` | **5/5 MATCH** |
| 3 | mi_matrix frozen-25 + oob | `bash scripts/stdlib/run_fixtures.sh /tmp/t5_work/post/zig1_5_clean <25 frozen dirs>`; oob `-fsafe` recipe | `run_fixtures: 25 PASS / 0 FAIL over 25 dirs`; oob trap: dump rc 0, build rc 0, run **rc 133**, stdout 0 B `d41d8cd98f00b204e9800998ecf8427e` | **MATCH** |
| 4 | examples | per-dir `-ffast -o` + `build_target.sh linux` + run (CWD=dir, timeout 25, mud 8 rc 124, stdin /dev/null, rogue* `q\n`) | **26/26 build, 26/26 run**; all stdout md5 prefixes == T0/T3 table (`8c0d394c`,`b53b3a3d`,`f6a54779`,`fcbf7e7c`,`8cf0a784`,`74630882`,`8bda3d5a`×2,`dc22fa47`,`1c1f0a41`×4,`c3c7765e`,`d5966775`,mud rc124 `9545fe1d`,`d095a94d`,`45d2f0fb`,`3fb6709e`×2,`c6c047cb`,`264ea6b1`,`3d70c50b`,`7421137a`,z9play rc1 `f35b7ef7`,z9torr rc1 `f666af15`) | **MATCH** |
| 5 | stdlib | `bash scripts/stdlib/verify_stdlib.sh /tmp/t5_work/post/zig1_5_clean` | `run_fixtures: 285 PASS / 0 FAIL over 285 dirs` / `STDLIB GATE OK` | **285/0 MATCH** |
| 6 | seed two-hop | `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t5_work/post` | `three-hop closure OK (moving point): hop2 == hop3 == b0e5f3b4e580f69eacdac7bd0e07dda1` | fixed point old `8a9ea90a4976165b2074279be7f7ab32` → **new `b0e5f3b4…`** (verdict (a) moving point) |
| 7 | 8 pins | `zig1_5_clean <mode> --dump-c89 <ENTRY> \| md5sum` | gol `93c5e3fdc5b80b2f3db020d995abbe3f`/`01a4e2265b33c97a8ca6ff3dfa551231`; lisp `6da05d070acd414674b1b1ec947baa5c`/`e3970e33ac09c8dfaa316d2d69bf61ec`; json `af3823fae0b29fa4d4ca58932538d631`/`24e0e812e7dffa5a43750135405ffe3f`; mud `48f188df6b5f09cb1614c532ae7e825a`/`243369f4a942ad27f75b3c391581bd29` | **0/8 delta** (identical to T4.1 values incl. F1-moved mud pair) |
| 8 | markers | `zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk.c 2> mk.bin` | `marker_lines=3436 bytes=38371` | **unchanged** vs 3436/38371 baseline |

## Concerns

- **Lifetime base revival = scope judgment call (STOP-present form).**
  `I found the intention is` §2.1's example detectable (`if (opt_ptr) |ptr|
  { return ptr; }` where opt_ptr points at a local) `but this is impossible
  given` the real pipeline's symbol tables never contain function
  locals/params (`symbol_registrator.zig` inserts module-level names only) —
  `classifyProvenance` was inert on every real compile (measured: `return &x`
  silent, PRE compiler). Options were (a) ship capture propagation on a dead
  base (unit-test-only coverage), or (b) also classify from analyzer-internal
  state. Implemented (b) (analyzer.zig-only, `Provenance.external` + bare/
  interior rules) because the named deliverable is the §2.1 example, and gated
  it on the battery: frozen-1124 byte-identical 0 movers, pins 0/8, goldens
  5/5. If the reviewer scopes T5 to capture propagation only, the
  classifyProvenance/runLifetimeAnalyzer hunks are independently revertable
  (the capture tests pass under the manual-symbol model too).
- **Comptime-dead arms: partial (T3 interaction).** Context directive "decide
  per Zig semantics (untaken arm does not exist) and truth-up docs" honored
  for the capture-free bool-literal family (`analyzerFoldComptimeBool`;
  fixture `tests/analyzers/dead_arm.zig`). Full T3-parity (evaluator-folded
  `KIND_BOOL` incl. consts/compounds/`@isWindows`, switch prongs) needs the
  shared `comptime_folds` table plumbed into `AnalyzerContext` — that touches
  `main.zig`/`comptime_eval.zig`, outside T5's plan touch set. Recorded as
  tech-debt §4.1. Cost if wrong: dead-arm false diagnostics survive for
  evaluator-only folds (the pre-T5 status quo for ALL folds).
- **NullPointer residual walk gap (disclosed, unfixed).** `analyzeExpr` is
  not invoked for `return` expressions or `var` initializers (deref in
  `return p.*` unchecked) and params are not seeded in the null state map
  (measured: 44 false WARN_6002 on the compiler self-source — warning-level,
  class-safe). Pre-existing; fixing changes warning volume on live code —
  left as tech-debt §4.2.
- **Capture aliasing (DoubleFree) left limited.** `var p = alloc(); var op =
  p; if (op) |q| { sandFree(s,q); }` keeps `op` untracked (assign-propagation
  gap), so frees via `q` warn "untracked" and cross-name double frees are not
  checked (tech-debt §4.3). The direct shape `var op = sandAlloc(...);
  if (op) |q|` IS covered (fixture `capture_double_free.zig`).
- **Pre-existing rot, untouched (disclose-only).** `sf/scripts/build_test.sh`
  0/9 (zig0 rejects current `ast.zig` etc.), `test_sym_reg_bin.zig` stale vs
  `semanticAnalyzerInit`, `error[19]`-class diagnostic-code rendering
  (ERR_3000 enum lacks `=3000`), `test_analyzer_bin.zig`'s `Symbol{…}`
  initializers missing `file_id` (zig1 zero-fills missing struct-init fields —
  compiles/runs; zig0 would reject). None touched per the no-unrelated-fixes
  rule.
- **Test-binary emission mode.** The suite must be built with `-ffast` (see
  Analyzer tests); default-mode builds trap in the embedded lexer's
  `parseU64` (`max_u64 -= 1` underflow check). Toolchain semantics, pre-existing.
- **Warning-code rendering in observed output** (`warning[3037]` = WARN_6002
  etc.) is the pre-existing enum-rendering drift; the docs truth-up describes
  the enum codes (2004/2005/2010–2012/2020–2021/6001–6011/7001/7010).
