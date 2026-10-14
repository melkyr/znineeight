# Combined fix report — P6-pre fix round 3 + P12 fix round 1 (H1/H2/H3, ONE battery)

**Status:** DONE_WITH_CONCERNS (H1+H2+H3 landed; battery 8/8 green; concerns are deferred-minor class only). Authority: plan Amendment (2026-10-14) + this dispatch brief. Tree anchor: `eaf03fa4` (`docs: emitter sanitization amendment 3 …`). Touch set honored: `sf/src/{lir_opt_pass,async_state_machine,c89_emit,c89_plan,type_registry}.zig` + `sf/docs/tech_docs/` + this report; `progress.md` NOT edited (controller-owned ledger lines staged per commit spec). Edits via `edit` only (read-before-edit; bottom-to-top per file); no bulk transforms; no subagents; no push.

---

## H1 — `width_bits`/`is_signed` populated at EVERY `.int_const` construction site

**Facts rule (uniform, matches `lower.zig` `emitIntConst`):** facts = the const's result temp type's semantic width/signedness via the P5 predicates `type_mod.typeRegistryIntWidthBits` / `typeRegistryIntIsSigned` (sign encoded 1/0 as `u8`; non-int kinds / out-of-range tids give (0,0) — the deterministic historical value-rule class). Two tiny pure helpers per file wrap the rule (`intFactWidthBits` / `intFactIsSigned`; the bool→u8 conversion uses the proven `emitIntConst` spelling `@intCast(u8, if (…) @intCast(u8, 1) else @intCast(u8, 0))`).

**Stray census:** `grep -rn "\.int_const = " sf/src/ --include="*.zig"` over the whole tree — construction sites found = the brief's known list EXACTLY (23 async + 3 fold); **0 strays**. Copier sites (non-edit per brief) unchanged: `async_state_machine.zig` `remapInst` (4-field copy, fix round 2), `lir_opt_pass.zig:1476` `retargetDefResult` (whole-payload `var ni = ic`), `else => return inst` passthroughs, `lir_stream`/`spill_store` byte copies.

**Census table (every construction site + facts source + edit):**

| # | site (pre-edit line) | file | temp / type | facts source | edit |
|---|---|---|---|---|---|
| 1 | `:2021` `.binary` fold | lir_opt_pass.zig | `b.result` | `tempDeclTypeId(c, b.result)` → predicates (`c.reg`) | 4-field literal |
| 2 | `:2034` `.unary` fold | lir_opt_pass.zig | `u.result` | `tempDeclTypeId(c, u.result)` → predicates | 4-field literal |
| 3 | `:2042` `.int_cast` fold | lir_opt_pass.zig | `ic.result` (cast target; `tryFoldIntCast` checks `rt == ic.target`) | `tempDeclTypeId(c, ic.result)` → predicates | 4-field literal |
| 4 | `:221` `fieldPtrBase` off | async_state_machine.zig | `newTemp(b, TYPE_USIZE)` | predicates on `TYPE_USIZE` | 4-field literal |
| 5 | `:469` align7 | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 6 | `:473` align_mask | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 7 | `:477` fsz_t | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 8 | `:492` pool_off_t | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 9 | `:525` zero_st | async_state_machine.zig | `c_state_type` (layout-read, default U8) | predicates on `c_state_type` | 4-field literal |
| 10 | `:545` poff | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 11 | `:553` nptr | async_state_machine.zig | `ptrVoid(reg)` (null-ptr const) | predicates → non-int (0,0) | 4-field literal |
| 12 | `:566` sv | async_state_machine.zig | `b.state_type` | predicates on `b.state_type` | 4-field literal |
| 13 | `:583` fsz_t2 | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 14 | `:665` `fiStoreAt` off | async_state_machine.zig | `fiNewTemp(…, TYPE_USIZE)` | predicates on `TYPE_USIZE` (`reg` param) | 4-field literal |
| 15 | `:684` size_t | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 16 | `:686` i_t | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 17 | `:705` byte0 | async_state_machine.zig | `TYPE_U8` | predicates | 4-field literal |
| 18 | `:708` one | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 19 | `:726` zero_st | async_state_machine.zig | `state_type` param | predicates on `state_type` | 4-field literal |
| 20 | `:853` z_usize | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 21 | `:856` cap_t | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| 22 | `:859` z_oom | async_state_machine.zig | `TYPE_U8` | predicates | 4-field literal |
| 23 | `:1125` lim | async_state_machine.zig | `state_type` | predicates on `state_type` | 4-field literal |
| 24 | `:1171` cz | async_state_machine.zig | `ptr_void` (null-ptr const) | predicates → non-int (0,0) | 4-field literal |
| 25 | `:1191` sv | async_state_machine.zig | `state_type` | predicates on `state_type` | 4-field literal |
| 26 | `:1244` zero | async_state_machine.zig | `TYPE_USIZE` | predicates | 4-field literal |
| — | `lower.zig:1639` `emitIntConstFacts` | lower.zig | caller-carried | already 4-field (P6-pre fix round 1) | none (done) |

Bool folds (`bool_const` at `:2017`/`:2031`-class) untouched (different record). `lir.zig:74` record unchanged.

**H1 gate (proof i — zero remaining 2-field constructions):**

```
$ grep -rn "int_const = " sf/src/ --include="*.zig" | grep -v "width_bits"
sf/src/lir_opt_pass.zig:1476:        .int_const => |ic| { var ni = ic; ni.result = newr; return LirInst{ .int_const = ni }; },
```

Single remaining line = the whole-payload retarget COPIER (brief-mandated non-edit; facts ride the copy). Every CONSTRUCTION literal carries all four fields (26/26 rows above + `lower.zig:1639`). The two read gates (`c89_plan` `deriveConstCarrier` fact path; `c89_emit.zig` `d4_fcar` fill) can now only ever see written facts.

## H2 — every `sorted` walker bounded on the sort SNAPSHOT length

**Snapshot length:** `C89SpellPlan` gains `typedef_order_len: usize` (house style: beside `fn_count`/`fn_cap`), set in `spellPlanPlanTypeOrder` to `reg.types_len` at plan time (exactly the count `tstTopologicalSort` covers — the popped/append guarantee makes `typedef_order` a permutation of `0..types_len-1` at snapshot), init `0` in `spellPlanInit`. Comment truth-ups in `c89_plan.zig`: the `tstTopologicalSort` header note ("the follow-up 'bound on snapshot length' is unchanged and NOT taken here" → TAKEN here) and the P2-append note ("walk `sorted[0..types_len]`" → `sorted[0..typedef_order_len]`, the plan-time snapshot).

**Walker census (`grep -n "sorted\[" sf/src/c89_emit.zig` — 4 consumers, all were live-bounded):**

| walker | site | old bound | new bound |
|---|---|---|---|
| `emitTypePasses` Pass 1 (forward typedefs) | `c89_emit.zig:1087` | `tsi < reg.types_len` | `tsi < emitter.plan.typedef_order_len` |
| `emitTypePasses` Sub-pass 2a (pointer-only) | `:1111` | `tsi < reg.types_len` | `tsi < emitter.plan.typedef_order_len` |
| `emitTypePasses` Sub-pass 2b (value-embedding) | `:1124` | `tsi < reg.types_len` | `tsi < emitter.plan.typedef_order_len` |
| `emitModuleHeaderFile` module header walk | `:2144` | `tsi < emitter.registry.types_len` | `tsi < emitter.plan.typedef_order_len` |

Not in scope (NOT `sorted` walkers, untouched per brief): `emitNeededTupleTypes` (`needed_tuple_set` membership over the registry) and the `ts_ref_set` walk. `sorted` itself is passed as `emitter.plan.typedef_order` (unchanged call plumbing).

**H2 proof (ii):**

```
$ grep -n "typedef_order_len\|sorted\[tsi\]" sf/src/c89_emit.zig
1087:    while (tsi < emitter.plan.typedef_order_len) : (tsi += 1) {
1088:        var tid = sorted[tsi];
1111:    while (tsi < emitter.plan.typedef_order_len) : (tsi += 1) {
1112:        var tid = sorted[tsi];
1124:    while (tsi < emitter.plan.typedef_order_len) : (tsi += 1) {
1125:        var tid = sorted[tsi];
2144:    while (tsi < emitter.plan.typedef_order_len) : (tsi += @intCast(usize, 1)) {
2145:        var tid = sorted[tsi];
$ grep -n "typedef_order_len" sf/src/c89_plan.zig
34:    typedef_order_len: usize,
98:    plan.typedef_order_len = @intCast(usize, 0);
263:    plan.typedef_order_len = reg.types_len;
```

**Expected behavior delta: ZERO — proven by the battery** (item 2/7/3 below: corpus class file byte-identical, pins 0/8, goldens 5/5). Multi-file/header-walk evidence (proof iii, the brief's optional probe): the goldens' dumps ARE multi-module header walks (json 9 / mud 9 / lisp 15 / gol 7 emitted CUs incl. std module headers) and their runtime outputs + the 8 dump pins are byte-identical to the frozen anchors — post-snapshot synthetic types (`Slice_`/`Arr_`/`Opt_` class) ride the `:2554`-class skip guards exactly as before; the old over-read landed in the sort's own `queue` buffer (dedup-safe), so bounding changes no output.

## H3 — comment truth-up

`sf/src/type_registry.zig` `typeRefs` header comment (the `:1243` region): the typedef-ordering attribution now reads "**the planner's** typedef ordering (`c89_plan.zig` `spellPlanPlanTypeOrder`/`tstTopologicalSort` — P12 moved the sort into the planner; the emitter walks the carried order), plus the P4 classification's shared-set closure `classificationSharedClosure` in `type_resolver.zig`" (classificationSharedClosure clause kept). Comment only — zero code. Tech-docs twin: `03_type_resolution.md` Defect-D section's "(the same edges the emitter's typedef ordering uses" → planner attribution (same wording).

## Tech-docs duty

`[updated: 2026-10-12 — combined fix …]` truth-ups: `07_lir_lowering.md` (H1 title entry — facts fill complete, helpers, gate), `08_c89_emission.md` (H2 title entry — snapshot bounds; supersedes the P12 entry's "Walk bounds untouched" note), `03_type_resolution.md` (H3 attribution), `INDEX.md` Table A (4 new rows `intFactIsSigned`/`intFactWidthBits` × 2 files; `spellPlanPlanTypeOrder` row notes `typedef_order_len`).

---

## Runtime battery (ONE run after all three fixes; command + observed output per claim)

Build: `FIXED_POINT_MD5=e93ca5eeb647f7465f5cd096b9208ca5 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p6fix3/s1` (repo root).

### 1. Seed two-hop

```
[seed] hop2 binary md5: 1293d62d71dceeb734dee837a7e10e8e
[seed] two-hop closure OK: hop1 == hop2 == 1293d62d71dceeb734dee837a7e10e8e
error: fixed-point mismatch: got '1293d62d71dceeb734dee837a7e10e8e', want 'e93ca5eeb647f7465f5cd096b9208ca5'
```

**hop1==hop2 proven**; fixed point `e93ca5ee…` → **`1293d62d71dceeb734dee837a7e10e8e`** (new, recorded; compiler-moving — gate mismatch expected; **seed NOT rotated** — rotation is Task C).

### 2. Corpus classify (class FILE vs frozen Appendix A)

```
$ bash scripts/corpus/classify /tmp/p6fix3/s1/zig1_5_clean /tmp/p6fix3/corpus.txt
wrote /tmp/p6fix3/corpus.txt: 1124 dirs
$ md5sum /tmp/p6fix3/corpus.txt /tmp/task0_work/corpus_baseline.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/p6fix3/corpus.txt
518eca1a9b5d3e1cc5a48abce214abd8  /tmp/task0_work/corpus_baseline.txt
$ diff … → empty (DIFF EMPTY (byte-identical))
$ awk '{print $2}' … | sort | uniq -c → 116 FAIL / 58 GREEN / 950 OK
```

**1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH — class file byte-identical, 0 movers (no FAIL→OK/OK→FAIL).**

### 3. Goldens 5/5

dump+gcc all rc=0, 0 `error:`, line counts 13924/19277/15596/14789 (record):

| golden | command | observed md5 | frozen | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 ./gol > gol.out` (rc=0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7c…` | YES |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 ./lisp` (rc=0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f897…` | YES |
| json | `cd examples/z98/json_parser && timeout 60 gold/json` (rc=0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a…` | YES |
| mud server | `bash examples/z98/mud_server/demo/session.sh gold/mud srv.out cli.out` (rc=0) | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0ab…` | YES |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f…` | YES |

**5/5 byte-identical.**

### 4. mi_matrix anchor SET (25 + oob)

SET re-enumerated from the progress.md load-bearing definition (non-stdlib ∧ non-empty `expected.txt` ∧ `expected.rc=0`) → **25 dirs, `diff` vs the frozen list EMPTY** (set integrity checked before running). Harness: `bash scripts/stdlib/run_fixtures.sh /tmp/p6fix3/s1/zig1_5_clean <the 25>` → **`run_fixtures: 25 PASS / 0 FAIL over 25 dirs`**. Trap fixture `slice_index_field_store_oob_xmod` (`-fsafe`): dump rc=0, build rc=0, **run rc=133** (Trace/breakpoint trap), stdout 0 bytes, md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt` md5. **MATCH.**

### 5. examples/z98/*/ (26 build + 26 run)

Build (`-ffast -o` + `build_target.sh linux`): **26/26 dump=0 / `.c` counts identical to task-0 §1.4** (7/6/6/7/6/7/9/9/9/14/15/15/15/8/6/9/6/6/21/20/6/6/7/7/25/38) / build=0. Run (CWD=example dir; `timeout 25` except mud 8; stdin `/dev/null` except rogue* `q\n`): **26/26 rc + stdout md5_16 IDENTICAL to the §1.4 table** — days_in_month `8c0d394cbc6e7f36`, fibonacci `b53b3a3d6ab90ce0`, func_ptr_return `f6a5477970a87a1c`, game_of_life `fcbf7e7cead5082f`, heapsort `8cf0a7844206319d`, hello `746308829575e17c`, json×2 `8bda3d5a1ec07d14`, json_parser_workaround `dc22fa473650bd3d`, lisp×4 `1c1f0a417d5e9434`, lzw `c3c7765e6faf7b70`, mandelbrot `d596677501e36537`, mud_server rc=124 `9545fe1d245293ef`, prime `d095a94d20dcaf7a`, quicksort `45d2f0fb6fc40654`, rogue×2 `3fb6709e7bbd8964`, sort_strings `c6c047cbc13cdd4f`, tco_defer `264ea6b106a51dde`, tco_factorial `3d70c50b5a37d549`, tco_return_try `7421137aa2d104b4`, z9play rc=1 `2016494de476fcb6`, z9torr rc=1 `f666af15cf2625b3` (full 26-row match).

### 6. Stdlib gate

```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/p6fix3/s1/zig1_5_clean
run_fixtures: 285 PASS / 0 FAIL over 285 dirs
STDLIB GATE OK
```

### 7. The 8 `--dump-c89` pins (old → new)

| entry | mode | old (P6-pre/P12 record) | new | delta |
|---|---|---|---|---|
| mud_server | `-fsafe` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | `8b3c3d72ab59a9ae3c971c6a7759c7c0` | 0 |
| mud_server | `-ffast` | `fa346108ed00d03a037c2f9331d3bdf8` | `fa346108ed00d03a037c2f9331d3bdf8` | 0 |
| game_of_life | `-fsafe` | `1b5d49b141ee9c664a82c270454bd75b` | `1b5d49b141ee9c664a82c270454bd75b` | 0 |
| game_of_life | `-ffast` | `01a4e2265b33c97a8ca6ff3dfa551231` | `01a4e2265b33c97a8ca6ff3dfa551231` | 0 |
| lisp_interpreter_curr | `-fsafe` | `8e5f2bc288d1dc75d7aee284cb35c291` | `8e5f2bc288d1dc75d7aee284cb35c291` | 0 |
| lisp_interpreter_curr | `-ffast` | `e3970e33ac09c8dfaa316d2d69bf61ec` | `e3970e33ac09c8dfaa316d2d69bf61ec` | 0 |
| json_parser | `-fsafe` | `2a12d0aac24d5bcdd694f05e04a4f029` | `2a12d0aac24d5bcdd694f05e04a4f029` | 0 |
| json_parser | `-ffast` | `24e0e812e7dffa5a43750135405ffe3f` | `24e0e812e7dffa5a43750135405ffe3f` | 0 |

**Pin delta: 0/8** (no emission-rule change; H1 makes previously indeterminate facts deterministic — the gated classes never read them before and read defined values now; H2 bounds change no emitted byte). Process note: one pin poll returned an empty-md5 in the FIRST pass because I ran the pins loop and the `--markers` dump in parallel from the same CWD (the compiler's CWD spill files raced — a harness error, not a compiler defect); re-run sequential + 3x repeat: `2a12d0aac24d5bcdd694f05e04a4f029` stable, and the sequential transcript above is authoritative.

### 8. Markers telemetry

`zig1_5_clean --markers --dump-c89 examples/z98/game_of_life/main.zig > mk_gol.c 2> mk_gol.bin` — dump rc=0; stderr **3,436 lines / 38,378 B** — identical to the P2-P6-pre-P12 record (no new markers; H1/H2/H3 emit none).

---

## Observations (report-only)

- **O1:** H1 makes the fold/async construction facts DETERMINISTIC where they were previously indeterminate C-struct copies — the gates still do not read them (hoisted kinds unchanged), but the poison-the-well class is gone; the gates can now only see written facts (H1 gate, proof i).
- **O2:** the brief's exact async line list matched the file census 23/23 (0 strays); the "24 constructions" figure in the P6-pre-fix plan/round-2 audit counted the `remapInst` copier as a construction (already corrected in fix round 2's audit).
- **O3:** the two null-ptr consts (`nptr`/`cz`) take the non-int (0,0) facts class — deterministic value-rule class, and structurally gate-unreadable (ptr hoisted kinds); consistent with the uniform rule.
- **O4:** H2's `typedef_order_len` is read-only state of the plan; no emitter decision added (Decision-vs-spelling preserved — the sort and its snapshot length are planned at the boundary, the emitter walks).
- **O5:** seed NOT rotated per brief (rotation is Task C).

## Concerns

1. Deferred minors stay deferred (spellPlan linear lookups; `c89_emit.zig:566-568` re-indent churn; the §5.4 Class B disclosed item) — untouched per "No unrelated fixes".
2. `lir_opt_pass.zig` fold-produced consts still land on concrete-hoisted temps (fold gate `intKindWidth ≠ 0`) — unchanged; their facts are now populated, so any future gate relaxation is safe.
3. Harness note (not a compiler concern): parallel zig1 invocations sharing a CWD race on spill files (observed once in battery item 7's first pass; sequential re-run clean).
