# Task 3 report — Comptime-if fold (D2 root) + module-closure fix

Branch `zig1_improvements`. Scope: D2 at root (Amendment 1 touch set
`{semantic_analyzer.zig, lower.zig, comptime_eval.zig, main.zig}` as ONE task).
Binding spec: `docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md`
§3 (its Consequence paragraph is falsified — see §Investigate; T6 owns the
truth-up, the spec was NOT edited). `examples/torrent_example_defects.md`,
`run.err`, untracked `audio_win9x*.zig`, `progress.md` left alone (T6/other
owners). `comptime_eval.zig` required NO edit (its existing APIs carried the
whole trigger set).

Gate compiler: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_t3`
→ `/tmp/d1d2_t3/zig1_5_clean` (hop1 md5 `6de5b2e15d6fe81f6e9466b5e6698b22`);
self-hosted fixed point **hop2 == hop3 == `362fcfb25d88068388755fc1e0ce6c2d`**
(old→new: `6e6d1262e4a286486d2f478961fbd040` → `362fcfb2…`). hop1 ≠ hop2 is the
script's recorded "moving point" shape (previously seen at FX14-F): the T3 fold
changes how `sf/src` compiles ITSELF (comptime-known `if`s inside the compiler
sources now eliminate dead arms in the self-compile C). hop1 and hop2 were
verified to emit byte-identical output on user programs (prune fixture: same
emission set, `main_*.c` identical), so the battery runs on `zig1_5_clean`
per the task-3-context command. Pin compiler (pre-T3 behavior): `/tmp/d1d2_t2/zig1_5_clean`
md5 `6e6d1262e4a286486d2f478961fbd040` (post-T2 tree == pre-T3 tree).

---

## Investigate

### Channel re-verification — the context's "real leak" attribution is FALSIFIED

The task-3-context attributes the D2 leak to the main.zig:1306+ all-fn scan +
`pruneTypeMarkByValue` type-owner module marking. A probe matrix on the pin
compiler (fixture variants in `/tmp/d1d2_t3work/p_*`, all run as
`zig1_5_clean -ffast --dump-c89 --output-dir <dir> <main.zig>`, sequential —
spill-file race) refutes that as the operative pin:

| probe | shape (base = `iswindows_deadarm_prune_xmod`) | windep emitted? |
|---|---|---|
| `p_noeu` | windep keeps `var g: u32 = 0` (runtime-init), `open` returns plain `*void` (no EU) | **YES** |
| `p_undef` | windep keeps EU `E!*void` return, global becomes `var g: u32 = undefined` (storage global, `has_runtime_init=0`) | no |
| `p_nog` | windep has no global at all, EU return intact | no |
| `p_unused` | windep has no global; a NEVER-CALLED `fn helper()` in the live root calls `windep.open` | **YES** |
| `p_lit` | dead arm is `else` of `if (true)` (literal condition), windep global-less | **YES** (pre-fix) |
| `p_cconst` | dead arm behind `if (use_win)` (module `const bool = false`), windep global-less | **YES** (pre-fix) |

Conclusions (measured, not inferred):

1. **The operative D2 pin is the unconditional runtime-init root seed**
   (`main.zig` phase_C89Emission, pre-fix `:1389-1408`): any module with a
   runtime-initialized global (`var g: u32 = 0` counts — the init is a
   coercion-wrapped literal, `has_runtime_init=1`, `__module_init` emitted)
   got a force-edge root→module regardless of call/type reachability. `p_noeu`
   (global, NO error-union anywhere) still pins windep; `p_undef`/`p_nog`
   (no runtime-init global) do not. This is the leak.
2. **The `pruneTypeMarkByValue` type-owner channel does NOT pin these shapes.**
   Composites mint `module_id=0` (`type_registry.zig` GetOrCreate sites); the
   owner mark fires only for NAMED types (the per-module error set `E`). Main's
   live arm references only `linuxdep.E` (the shared EU typedef
   `zT_D078880E_EU_46` is module-less), and windep's own fn's types are
   same-module (`ty.module_id == src_mid` → no edge). The channel is real code
   and load-bearing for cross-module type spellings, but it was not the pin.
3. **The all-fn LIR scan is load-bearing, not a leak.** `p_unused`: a
   never-called `fn helper()` in the live root module is still EMITTED
   (modules are emitted atomically with ALL their lowered fns —
   `emitFunctionSet` walks the module's whole slot range), and its
   `call_direct`/`func_ref`/type edges are exactly what keeps its callees'
   modules compiled-in for the link. Restricting the scan to call-reachable
   fns (the context's fix-shape (a)) would make `main.c`'s `helper` call an
   undefined `windep` fn → link failure. Fix-shape (b) (type-owner edges only
   from reachable fns) has the same problem and, separately, does not touch the
   operative pin at all.
4. **The lowering fold was missing trigger-set shapes** (in scope per the
   dispatch's probe rule): `p_lit` (`if (true)`) and `p_cconst` (`if (comptime
   const)`) still emitted the dead arm's module pre-fix, because
   `phase_ComptimeEvaluation`'s if-domain stored only no-`else` `if_expr`
   conditions (and `@isWindows()` via the builtin-calls sweep). The fold
   machinery (`if_fold`/`ie_fold` consuming `comptimeFoldBool`) was fine; the
   table never carried these conditions.
5. Spec §3's Consequence paragraph ("dead-arm LIR refs … module-reference
   edges … no longer exist") describes a channel that measured away at T0 and
   is not the fix lever. As ordered: NOT edited (T6 truth-up).

### Chosen closure mechanism (Ruling T3-A)

**Reachability-consistent runtime-init edge** (one mechanism, in
`sf/src/main.zig`): the runtime-init root edge is no longer a force-seed BEFORE
the closure; it is added AFTER the closure, only for ALREADY-reachable modules
with runtime-init globals. Why this and not the context's named shapes:

- It is the measured pin (probe matrix above); the named shapes cannot deliver
  D2 green (the pin is a different edge) and fix-shape (a) is unsafe under
  atomic module emission (`p_unused` link proof).
- Blast radius is minimal and provable: for every LIVE module the edge set is
  identical to pre-T3 (the seed edges for reachable modules are simply added
  later), so root-header includes and `__module_init` emission for live modules
  are byte-for-byte unchanged. Only modules with NO call/type/instruction
  path from the root drop out — exactly the comptime-dead D2 modules. Zig's
  lazy module-init semantics agree: a module nothing references has no
  observable globals.
- `--dump-c89` pins are structurally unaffected by the closure at all: the
  single-file path (`emitModule`, no `--output-dir`) emits every slot and uses
  `cincludeUnionAll`; only the multi-file `--output-dir` path consults
  `reachable`/`prune_active`. Observed 0/8 pin movement (below) is therefore
  expected for the closure half; any pin movement would have been attributable
  to the fold half (operator-acceptable per spec §6).
- Cost if wrong: a program whose comptime-dead module's `__module_init` has
  side effects on LIVE state (writes another module's global / calls a live fn
  with observable effect) would silently lose those side effects. The battery
  (frozen 1124 class-identical, goldens 5/5, examples 26/26, stdlib 285/0,
  pins 0/8) found no such shape in the corpus. If one appears, the fix is to
  seed fn-reachability from `__module_init` of modules whose init bodies carry
  cross-module stores/calls.

### Sema gate design (the Zig rule)

Trigger set = the narrow fixture-pinned spec §3 set, implemented as
`semanticAnalyzerIfComptimeCondition` (`semantic_analyzer.zig`), consulted by
BOTH the value-`if` resolver and the `if_stmt` statement walker, only for
`if`/`else` pairs (child_2 != 0; no-`else` keeps the pre-T3 walk — the §3 rule
is stated for `if`/`else`, and the error[3059] no-else gate types the then-arm
(`if_noelse_reject_xmod` rows must not move — they did not: frozen 1124
byte-identical)):

1. capture conditions (`if (opt) |v|`) never gate (payload != 0);
2. literal `true`/`false` → gate;
3. shared fold-table KIND_BOOL entries (`@isWindows()` via the builtin sweep;
   comptime `const`/constant folds via T3's extended if-condition sweep) →
   gate. The table is populated by `phase_ComptimeEvaluation` with
   `ce.host_is_windows = ctx.cli.target_is_windows`, so `@isWindows()` polarity
   follows the CLI target — proven by the `-osw` wine runs below;
4. function-local comptime `const` bool (evaluator, local-const aware) → fold,
   **stamp** into `ctx.comptime_folds` (via the new
   `SemanticAnalyzer.comptime_folds` pointer, bound in
   `phase_SemanticAnalysis`) and gate. Stamping keeps sema and lowering on the
   SAME arm (coherence: sema never leaves an arm un-analyzed that lowering
   still lowers — every gate fires only when a table entry exists or is made).
   Without a table to stamp (front-resolution's pass) the fallback does not
   trigger; that pass over-analyzes both arms (safe).

Gate behavior: the untaken arm is not analyzed (statement walker only pushes
the live arm; value-`if` resolves only the live arm) and is stamped
`TYPE_NORETURN` so the existing result-typing tail resolves the `if` to the
live arm's value/type (expected-type coercion, noreturn-arm paths — the exact
machinery a diverging arm already took). FX9's f32 arm-reachability now reads
the gate's verdict first (the un-analyzed arm's float-narrow status is not
walked). Lowering's `ie_fold` keeps folding on the same table entries; its old
`ie_rtype3 != TYPE_NORETURN` second-line guard is superseded by an explicit
noreturn branch (live arm lowered via `lowerIfArmValue`, block terminated) —
required for coherence (a noreturn-typed folded `if` must not fall through to
the both-arms path and lower an un-analyzed arm).

Lowering trigger-set gap (in scope per the probe): `phase_ComptimeEvaluation`'s
if-domain now stores KIND_BOOL folds for EVERY capture-free `if` condition
(`if_expr` any + `if_stmt`) — literals, comptime consts, `@isWindows()`,
constant folds. `lower.zig` needed no fold-path rewrite beyond the noreturn
branch (the `if_fold`/`ie_fold` consumers already key on the condition node).

### Corpus re-verification of the dead-arm scan (inherited from T0)

T0's scan (zero reject fixtures whose only error sits in a comptime-dead arm)
covers literal/`@isWindows()`/`and`-`or` patterns; the T3 trigger set adds
module/fn-local `const` conditions. The frozen-1124 byte-identity gate (below)
is the cheap re-verification: 0 movers, so no pre-existing reject fixture's
census depends on a dead arm under the wider trigger set. `f32_narrow_reject_xmod`
census re-measured (C3 watch): still 39 × `error[3000]` (18 FX3 + 15 FX9 + 6
FX10), class GREEN stable — no header edit needed.

---

## Implement

Files touched: `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`,
`sf/src/main.zig` (+ tech docs + fixtures; `comptime_eval.zig` unchanged).

1. `main.zig` — closure fix (Ruling T3-A): unconditional runtime-init
   force-seed deleted; post-closure root edges only for reachable RI modules
   (live-module include set byte-identical).
2. `main.zig` — `phase_ComptimeEvaluation` if-domain extended to all
   capture-free `if_expr`/`if_stmt` conditions (KIND_BOOL folds).
3. `main.zig` — `sa.comptime_folds = &ctx.comptime_folds` binding in
   `phase_SemanticAnalysis`.
4. `semantic_analyzer.zig` — `comptime_folds: ?*ComptimeFoldTable` field (init
   `null`; `front_resolution.zig` call sites unchanged and out of the touch
   set — they over-analyze both arms, safe); `semanticAnalyzerIfComptimeCondition`
   (trigger set + local-const stamp); gated `semanticAnalyzerResolveIfExpr`
   (untaken arm unstudied, stamped `TYPE_NORETURN`, if takes the live arm);
   gated `if_stmt` work-push (live arm only); FX9 reach reads the gate verdict.
5. `lower.zig` — `ie_fold` noreturn-typed folded `if` eliminates the untaken
   arm (guard superseded).
6. New fixture `repro/mi_matrix/iswindows_deadarm_cond_if_xmod` (sema gate:
   dead-arm errors vanish, live-arm value/type pins) + goldens captured at
   flip; `iswindows_deadarm_errunion_xmod` goldens captured at flip;
   `iswindows_deadarm_prune_xmod` goldens preserved byte-identical.
   NOTES.md mechanism-correction + flip records appended (the fixture NOTES
   "Mechanism" attribution is superseded by the probe matrix; the SPEC text is
   untouched — T6 owns it).
7. Tech docs (changed subsystems, T2's `[updated: 2026-10-16 …]` style):
   `docs/sf/Design_p2.md` §7 (sema gate), `docs/sf/AST_LIR_Lowering_p2.md`
   (fold paths), `docs/sf/LIR_C89_Emission_p2.md` §0 (module closure).

Designed flips (NEW fixtures only; frozen 1124 byte-identical, 0 movers):

| fixture | pre-T3 (measured) | post-T3 (measured) | designed? |
|---|---|---|---|
| `iswindows_deadarm_errunion_xmod` | FAIL (both targets: wrong-platform `@cInclude` kills gcc/mingw) | **OK** (wrong-platform module NOT emitted both targets; runs `iswindows deadarm ok` rc 0) | YES — FAIL→OK |
| `iswindows_deadarm_prune_xmod` | OK (runtime golden; `windep_*.c` emitted = emission red) | OK (golden byte-identical; `windep_*.c` ABSENT on linux / `linuxdep_*.c` ABSENT on `-osw`) | YES — OK→OK + emission pruned |
| `iswindows_deadarm_cond_if_xmod` (NEW) | FAIL (rc 2, 0 `.c`, `error[20]`×3 dead-arm rows; `expected_error.txt` + `expected.rc=2`) | **OK** (dead-arm errors vanish; runs `cond if ok` rc 0, `x==2`/`q==42` live-arm value pins; `expected.rc` flipped 2→0 at capture) | YES — FAIL→OK |

Observation (T4's deliverable, NOT claimed): `conditional_import_if_xmod`
stays FAIL and `conditional_import_switch_xmod` stays OK+link-fail — T3's fold
did not flip them (their gap is `@import` in expression position, T4 scope).

---

## Runtime battery

8 items; every claim = command + observed output. Gate compiler
`/tmp/d1d2_t3/zig1_5_clean`. Sequential runs (spill-file race).

### 1. Seed two-hop / fixed point
```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_t3
→ hop1 6de5b2e15d6fe81f6e9466b5e6698b22
  hop2 == hop3 == 362fcfb25d88068388755fc1e0ce6c2d
  three-hop closure OK (moving point)
```
**MATCH** (closure held at hop2==hop3). Fixed point old→new:
`6e6d1262e4a286486d2f478961fbd040` → **`362fcfb25d88068388755fc1e0ce6c2d`**
(moving point: the T3 fold changes the compiler's self-compile C; hop1≠hop2 is
the script's recorded shape. hop1/hop2 user-program outputs verified
byte-identical). Seed rotation stays closeout-owned.

### 2. Corpus classify (post-T0 1130-line universe + new fixture = 1131)
```
bash scripts/corpus/classify /tmp/d1d2_t3/zig1_5_clean /tmp/d1d2_t3work/corpus_t3.txt
→ wrote …: 1131 dirs
frozen 1124 subset (7 designed fixture lines removed): md5 518eca1a9b5d3e1cc5a48abce214abd8
  diff vs T0 anchor (518eca1a9b5d3e1cc5a48abce214abd8) EMPTY → byte-identical, 0 movers
tally: 956 OK / 58 GREEN / 117 FAIL / 0 ICE / 0 CRASH
```
**Frozen 1124 class-identical, 0 movers.** Designed lines:
`errunion FAIL→OK`, `cond_if FAIL→OK (new dir)`, `prune OK→OK`, coerce/emit OK
(T2 flips stable), `conditional_import_if` FAIL / `conditional_import_switch` OK
(unchanged — T4). Tally delta vs T2 (954/58/118 over 1130) = exactly the two
designed OK gains minus one designed FAIL flip.

### 3. Goldens 5/5
Build (`zig1_5_clean <mode> --dump-c89 <ENTRY> > g.c` +
`gcc -m32 -std=c89 -O0 -Wno-long-long -Wno-pointer-sign -I sf/src/include g.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o g`): all 4 dump rc 0, gcc rc 0, 0 `error:`.

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 ./game_of_life < /dev/null` rc 0 | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | same | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 ./lisp_interpreter_curr` rc 0 | `b3d9f8974da24ddbf9d389f3d7d97322` | same | YES |
| json | `cd examples/z98/json_parser && timeout 60 …json_parser` rc 0 | `8bda3d5a1ec07d14a301bc343df32bf8` | same | YES |
| mud server | `bash examples/z98/mud_server/demo/session.sh …` rc 0 | `66c8f0abb926cca7baf9a0d1692ab318` | same | YES |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | same | YES |

**5/5 MATCH.**

### 4. mi_matrix frozen-25 + oob trap
```
bash scripts/stdlib/run_fixtures.sh /tmp/d1d2_t3/zig1_5_clean <the frozen 25 dirs>
→ run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```
oob trap `slice_index_field_store_oob_xmod` (`-fsafe` recipe): dump rc 0,
build rc 0, run **rc 133** (Trace/breakpoint trap), stdout 0 B md5
`d41d8cd98f00b204e9800998ecf8427e`, `expected.rc` pin 133. **MATCH.**

### 5. Examples 26/26 build + 26/26 run
Build (`zig1_5_clean -ffast -o <out> <entry>` + `sh build_target.sh linux <out>/prog`,
CWD out-dir): **26/26 OK** (dump rc 0, ≥1 `.c`, build rc 0). Run (CWD=example
dir, `timeout 25`, mud `timeout 8` rc 124, stdin `/dev/null`, rogue* fed `q\n`):
**26/26 correct** — every stdout md5 matches the T0 table (days_in_month
`8c0d394c…`, fibonacci `b53b3a3d…`, func_ptr_return `f6a54779…`, gol
`fcbf7e7c…`, heapsort `8cf0a784…`, hello `74630882…`, json `8bda3d5a…`×2 +
workaround `dc22fa47…`, lisp `1c1f0a41…`×4, lzw `c3c7765e…`, mandelbrot
`d5966775…`, mud rc 124 `9545fe1d…`, prime `d095a94d…`, quicksort `45d2f0fb…`,
rogue `3fb6709e…`×2, sort_strings `c6c047cb…`, tco `264ea6b1…`/`3d70c50b…`/
`7421137a…`, z9play rc 1 `f35b7ef7…`, z9torr rc 1 `f666af15…`).

### 6. Stdlib
```
bash scripts/stdlib/verify_stdlib.sh /tmp/d1d2_t3/zig1_5_clean
→ run_fixtures: 285 PASS / 0 FAIL over 285 dirs
  STDLIB GATE OK
```
**285/0 MATCH.**

### 7. The 8 `--dump-c89` pins (old→new)
`zig1_5_clean <mode> --dump-c89 <ENTRY> | md5sum` (repo root):

| entry | `-fsafe` | `-ffast` | vs QUICK_REF 2026-10-16 table |
|---|---|---|---|
| `examples/z98/mud_server/main.zig` | `bbc02913a10af9b0b5ed0f292f4e3407` | `fa346108ed00d03a037c2f9331d3bdf8` | unchanged |
| `examples/z98/game_of_life/main.zig` | `93c5e3fdc5b80b2f3db020d995abbe3f` | `01a4e2265b33c97a8ca6ff3dfa551231` | unchanged |
| `examples/z98/lisp_interpreter_curr/main.zig` | `6da05d070acd414674b1b1ec947baa5c` | `e3970e33ac09c8dfaa316d2d69bf61ec` | unchanged |
| `examples/z98/json_parser/main.zig` | `af3823fae0b29fa4d4ca58932538d631` | `24e0e812e7dffa5a43750135405ffe3f` | unchanged |

**old→new: 8/8 UNCHANGED (0/8)** — the closure change is structurally
invisible to `--dump-c89` (single-file path), and the fold half happened to
move nothing in the four gate programs.

### 8. Markers telemetry
```
zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk.c 2> mk.bin
→ marker_lines=3436 bytes=38371
```
old→new: 3437 lines / 38384 B → **3436 / 38371** (−1 line / −13 B; one `DC:k`
call marker gone — a comptime-dead arm's call no longer emits a marker).
Recorded (telemetry, not a gate).

### D2 fixture cross-build + target-polarity evidence
- `iswindows_deadarm_errunion_xmod`: linux `-ffast --dump-c89` rc 0 →
  `windep_*.c` ABSENT (only `linuxdep_6F2C77EB.*` + std); `build_target.sh
  linux` clean; run `iswindows deadarm ok` rc 0. `-osw` dump rc 0 →
  `linuxdep_*` ABSENT (only `windep_5A55131B.*`); `build_target.sh mingw`
  clean (i686-w64-mingw32-gcc); **wine run `iswindows deadarm ok` rc 0** (the
  WIN arm executed — `@isWindows()` polarity follows the CLI target through
  both the sema gate and the lowering fold).
- `iswindows_deadarm_prune_xmod`: emission contract both targets
  (`windep`/`linuxdep` opposite sets as above); golden PASS byte-identical;
  mingw clean; wine `iswindows prune ok` rc 0.
- `iswindows_deadarm_cond_if_xmod`: linux build+run `cond if ok` rc 0 (3x
  deterministic); `-osw` mingw build clean + wine `cond if ok` rc 0 (value
  pins `x==2`/`q==42` are target-neutral).

### Fixture goldens (flip-time captures)
```
bash scripts/stdlib/run_fixtures.sh --capture /tmp/d1d2_t3/zig1_5_clean <3 D2/sema fixtures>
→ CAPTURED cond_if (11 B, rc 0), errunion (21 B, rc 0), prune (19 B, rc 0)
  3 PASS / 0 FAIL
bash scripts/stdlib/run_fixtures.sh … <same 3>   # non-capture re-check
→ 3 PASS / 0 FAIL
```
`prune` goldens byte-identical to the T0 capture (git diff empty — the pre-fix
golden stands). `errunion` gained `expected.txt`=`iswindows deadarm ok\n` +
`expected.rc`=0 (its documented GREEN contract). `cond_if` `expected.rc`
flipped `2`→`0` at capture (T2 coerce precedent);
`expected_error.txt`=`20 3` remains the committed RED record.

---

## Concerns

- **C1 (STOP-present on the context's fix-shape — Ruling T3-A, cost if wrong
  above):** the task-3-context's "real leak" (all-fn scan +
  `pruneTypeMarkByValue`) is falsified by the probe matrix; the operative pin
  is the runtime-init root seed. The named fix shapes were therefore NOT
  implemented (shape (a) is refuted as unsafe — atomic module emission makes
  the all-fn scan load-bearing for link correctness; both shapes miss the
  pin). The implemented mechanism (reachability-consistent runtime-init edge)
  delivers the unchanged deliverable (wrong-platform module not emitted, both
  targets) with 0/8 pins + frozen-corpus byte-identity as blast-radius proof.
  Operator should confirm the ruling; if the named shapes were meant to be
  implemented ALONGSIDE this, that would add an unsafe scan restriction —
  STOP-present on request.
- **C2 (dead-module init side effects):** a module that is otherwise
  unreachable but whose `__module_init` writes live state (cross-module global
  stores / observable calls from the init body) now loses those side effects
  (the module is dropped whole). No corpus/example shape found (battery
  clean). Recovery shape if one appears: seed fn-reachability from init bodies
  with cross-module stores/calls.
- **C3 (moving fixed point):** hop1≠hop2 on this change (the fold alters the
  compiler's self-compile C); the stable fixed point is hop2==hop3
  `362fcfb2…`. Precedent: FX14-F. Battery ran on hop1 (`zig1_5_clean` per the
  context's command); hop1/hop2 user-output byte-identity verified on the
  prune fixture.
- **C4 (trigger-set breadth):** the gate fires on anything the shared fold
  machinery folds to KIND_BOOL (spec's "the existing evaluator already folds"
  reading) plus literals and comptime `const` bools — this includes constant
  compound folds (`if (false and x)`-with-else, `if (1 < 2)`). Frozen-1124
  byte-identity + `if_noelse_reject_xmod` stability show no corpus dependence;
  if the operator wants the STRICT three-shape reading (only
  `@isWindows()`/literals/consts, no constant expressions), narrowing is a
  two-line change in `semanticAnalyzerIfComptimeCondition` + the sweep domain.
- **C5 (no-`else` if statements not gated):** `if (false) stmt;` (no else)
  still analyzes + lowers the dead arm (the §3 rule is stated for `if`/`else`;
  gating no-else would drop `if_noelse_reject_xmod` error[3059] rows and move
  the frozen corpus). Zig is stricter here; recorded as a known boundary.
- **C6 (nocomptime_eval.zig edit):** the touch set named it; the existing
  evaluator/table APIs carried the trigger set, so the file is untouched
  (minimal-change rule: "if your probe shows the lowering fold missing a
  trigger-set shape … otherwise do not touch" applies by analogy — the gap was
  in main.zig's sweep domain and sema's gate, not the evaluator).
- **C7 (markers telemetry delta):** −1 line/−13 B (item 8) — one eliminated
  dead-arm call marker. Expected class of movement; recorded.
- **C8 (`iswindows_deadarm_cond_if_xmod` `-osw` naming):** the fixture's
  `@isWindows()` sub-shape is target-relative but CLEAN in both arms (the
  error-vanishing pins use target-neutral `false`/const conditions), so the
  fixture is green on both targets post-T3; pre-fix FAIL was target-neutral
  too (sema analyzed the dead arms under both targets).

---

## Investigation round (C5 + hop gate)

Operator rulings on the T3 STOP-present (recorded): **C1 RATIFIED** — the
runtime-init-edge fix stands as landed; no rework. **C4 KEEP WIDER** — the
trigger set stays evaluator-folded `KIND_BOOL` including constant compounds
(`false and run`, `umax < 0`, `1 < 2`, …); this closes concern C4 as
ratified and is load-bearing for Investigation 2's delta explanation below.

Evidence-first round; NO code/fixture changes were made (report bookkeeping
only). Gate compiler for all probes: `/tmp/d1d2_t3/zig1_5_clean` (post-T3).

### Investigation 1 (C5) — else-less `if` gating

**1a. What the Zig rule (the milestone's oracle) actually does.** Zig
langref 0.15.2, "Compile-Time Expressions" (the comptime-parameter `max(bool)`
example, `test_comptime_max_with_bool.zig`):

> "This works because Zig implicitly inlines **if expressions** when the
> condition is known at compile-time, and the compiler guarantees that it
> will **skip analysis of the branch not taken**."

The rule is stated for `if` expressions generally — no `else`-form
qualification — and the guarantee is about the **branch not taken**. For an
else-less `if` there is still exactly one branch not taken when the condition
is comptime-known: `if (comptime_false) <arm>` — the arm is the branch not
taken → **not analyzed** (this is the famous `if (false) { @compileError(…); }`
compiles-anyway pattern); `if (comptime_true) <arm>` — the arm IS the taken
branch → analyzed. Separately, Zig types an else-less `if` as `void` (already
pinned in this repo's fixture header: "Official Zig 0.15.2 types a no-`else`
`if` as `void`, so using it as a value is 'incompatible types: … and void'"),
so a **value use** of an else-less `if` rejects regardless of arm elimination.
Spec §3's rule text says "`if`/`else`", but its own parenthetical — "(Zig
semantics: the untaken branch is eliminated before analysis)" — points at the
quoted guarantee, which covers the else-less form. **The Zig rule therefore
DOES include the else-less statement form** (and else-less value forms for
the purpose of arm-internal diagnostics).

**1b. What z98 does today (measured, gate compiler).**
`/tmp/d1d2_t3work/inv_c5/stmt_dead.zig` — statement form:

```zig
pub fn main() void {
    var x: i32 = 0;
    if (false) {
        x = dead_arm_undeclared_ident;
    }
    _ = x;
}
```
→ dump rc 2, 0 `.c`, `error[20]` (identifier not declared) + `warning[3000]`
— the dead arm is **analyzed** and its errors fire. Zig would report nothing
(branch not taken). This is the C5 divergence, directly demonstrated.
(Asymmetry note: lowering's `if_fold` ALREADY eliminates the else-less dead
arm — the same shape emits no dead-arm C — so the gap is diagnostics-only,
sema-side.)

`/tmp/d1d2_t3work/inv_c5/value_false.zig` — value form, three sites
(`var x: i32 = if (false) 1;` / `take(if (false) 2);` / `_ = if (false) 3;`)
→ exactly 3 × `error[3059]` ("if expression without 'else' cannot be used as
a value (its type is 'void')"), no `error[3000]` cascade (the if is typed
`then_type` after the 3059, so the enclosing init coerces silently). This
matches Zig's value-use rejection (void-typed if).

**1c. `if_noelse_reject_xmod` — what it pins and per-row consequences.**
Measured census (gate compiler): rc 2, 0 `.c`, **exactly 10 ×
`error[3059]`**, no `error[3000]`/`error[20]`; no `expected_error.txt`
(contract lives in the header: "rc=2, 0 emitted `.c`, `error[3059]` per
value-`if` site"). All 10 rows, with the gate relevance of each condition:

| row (main.zig) | shape | condition folds? | dead arm analyzed today? | would arm-walk skip change the row? |
|---|---|---|---|---|
| :22 `pick` | `if (a == 1) 1` | no (runtime) | n/a (runtime) | no |
| :26 `capPick` | `if (o) \|v\| v` | no (capture; gate refuses) | yes | no |
| :33 `andFalse` | `if (false and run) 1` | **yes** (C4 wider set → `false`) | yes (arm = literal `1`, clean) | **variant-dependent** (below) |
| :43 `u64Lt0` | `if (umax < 0) 3` | **yes** (C4 wider set → `false`) | yes (arm = literal `3`, clean) | **variant-dependent** (below) |
| :50 `rhsAndFalse` | `if (run and false) 1` | no (runtime lhs declines) | yes | no |
| :55 `rhsAndTrue` | `if (run and true) 1` | no (runtime lhs) | yes | no |
| :60 `rhsOrFalse` | `if (false or run) 1` | no (runtime lhs) | yes | no |
| :66/:67/:68 `main` | `if (a == 1) …` ×3 | no (runtime) | n/a | no |

Only rows :33 and :43 have comptime-known conditions; their dead arms are
**clean literals** (T0's adjudication point). Consequences by implementation
variant:

- **Variant A — transplant the landed with-else gate (untaken arm stamped
  `TYPE_NORETURN`):** the error[3059] check (`then_type != TYPE_NORETURN and
  …`) **skips** → rows :33 and :43 lose their 3059 (10 → 8 rows). Worse, the
  if then types `NORETURN` so `var x: i32 = <noreturn>` — either the program
  is **silently ACCEPTED** (Zig rejects it: else-less if is `void`) — a
  semantic regression — or the init cascades an `error[3000]`, which per the
  classifier (`0 .c + error[3000] → GREEN`) flips the fixture
  **FAIL → GREEN = frozen-corpus class MOVER** (forbidden gate). The header
  contract ("3059 per value-`if` site", 10 sites) is violated either way.
- **Variant B — Zig-faithful:** skip the arm WALK for comptime-known-false
  else-less arms only; keep the value-use rejection (3059) **unconditional**
  for else-less ifs whose condition is not comptime-true (its type is `void`
  — Zig rejects the use regardless of arm elimination). Rows before/after:
  **10 × error[3059] → 10 × error[3059]**, same sites, class **FAIL → FAIL**
  (no frozen mover expected). The statement-form probe `stmt_dead` flips
  FAIL → OK (dead-arm `error[20]` vanishes — Zig-correct) and would need a
  NEW fixture pin. The fixture's header contract holds.

**1d. T0's scan coverage.** `if_noelse_reject_xmod` **is** in T0's scanned
adjudication set (the 6-dir table, task-0-report §1.4): "the dead then-arms
hold clean literals → class stays FAIL (3059 gate fires on the value use
regardless of arm elimination)". That class-level verdict is correct for
Variant B and (only if no 3000 cascade appears) for Variant A — T0's
adjudication did not distinguish the two stamping designs. Scan-coverage
gap to record: T0's `PAT` does not match constant-**comparison** conditions
(`umax < 0`-class); a reject fixture whose only comptime-dead arm sits behind
such a fold AND carries the fixture's only error would have been missed by the
pattern sweep. The frozen-1124 byte-identity gate is the backstop any
implementation must re-run.

**1e. Verdict.** The Zig rule (the milestone's oracle) **mandates** the
untaken-arm elimination for the else-less form too (1a), so option (ii) is
mandated — and this round's rules say: STOP-present, do not implement. Binding
STOP-present:

> **I found the intention is** gating else-less `if` arms exactly like the
> landed with-else gate (untaken arm not analyzed, the `if` taking the live
> arm's value/type), **but this is impossible given** the landed gate's
> `TYPE_NORETURN`-stamp pattern: the error[3059] value-use rule keys on the
> analyzed then-type, so the transplant silently ACCEPTS Zig-rejected value
> uses (`var x: i32 = if (false) 1;`) and drops 2 of 10 pinned 3059 rows
> (`if_noelse_reject_xmod` :33 `andFalse`, :43 `u64Lt0`; class FAIL → FAIL
> only if no `error[3000]` cascade appears — unproven, and a cascade is a
> frozen FAIL→GREEN mover). A Zig-faithful Variant B (skip the arm walk for
> comptime-known-false else-less arms; keep the 3059 value-use rejection
> unconditional) keeps the fixture at 10 × 3059 / class FAIL and flips only
> dead-arm-internal diagnostics (`stmt_dead`-shape `error[20]` vanishes,
> Zig-correct — needs a NEW fixture pin), but it is a different design than
> the landed gate and is a behavior change. Operator must rule: (i) leave
> as-is (cost: z98 keeps wrong-rejecting dead-arm diagnostics in else-less
> `if (false)`/comptime-false statement arms — `stmt_dead` probe; emitted C
> is already correct because lowering folds; divergence from Zig recorded
> here), or (ii) implement Variant B (or another ruled shape) as a follow-up
> task with the fixture pin + frozen-gate re-run.

### Investigation 2 (hop gate) — hop1 ≠ hop2

**2a. What the script actually checks (`scripts/seed/build_from_seed.sh`).**
`build_hop compiler dumpdir binout` runs
`compiler -ffast --dump-c89 --output-dir dumpdir sf/src/main.zig` (repo root,
relative path — module-hash tokens depend on the resolved path) then gcc -c +
link → `binout`. Chain: **hop1** = gcc(seed compiler's C-dump of CURRENT
`sf/src`) → `zig1_5_clean`; **hop2** = gcc(hop1's C-dump of the same sources)
→ `hop2/zig1_hop2`; **hop3** = gcc(hop2's C-dump) → `hop3/zig1_hop3`. The gate
compares **binary md5s** (not C dumps): `hop1 == hop2` prints "two-hop closure
OK"; on mismatch the script takes its own documented path — *"Moving point:
the committed seed's dump predates the current sf/src, so hop1 differs;
convergence is hop2 == hop3"* — and requires `hop2 == hop3` ("three-hop
closure OK (moving point)"), exiting 0; it **dies** only if hop2 ≠ hop3. The
recorded fixed-point identity is `CLOSURE_MD5="$HOP2_MD5"` (an optional
`FIXED_POINT_MD5` gate compares against hop2's md5), i.e. the script's
canonical fixed point IS the self-hosted binary, and `hop1 == hop2` is the
fast path that additionally asserts the seed-era dump already agrees.

**2b. Why T3 diverges (measured delta shape).** hop1 ≠ hop2 (binary md5s
`6de5b2e1…` vs `362fcfb2…`) iff the seed compiler's C-dump of `sf/src` differs
from hop1's dump of the same sources (gcc is deterministic on the same C).
Dump evidence from the T3 build dirs:

- module sets: `gen` (seed dump), `hop2/` (hop1 dump), `hop3/` (hop2 dump)
  each contain the same 49 `.c` files — the T3 closure fix pruned **nothing**
  from the compiler's self-emission (all `sf/src` modules are reachable);
- `hop2/` vs `hop3/`: **0 differing files** (byte-identical dumps; totals
  9 467 080 B both) — the landed compiler's self-dump is stable;
- `gen/` vs `hop2/`: **exactly one file differs** — `pal_388A8A1B.c`
  (1200 lines / 29 651 B → 1050 lines / 25 368 B; −4 283 B). The diff shape is
  T3's dead-arm elimination on the compiler's OWN sources:
  `sf/src/pal.zig:211` `pub const g_markers_debug: u32 = 0;` and
  `markerWrite`/`markerWriteInt`'s `if (g_markers_debug != @intCast(u32, 0)) { … }`
  gates — **comptime-const conditions inside the C4-ratified wider trigger
  set**. The pre-T3 seed compiler lowered both arms of those ifs
  (`if ((unsigned char)(0)) goto z_bb_…` + the full marker-flood bodies); the
  T3 compiler eliminates the dead arms. That is the whole delta.

So the divergence is **exactly the expected one-extra-hop convergence of
self-hosting after an emission-changing milestone** (seed-compiler-era dump vs
new-compiler dump of the same sources), not a self-emission instability:
hop2 == compile(dump(hop2)) holds bit-for-bit (hop2 == hop3 binaries and
byte-identical dumps). Prior tasks' `hop1 == hop2` held because their emission
changes were no-ops on `sf/src`'s own shapes (T2's own battery note: "every
pull is a `seen` no-op"; T0 fixtures-only; T1 registry-identity — all
recorded `hop1 == hop2` at `f18b69ec…` / `69cf0269…` / `6e6d1262…`). T3 is the
first emission-changing milestone to move the compiler's own C, and the
script's moving-point path (explicitly commented for this case) is the
authoritative gate. The plan battery letter "seed two-hop hop1==hop2" is the
two-hop spelling of "the built compiler is a self-compile fixed point";
`hop2 == hop3` is that property. (The context's battery line anticipated the
fixed point moving and recorded old→new — done: `6e6d1262…` → `362fcfb2…` —
but assumed hop1==hop2; the assumption held for T0–T2 only.)

**2c. Verdict: (a)** — the gate is satisfied under the script's real
semantics (hop2 == hop3, the script's own `three-hop closure OK (moving
point)` pass; the fixed-point identity it would gate with `FIXED_POINT_MD5` is
hop2's `362fcfb25d88068388755fc1e0ce6c2d`). Not (b): the delta is not an
instability (2b: byte-identical hop2/hop3 dumps). Not (c): T0/T1/T2 all
recorded `two-hop closure OK: hop1 == hop2`; T3's build is the first to
diverge, and the cause is the T3 emission change (pal.zig marker-gate dead
arms). One residual note for the operator: if the plan letter `hop1==hop2` is
meant as a HARD two-hop gate regardless of the script's moving-point path,
then every emission-changing milestone is red by construction until the seed
is rotated at closeout (the seed's own dump era predates the milestone) — the
closeout seed rotation is exactly what re-establishes hop1==hop2 on the next
build.

---

## Fix round (C5 Variant B)

Operator ruling: implement **Variant B** (the Zig-faithful else-less gating
specified in the investigation round). Variant A (`TYPE_NORETURN`-stamp
transplant) forbidden. Implemented + full battery re-run; frozen 1124
byte-identical (0 movers).

### Mechanism (`sf/src/semantic_analyzer.zig`)

- **`if_stmt` walker:** the T3 gate now covers ELSE-LESS statements too. A
  comptime-known-FALSE else-less `if` pushes **no arm** (the then arm is the
  branch not taken — not walked, Zig langref "skip analysis of the branch not
  taken"); a comptime-known-TRUE one walks the then arm (taken branch);
  unknown/capture conditions unchanged (capture conditions never gate).
- **`semanticAnalyzerResolveIfExpr` (value form, else-less):** when the gate
  returns false (comptime-known-FALSE), the then arm is **not resolved** and
  `error[3059]` fires **unconditionally** (same message/ErrorCode/span and
  `diagnosticCollectorMarkNodeOnce` guard as the existing check) — an
  else-less `if` with no taken arm is `void`-typed, so every value use is
  rejected regardless of what the skipped arm would have typed (Zig rejects
  it too). The `if` result is `TYPE_UNDEFINED`, the codebase's error sentinel:
  every downstream check guards it out, so no cascading diagnostics.
  Comptime-known-TRUE else-less keeps the pre-T3 walk + ruling-3 acceptance.
  Analyzed cases (runtime/unknown/capture conditions) keep the existing
  then-type-gated 3059 check **byte-exact** (maximal behavior preservation;
  the unconditional rule is scoped to the skipped subset).
- **Pipeline safety anchor:** `main.zig` exits(2) after
  `phase_SemanticAnalysis` when any error is present — a program whose only
  fault is a skipped-arm 3059 never reaches lowering, so the pre-existing
  void-typed-if-at-value-site lowering ICE (measured: `error[3043]` on
  `var x: i32 = if (false) v();` when NO 3059 fires) cannot bucket the class
  as ICE for these shapes. The 3059 rows therefore cannot be displaced by
  lowering noise.
- **Variant A guard:** no `TYPE_NORETURN` stamp is used on the else-less
  skipped path (it would make the existing then-type-gated check skip and
  drop rows `:33 andFalse`/`:43 u64Lt0` — the forbidden flip).

### Fixture pin (NEW, designed addition)

`repro/mi_matrix/comptime_if_noelse_deadarm_xmod` — else-less statement forms
whose dead arms carry `error[20]`-class diagnostics (literal `false`,
comptime `const` false, constant-fold `1 > 2`, clean `@isWindows()`), live
pins (`if (true)` taken arm analyzed; runtime `if` untouched; `x == 11` gate
prints the golden). Value forms excluded on purpose (they are always 3059 —
`if_noelse_reject_xmod` pins that census).

| | pre-C5 (pin compiler `/tmp/d1d2_t3/zig1_5_clean`) | post-C5 (`/tmp/d1d2_c5b/zig1_5_clean`) |
|---|---|---|
| dump | rc 2, 0 `.c`, `error[20]`×3 + `warning[3000]`×3 → class **FAIL** | rc 0, 5 `.c`, 0 diagnostics |
| run | unreachable | `comptime if noelse ok\n` rc 0, 3× deterministic |
| class | FAIL | **OK** (designed FAIL→OK flip) |

Golden captured at flip: `expected.txt`=`comptime if noelse ok\n`,
`expected.rc`=0 (`run_fixtures.sh --capture` → 1 PASS). The 3×3059
preservation probes re-measured post-C5:
`if_noelse_reject_xmod` → **exactly 10 × error[3059]** (rc 2, 0 `.c`, class
FAIL — the required "10/10 rows unchanged"); `value_false` probe
(`var x: i32 = if (false) 1;` etc.) → 3 × 3059 unchanged; `stmt_dead` probe
(`if (false) { dead_ident; }`) → **rc 0, 0 stderr bytes** (was rc 2 +
`error[20]` — the pinned Zig silence).

### Runtime battery (gate compiler `/tmp/d1d2_c5b/zig1_5_clean`; sequential)

| # | item | command | observed | verdict |
|---|---|---|---|---|
| 1 | seed two-hop | `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_c5b` | hop1 `476482dc…`; hop2 == hop3 == **`67abd038909ae211c839e493e895ba72`**; `three-hop closure OK (moving point)` | MATCH (script semantics). Fixed point old→new: `362fcfb2…` → `67abd038…` |
| 2 | corpus classify | `bash scripts/corpus/classify /tmp/d1d2_c5b/zig1_5_clean …corpus_c5b.txt` | 1132 dirs; frozen-1124 subset md5 `518eca1a9b5d3e1cc5a48abce214abd8`, diff vs T0 anchor **EMPTY**; tally 957 OK / 58 GREEN / 117 FAIL / 0 ICE / 0 CRASH | **Frozen 1124 byte-identical, 0 movers.** Designed lines: `comptime_if_noelse_deadarm_xmod OK` (new flip), errunion/cond_if/prune/coerce/emit OK, cond_import_if FAIL / cond_import_switch OK (T4's, unchanged) |
| 3 | goldens 5/5 | dump+gcc+run (QUICK_REF recipe) | gol `fcbf7e7c…`, lisp `b3d9f897…`, json `8bda3d5a…`, mud `66c8f0ab…`/`93147d0f…` | **5/5 MATCH** |
| 4 | mi frozen-25 + oob | `run_fixtures.sh` <25 names> + `-fsafe` oob recipe | 25 PASS / 0 FAIL; oob rc 133, stdout `d41d8cd9…` | **MATCH** |
| 5 | examples | `-ffast -o` + `build_target.sh linux`; run CWD=example-dir | 26/26 build OK; 26/26 runs — every md5 matches the T0 table (mud rc 124 `9545fe1d…`, z9play/z9torr rc 1, …) | **MATCH** |
| 6 | stdlib | `bash scripts/stdlib/verify_stdlib.sh …` | 285 PASS / 0 FAIL; `STDLIB GATE OK` | **285/0 MATCH** |
| 7 | 8 pins | `<zig1> <mode> --dump-c89 <ENTRY> \| md5sum` | mud `bbc02913…`/`fa346108…`, gol `93c5e3fd…`/`01a4e226…`, lisp `6da05d07…`/`e3970e33…`, json `af3823fa…`/`24e0e812…` | **0/8 delta** (unchanged vs QUICK_REF table) |
| 8 | markers | `--markers --dump-c89 gol` → `wc -lc` | 3436 lines / 38371 B | unchanged vs T3 round (T0: 3437/38384) |

D2 fixtures re-verified green through the classify gate (errunion/cond_if/prune
OK lines). Hop note: hop1 ≠ hop2 again on the same moving-point path as the
Investigation-2 finding (C5 changes what the compiler analyzes in its own
sources — skipped arms drop their hoisted temps from the self-dump); the
hopped dumps' stability claim from Investigation 2 stands (hop2==hop3 here
too).

### Commits

(a) `fix(semantic_analyzer): D2 — else-less comptime-dead arm skip (Variant B)`
— `sf/src/semantic_analyzer.zig` + `docs/sf/Design_p2.md` (§7 note) + the new
fixture + its captured golden (the T2 convention: flip-time goldens ride with
the fix commit).
(b) `docs(sdd): T3 C5 Variant B` — this report.
