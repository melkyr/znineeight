# Phase 1 M2 Task 1C-F report — `const`-global rodata (the fix)

Status: COMPLETE — compiler fix landed; full battery green (one known
pre-existing stdlib failure class, Task 2 `std_cipher` not delivered — out of
scope); seed rotated **v112**, new fixed point `F_new`.

- Branch `zig1_improvements`; base HEAD `efce3dc7`.
- `F_new` = `45158dcede81125a39a2c2c58478e21e` (`hop2==hop3` moving point;
  `hop1≠hop2` expected for a compiler change).
- Plan authority: `task-1c-f-plan.md` + operator rulings in
  `task-1c-f-brief.md`; design `task-1c-i-report.md` §3.

## 1. Design deltas vs I-report (binding; D1–D7)

- **Fold-scope OPTION A:** use-site fold extended to all scalar trees. Order
  of the kind test at `lower.zig` (ident arm) and `lowerModuleMemberValue`:
  (1) `int/float/char_literal` — today's exact path, byte-identical (S1);
  (2) `bool_literal` → `bool_const` (new); (3) tree root scalar
  (int/char/bool/float) → `emitIntConstFacts` with the decl's resolved-type
  width/signedness (negatives exact two's-complement; >64-bit never reaches a
  tree); (4) else `load_global`. Aggregates keep `load_global`. S3 (`3+4`,
  `@intCast`, `-10`) and S18 refs fold at use — no `load_global`. Markers
  telemetry re-baselined (§5.7).
- **D1 tagged-union payloads:** the emitted payload union leads with
  `char _dummy` (`emitTaggedUnionType`), so a payload member is never the C89
  first-member static-initializer target. Rule: tagged-union const with
  all-void payload → `agg` (`{ tag, { 0 } }`); **any non-void payload →
  `null`** (STOP-1 family `.bss` fallback, correct values). Zero tree
  occurrences (S15/S16 probe-only; `t1ci_edge4` is tag-only). Untagged-union
  first-non-void-member rule unchanged (`{ v }`, probe-proven).
- **D2 float folds:** `comptimeEvalEvaluate` has no `float_literal` leaf and
  its binops are int-only (`comptime_eval.zig:839+`). `float_literal` →
  `float_val` (evaluator reads `store.float_values`); float arith /
  negate-of-float → `null` (today's `.bss` path, correct values).
- **D3 fold is value-context only:** `lowerLValueAddr`'s non-local ident arm
  routes `SymbolKind.global` through `lowerGlobalRef` (never the fold), so
  `&const_scalar` renders `&zG_name` (with the qualifier-discard cast), not
  `&temp`. Fixes the pre-existing S1 `&K` wrong-address path as a side effect.
- **D4 `phase_ConstInit` pre-pass** (`main.zig`, runs after
  `phase_AsyncFrameSize`, before `phase_LIRLowering`): classifies ALL
  modules' file-scope consts into the shared `decl→root` map before any
  `lowerFn` runs (fn-before-const source order + cross-module
  `lowerModuleMemberValue` lookups need the full map). The storage walk,
  module-init skip, use-site fold and emitter all consult this one result —
  one evaluator, no second kind test.
- **D5 int init text:** `(CTYPE)(…)` wrapper around the
  `writeIntConstRvalue` literal style (probe `t1ci_c89b` forms). Qualifier
  goes BEFORE the declarator name (`T const n`, not `const T n`) so raw
  pointer spellings get pointer-constness (probe S11 `unsigned char* const`).
- **D6 `fn_addr`:** cast form `(T)zF_fn` gcc `-std=c89 -pedantic -Wall
  -Wextra` clean (probe `/tmp/t1cf_fn.c`) — kept in.
- **D7 wide ints:** magnitude > 64 bits → `null` (no Z98 C type holds them;
  symmetric with the use-site ">64-bit ⇒ no fold" rule). Un-typed literal
  carriers (`integer_literal_type` spells `int`, size 0) are normalized to
  `u32`/`u64`/`i64` at record time (mirror of the use-site carrier rule).

## 2. Implementation (files)

- **new `sf/src/const_init_eval.zig`** — flat `ConstInitNode` pool
  (kinds zero/int/float/bool/char/string/global/fn/agg) + child-index side
  array; `constInitEvaluate` memoized on `decl_idx` (`CIE_NONE` = classified
  non-constant; `in_progress` cycle marker ⇒ `null`); type-directed
  classifier (optional/EU via typedef shapes, struct re-order to C-visible
  field order, tuple positional, array full-length zero-fill, STOP-1 union
  boundary, S12 `[N]u8 = "…"`). Depth-capped recursion (cap 256; a cap-out
  is always the safe `.bss` fallback). `null` always means "today's path,
  today's values".
- **`sf/src/lir.zig`** — `ModuleGlobalDecl` += `const_init: u32`
  (0xFFFFFFFF = none), `link_visible: u8` (flags bit1|bit3).
- **`sf/src/main.zig`** — `CompilerContext.const_inits` (emission arena —
  the trees outlive the lowering→emission `sandReset` of the module arena);
  `phase_ConstInit`; storage walk consults the map (constant-tree rows
  recorded with `has_runtime_init=0`; import/field-of-import un-sets first;
  no-tree rows keep today's `.bss` path verbatim); emitter handoff.
- **`sf/src/lower.zig`** — `SemanticContext.const_inits`; module-init skip =
  tree presence OR today's literal kind test (kept, covers null-tree
  literals); use-site fold rules 1–4 (ident arm + `lowerModuleMemberValue`);
  `foldConstTreeScalar` helper; D3 `lowerLValueAddr` change.
- **`sf/src/c89_emit.zig`** — `C89Emitter.const_inits`;
  `emitGlobalExternDecls` const branch (body `static T const n = <init>;` /
  `T const n = <init>;`; header `extern T const n;` visible-only, private
  skipped); new `emitConstInitValue` (+ typed int/float literal writers,
  global/fn name mangling, per-shape rendering from I §3.3); qualifier-discard
  casts at `addr_of` and `make_slice` `.ptr` (and the `global_addr` init
  form). `moduleHasRuntimeInit`/`emitModuleInitCalls` unchanged (const-only
  modules lose `__module_init` by design).

## 3. Fixtures + gate (committed, non-vacuous)

- `repro/mi_matrix/stdlib_const_rodata_xmod/{main.zig,expected.txt,expected.rc}`
  — S3/S2/S1/S4 (256-entry table)/S5/S6/S7/S8/S9/S10/S11/S12/S18-chain/S19 +
  **STOP-1 negative** (non-first-member union const `ub`, value asserted).
  stdout `7 12 8 1786 4 5 22`, rc 0. Pinned in
  `scripts/stdlib/expected_dirs.txt` (C-locale sorted).
- `repro/mi_matrix/const_rodata_gate/{value_shapes.zig,runtime_shapes.zig}` —
  nm probes: value-only → `R/r`; address-bearing → `D/d` (never `B/b`);
  non-constant/`undefined`/STOP-1 union/`var` → `B`.
- `repro/mi_matrix/const_rodata_xmod_xmod/{main.zig,leaf.zig,expected.txt,expected.rc}`
  — cross-module pub table + `&pub const` array (`extern const` + addr_of
  cast). stdout `79`, rc 0.
- `scripts/compiler/gate_const_rodata.sh` (new) — gcc `-std=c89 -c` + `nm -S`
  class assertions, `__module_init` store greps (S19/rs symbols ARE stored,
  value shapes never), header text (`extern … const` for pub, absent for
  private; private def `static … const`), value fixture run.

### Gate run

```
bash scripts/compiler/gate_const_rodata.sh /tmp/t1cf_b/zig1_5_clean
→ [gate_const_rodata] ok _vs_scalar class 'r' (R/r)   (… 11 value shapes R/r)
  [gate_const_rodata] ok _vs_slice class 'd' (ro/reloc)  (_vs_many/_vs_parr too)
  [gate_const_rodata] ok _rs_nonconst class 'B' (bss)  (… rs_undef/rs_union/rs_var/rs_seed)
  [gate_const_rodata] ok S19 rs_nonconst IS stored in __module_init
  [gate_const_rodata] ok STOP-1 rs_union IS stored (fallback values)
  [gate_const_rodata] ok no value-shape const is stored
  [gate_const_rodata] ok private consts absent from headers
  [gate_const_rodata] ok private const definition is 'static ... const'
  [gate_const_rodata] ok pub const header row is 'extern ... const'
  PASS repro/mi_matrix/stdlib_const_rodata_xmod
  CONST_RODATA GATE OK
```

### Non-vacuity mutations (applied, recorded, reverted)

1. Emitter const branch stubbed (`if (g.const_init != 0xFFFFFFFF and false)`),
   rebuilt, gate run:
   `FAIL: _vs_scalar class 'B' want R/r` … (all 11 value shapes + address
   shapes `B`), `CONST_RODATA GATE FAILED` — gate step 2 FAILS as required.
2. `constInitEvaluate` forced to return a `zero` tree for non-constant decls,
   rebuilt, gate run:
   `FAIL: _rs_nonconst class 'r' want B/b/C`, `FAIL: _rs_undef class 'r'`,
   `FAIL: _rs_union class 'r'`, `CONST_RODATA GATE FAILED` — the `.bss`
   negatives FAIL as required.
   Both mutations reverted; clean rebuild reproduces `hop2==hop3=45158dce…`.

## 4. Full compiler battery (old→new)

Build: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t1cf_b`
→ `hop1 a8943e360c9a89d2a5da904c452ccf42` ≠ `hop2`; `hop2 == hop3 ==
45158dcede81125a39a2c2c58478e21e` ("three-hop closure OK (moving point)").

### 4.1 Corpus frozen-1124 — 0 movers

```
bash scripts/corpus/classify /tmp/t1cf_b/zig1_5_clean /tmp/t1cf_corpus.txt
→ wrote /tmp/t1cf_corpus.txt: 1169 dirs
```

Frozen subset = the 1124 pre-`aa8315ae` universe dirs (current universe minus
the 42 post-freeze additions — 39 mi_matrix + 3 stdlib_test, listed in the
1C-F plan concerns — minus the 3 new 1C-F dirs):

```
grep -vE '<42 post-freeze dirs>|stdlib_const_rodata_xmod|const_rodata_gate|const_rodata_xmod_xmod' /tmp/t1cf_corpus.txt > /tmp/t1cf_corpus_frozen.txt
wc -l → 1124
md5sum → 518eca1a9b5d3e1cc5a48abce214abd8   (== frozen anchor, byte-identical)
tally → 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH
```

**0 movers; no FAIL↔OK flip** (the S12 repair moved nothing — no corpus dir
exercises `[N]u8 = "…"`). New 1C-F dirs classify `OK`×3.

### 4.2 Goldens 5/5 — runtime byte-identical

| golden | observed md5 | expected | match |
|---|---|---|---|
| gol (100 gens) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | same | YES |
| lisp `(+ 1 2)` | `b3d9f8974da24ddbf9d389f3d7d97322` | same | YES |
| json | `8bda3d5a1ec07d14a301bc343df32bf8` | same | YES |
| mud server | `66c8f0abb926cca7baf9a0d1692ab318` | same | YES |
| mud client | `93147d0f0bbd983a9d844fea8b7a6fa7` | same | YES |

### 4.3 mi_matrix frozen-25 + oob — MATCH

```
bash scripts/stdlib/run_fixtures.sh /tmp/t1cf_b/zig1_5_clean <frozen 25 dirs>
→ run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```

oob `slice_index_field_store_oob_xmod` (`-fsafe`): dump rc 0, build rc 0, run
**rc 133** (Trace/breakpoint trap), stdout 0 B md5 `d41d8cd9…` — MATCH.

### 4.4 Examples 26/26 build + 26/26 run — correct

All 26 built (`main.zig`, or `<name>.zig` for
func_ptr_return/mandelbrot/quicksort/sort_strings). Runs (CWD=example dir,
`timeout 25`, mud `timeout 8`, stdin `/dev/null`, rogue* fed `q\n`): every
stdout md5 matches the T0 §3.5 table — days_in_month `8c0d394c…`, fibonacci
`b53b3a3d…`, func_ptr_return `f6a54779…`, gol `fcbf7e7c…`, heapsort
`8cf0a784…`, hello `74630882…`, json `8bda3d5a…`/`8bda3d5a…`/`dc22fa47…`,
lisp* `1c1f0a41…`×4, lzw `c3c7765e…`, mandelbrot `d5966775…`, mud rc 124
`9545fe1d…`, prime `d095a94d…`, quicksort `45d2f0fb…`, rogue* `3fb6709e…`×2,
sort_strings `c6c047cb…`, tco `264ea6b1…`/`3d70c50b…`/`7421137a…`, z9play
rc 1 `f35b7ef7d832cc4a…` (usage banner, T0-C1), z9torr rc 1 `f666af15…`.

### 4.5 Stdlib — 316 PASS / 2 FAIL (2 = known pre-existing, out of scope)

```
bash scripts/stdlib/verify_stdlib.sh /tmp/t1cf_b/zig1_5_clean
→ run_fixtures: 316 PASS / 2 FAIL over 318 dirs
  failed: repro/mi_matrix/stdlib_aes_gcm_xmod repro/mi_matrix/stdlib_chacha_poly_xmod
```

315→316 PASS with the new pinned fixture (§3) as expected. The 2 failures are
**pre-existing and identical on the v111 seed compiler**
(`error[3048]: could not resolve imported file 'std_cipher.zig'` on both):
they are M2 Task-2 fixtures (`stdlib_aes_gcm_xmod`/`stdlib_chacha_poly_xmod`)
that reference the not-yet-delivered `std_cipher` module. Task 2 is BLOCKED
by design; **out of scope for 1C-F** (operator-confirmed known issue). Old
seed baseline for comparison: `312 PASS / 6 FAIL` (its 6 = the same 2 + the
Task-1 trio on the stale lib + the new fixture).

Crosscheck + determinism:

```
bash scripts/stdlib/run_crosscheck.sh /tmp/t1cf_b/zig1_5_clean
→ run_crosscheck: 9 PASS / 0 FAIL over 9 modules
```

(run_fixtures itself runs every fixture 3× and requires byte-identical
stdout — the 3× determinism gate — green for all 316.)

### 4.6 The 8 `--dump-c89` pins — moved 8/8 (recorded old→new)

`zig1 <mode> --dump-c89 <ENTRY> | md5sum` (repo root; compiler =
`/tmp/t1cf_b/zig1_5_clean`):

| entry | `-fsafe` old → new | `-ffast` old → new |
|---|---|---|
| `examples/z98/mud_server/main.zig` | `bbc02913a10af9b0b5ed0f292f4e3407` → `76c05e6e35ec0357dd61e330bd825c99` | `fa346108ed00d03a037c2f9331d3bdf8` → `3611017bb1ae0806288107347395a5e8` |
| `examples/z98/game_of_life/main.zig` | `93c5e3fdc5b80b2f3db020d995abbe3f` → `f83316ad82c40077553cb25fbec7620b` | `01a4e2265b33c97a8ca6ff3dfa551231` → `d1bc475b1e088475e3b527e0c06d13f1` |
| `examples/z98/lisp_interpreter_curr/main.zig` | `6da05d070acd414674b1b1ec947baa5c` → `e51e62ddb5d1c099c3d67f972a7181a8` | `e3970e33ac09c8dfaa316d2d69bf61ec` → `21339525dc1d2aab1b539b19b8375872` |
| `examples/z98/json_parser/main.zig` | `af3823fae0b29fa4d4ca58932538d631` → `b3f05fbea0b8dc5ca34a8ca0b73dbb09` | `24e0e812e7dffa5a43750135405ffe3f` → `cf25f6ecf323bca4ad7789e161be0bf6` |

(Runtime goldens 5/5 stay byte-identical — §4.2.) QUICK_REF table text is
left for Task 4's doc pass (plan §8 scope).

### 4.7 Markers — RE-BASELINED (recorded old→new)

```
/tmp/t1cf_b/zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > /tmp/t1cf_mk.c 2>/tmp/t1cf_mk.bin
```

`3437 lines / 38384 B` → **`3438 lines / 38453 B`** (use-site fold changes
move the marker emission — expected per the fold-scope ruling).

### 4.8 `check_emit_support.sh` — 8/8

```
bash scripts/check_emit_support.sh /tmp/t1cf_b/zig1_5_clean
→ [check] OK: 8/8 support files byte-identical to canonical (6 core + 2 conditional preludes)
```

## 5. Seed rotation v112 + plan re-anchor

```
bash scripts/seed/archive_seed.sh /tmp/t1cf_b/hop2/zig1_hop2 /tmp/t1cf_b/hop2 release/seed/zig1-seed.tgz --update-changelog
→ | self-emission C | 47 .c + 48 .h (10691275 bytes) |
  | fixed point | 45158dcede81125a39a2c2c58478e21e |
  | lib manifest | lib/manifest.md5 (40 std files; md5 88f2f6db2f30f7850a1aa3c3f5f8dce7) |
  | archive md5 | 578993ec772dcf2e715f705da9e451aa |

bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t1cf_verify
→ [seed] hop1 binary md5: 45158dcede81125a39a2c2c58478e21e
  [seed] hop2 binary md5: 45158dcede81125a39a2c2c58478e21e
  [seed] two-hop closure OK: hop1 == hop2 == 45158dcede81125a39a2c2c58478e21e
```

- v112 archive md5 `578993ec772dcf2e715f705da9e451aa`; binary / fixed point
  `F_new` = `45158dcede81125a39a2c2c58478e21e`; `lib/` 40 std files (copy
  list unchanged — `archive_seed.sh` needed no edit); manifest md5
  `88f2f6db2f30f7850a1aa3c3f5f8dce7`. Rebuilt-from-archive closes
  `hop1==hop2==F_new`. Self-emission grew 45c/46h → 47c/48h (L19 accepted:
  ~360 literal consts + string slices gain `static const` defs).
- Plan text `docs/superpowers/plans/2026-10-21-phase1-m2-crypto-core-plan.md`
  re-anchored: `21c95773…` → concrete `F_new`
  `45158dcede81125a39a2c2c58478e21e` (line 21); Task 4 rotate target
  `v112`→`v113` (line 135). Folded into the `fix` commit (plan concern-1
  ruling).

## 6. Concerns

1. **Stdlib crypto fixtures** `stdlib_aes_gcm_xmod`/`stdlib_chacha_poly_xmod`
   FAIL identically pre/post (`std_cipher` not delivered — M2 Task 2 BLOCKED).
   Operator-confirmed out of scope; no action in 1C-F.
2. `test_lower_bin.zig` `SemanticContext` literal is already unbuildable
   (F2 precedent: missing `state_widths`); left untouched, now also missing
   `const_inits`.
3. QUICK_REF seed/pin rows left stale by plan §8 scope (Task 4 owns the
   QUICK_REF edits: counts/install/verify + this table).
4. Corpus exclusion list in `task-1c-f-plan.md` §6.1 ("6 d1d2 + 3 Task-1") is
   a stale undercount — the true post-freeze universe growth is 42 dirs (39
   mi_matrix + 3 stdlib_test; verified 1166−42=1124 exactly). The battery
   used the corrected list; recorded here, plan text not edited.
5. The battery compiler is the hop1 build of the final source
   (`/tmp/t1cf_b/zig1_5_clean`, md5 `a8943e36…`); the fixed point
   `45158dce…` is `hop2==hop3` of the same source and is the archived seed
   binary. Emission behavior is source-determined; both closures converged.
