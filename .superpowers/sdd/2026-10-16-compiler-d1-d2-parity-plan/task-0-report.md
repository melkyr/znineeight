# Task 0 report — Preflight: battery baseline, fixtures, inventories, dead-arm scan

Plan: `docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md`
Spec (binding): `docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md`
Branch `zig1_improvements`, BASE `2b0cd2cf` (plan+spec). No `sf/src` change in T0.
Gate compiler: seed-built `/tmp/d1d2_build/zig1_5_clean` (md5 `f18b69ece1917bf970a036b276e5e403`).
A prebuilt seed-v98 compiler at `/tmp/z9play_seed_v98/zig1_5_clean` was verified md5-identical
to the gate compiler before use as a cross-check.

---

## 1. Investigate

### 1.1 Inventory (i) — every synthetic-composite GetOrCreate site (`sf/src/type_registry.zig`)

Read of the registry at the fixed point; per-site behavior **as the code is today**:

| site | line | key/cache | layout-dependence | canonical? |
|---|---|---|---|---|
| `typeRegistryGetOrCreatePtr` / `PtrQ` | 739/743 | `ptr_cache`, key `(base<<2)\|qual` | none (size 4, state 2 always) | YES — unconditional `MapPut` (the spec §2 "model" site) |
| `typeRegistryGetOrCreateManyPtr` / `Q` | 761/765 | `many_ptr_cache`, same key shape | none | YES (unconditional) |
| `typeRegistryGetOrCreateSlice` | 783 | `slice_cache`, key `(elem<<1)\|ic`, **lookup-first** | none (slice size 8, state 2 always) | YES (unconditional `MapPut`) |
| `typeRegistryGetOrCreateOptional` | **814** | `optional_cache`, key = payload | size/align only if `pay_type.state == 2` | **NO** — `MapPut` guarded `if (opt_state == 2)` (:834). A composite created before its payload is laid out is appended (state 0, size 0) and **never cached** → the next call mints a second id. **This is D1 bug 1.** |
| `typeRegistryGetOrCreateErrorUnion` | **839** | `eu_cache`, key `(payload<<32)\|error_set` | size/align only if payload `state == 2` | **Partial** — `MapPut` is unconditional (:866), so EU identity IS canonical today (spec §2 text "all three cache only when laid out" is stale for EU), BUT a pre-layout creation still freezes `state=0/size=0` and nothing later mutates it (see late-layout gap below) |
| `typeRegistryGetOrCreateArray` | **869** | `array_cache`, key `(elem<<32)\|length` | size/align only if `elem.state == 2` | **NO** — `MapPut` guarded `if (elem_ty.state == 2)` (:909). Same duplicate-id bug class as Optional |
| `typeRegistryGetOrCreateTuple` | 915 | **no key-cache at all** | none (state 2, size 0) | **NO** — every call appends a fresh tuple id (audit item for T1: tuple identity is name/creation-order dependent) |
| `typeRegistryGetOrCreateFn` | 966 | linear scan by `(name_id, module_id, stdcall-bit)` | none (state 2) | Name-keyed, NOT structural: two spelled-identical fn-ptr types with different minted names are distinct ids; two anonymous ones with equal `name_id` would collide. T1's structural `fn_type` comparison is the belt-and-braces |
| `typeRegistryGetOrCreateErrorSet` | 1000 | (per-kind payload; not in D1 family) | — | audited out of family scope |

- **Late-layout gap (all composite kinds):** the registry has no state-mutation writes (every `.state =` is a creation site); layout resolution lives in `sf/src/type_resolver.zig` (`layoutEnsure:433`, `typeResolverResolve` — sets `state=2` on the topologically resolved set). A composite created **after** that pass (or before its payload resolves) keeps `state=0/size=0` forever unless T1 adds on-demand `layoutEnsure` (spec §2 Fix 1 second clause). Confirmed no post-creation `.state =` writes by grep (`type_registry.zig`).
- **`typeRegistryIsAssignable:1813` fn_type comparison:** :1830-1849 — `src_f.return_type == tgt_f.return_type` **by id directly**, params by id equality, plus flags bits. Exactly the D1 hard-error path (`error[3000] type mismatch in field initialization … source: function / target: pointer`). EU↔EU comparison (:1858-1866) likewise compares `payload` by id (safe only while EU identity is canonical). Optional payload recursion at :1850-1854. T1 Fix 1's structural comparison covers `fn_type` return + params.
- Optional-family spelling/emit sites (context note, for T2 orientation only): `typeCName` optional/EU/array/slice spellings at `type_registry.zig:501-680`; P2 relation fn_type→`return_type` name_pos=1 at :1432-1437 (`typeRefsNote`).

### 1.2 Inventory (ii) — every comptime-condition consumer

**Fold-value production** (`phase_ComptimeEvaluation`, `sf/src/main.zig:642-710`) — the `comptime_folds` table is populated for exactly three node domains:
1. **every `builtin_call`** (`main.zig:671-678`) — covers `@isWindows()`; stored by node id.
2. **`var_decl` inits of kinds 33–42/62/64** (`main.zig:679-689`) — int/bool const initializers.
3. **NO-ELSE `if_expr` conditions, capture-free only** (`main.zig:690-708`) — comment verbatim: *"if_stmt conditions and if_expr with an `else` are deliberately NOT stored (bounded blast radius: their emitted C is unchanged)"*.

**Condition consumers:**
| consumer | site | behavior today |
|---|---|---|
| sema if-without-else comptime-true allowance | `semantic_analyzer.zig:23-24` (comment), `semanticAnalyzerConditionComptimeBool:3897` / `IsComptimeTrue:3915`, used at `ResolveIfExpr:3943` | no-else value-if accepted only if then-void/noreturn or condition comptime-true (Task 9B/9D, error[3059] gate). Probe = bool_literal fast-path + `comptimeEvalEvaluate` (local-const aware) |
| sema arm analysis | `ResolveIfExpr:3922` (then) + `:3962` (else); `if_stmt` work-push `:6135-6142` pushes BOTH arms | **both arms always analyzed today**; the only arm-reachability use of the comptime probe is FX9 f32-narrow status (`:4010-4015`). T3's Zig rule (untaken arm not analyzed) is NOT implemented |
| lowering `if_expr` fold | `lower.zig:6820-6871` (`ie_fold` via `comptimeFoldBool:3834`) | when the fold table has the condition and payload==0: lowers **only the taken arm** (capture-free; noreturn-typed ifs deliberately bypass the fold — Task 3 fix-r1 guard :6837) |
| lowering `if_stmt` fold | `lower.zig:7769-7786` (`if_fold`) | same: only the taken arm lowered when the fold hits + no capture. **Measured firing** on `if (@isWindows())` (no `IF:c0=` marker emitted; dead arm's call absent from the C) |
| lowering `if` non-fold path | `lower.zig:6884-6937` (if_expr), `:7788+` (if_stmt) | lowers **both arms** (the context's "~6900 lowers BOTH arms" = this path — reached for runtime conditions, captures, and noreturn-typed if_exprs) |
| `and`/`or` | evaluator short-circuit `comptime_eval.zig:1176-1214`; lowering `lowerBinaryArm:4686-4688` (`BIN_AND`/`BIN_OR`) | evaluator folds `false and X` / `true or X` (Task 9D); lowering keeps runtime short-circuit and consults no fold for the operator itself |
| `while` | lowering `while_stmt:7900-7960` (no fold consult); sema termination (`astWhileTerminates`, `diag_missing_return` rules; `while (true)` special-cased) | a comptime-false `while` still lowers its body; `while (true)` is a termination shape, not a folded condition |
| `@isWindows()` fold | `comptime_eval.zig:1579-1581` (`host_is_windows` field `:228`, default false `:267`) | folds to `true`/`false` from **`ctx.cli.target_is_windows`** (`main.zig:645`) — i.e. the CLI target (`-osw`/`-osl`), not host detection. **Drift note:** `sf/src/config.zig:4` `pub const host_is_windows: bool = false;` is an unused stale constant (context cited config.zig; the live wiring is the CLI target) |

**Measured D2 nuance (load-bearing for T3):** on the `iswindows_deadarm_*` fixtures the statement-position `if (@isWindows())` **fold path fires** (dead arm not lowered; no dead call in the emitted C) — yet the wrong-platform module is still emitted (`windep_*.c` present, pre-fix). So the surviving reachability edge is **not** the dead arm's `func_ref`/`call_direct` (the defect entry's hypothesis); it is one of the type-level/module-level channels the emitter's closure walks in `sf/src/main.zig:1306-1360`: `pruneTypeMarkByValue` over every lowered fn's hoisted-temp/param/return type ids (a cross-module type naming keeps the owner module alive — the error-union return type `E!*void` is exactly such a cross-module name), plus the `call_direct`/`tail_call`/`func_ref`/`load_global`/`store_global` scan over **all** lowered functions (including the never-called module's own fns). T3 must pin the channel repro-driven (`iswindows_deadarm_errunion_xmod` / `_prune_xmod` are the probes); making the untaken arm unanalyzed/not lowered alone may NOT fix D2 if the type-level edge remains — the scan's FAIL→OK framing below is about dead-arm *diagnostics*, and is separate from this emission channel.

### 1.3 Inventory (iii) — analyzer surface vs current language (`sf/src/analyzer.zig`, 920 lines)

Four passes, driven by `runAllAnalyzers:884` (per-fn budget `PER_FUNC_BUDGET=512K`):
- **SignatureAnalyzer** (`analyzeSignature:411`, `validateSignatureType:477`, `rejectAnytypeType:443`): accepts primitives i8–i64/u8–u64/f32/f64/bool/c_char/isize/usize, pointers `*T`/`[*]T`/fn-ptrs, slices, optionals, error unions, error sets; rejects incomplete struct/union/tagged-union/enum in signatures (`error[2011]`), `void` params (`error[2010]`), `anytype` anywhere in a signature incl. nested `?`/`*`/`[*]`/`[]`/`[N]`/`E!T`/`fn(...)` (`error[2012]`, recursive); warns `>64B` returns (`warning[7010]`). `validateSignatureType`'s ident path only inspects **named** types via `nameCacheGet` — it has **no rules at all** for fn-ptr returns of `?Aggregate`/`E!Aggregate`, arbitrary-width ints (`arb_uint_type`), `.tag` member access, or packed-union members (the doc's "C89 Compatibility Rules" in `docs/design/static_analyzers.md` §1 predate those shapes — T5's truth-up targets). A `fn (*void) ?Key` return type is a non-ident type node that falls through `validateSignatureType` untouched (its D1 failures live in sema/registry/emitter, not here).
- **LifetimeAnalyzer** (`runLifetimeAnalyzer:853`, provenance `classifyProvenance:65`, `checkReturnProvenance:106`): local-address/return/dangling tracking with field/index/slice composition; known gaps (`docs/tech_debt/static_analyzers.md` §2.1) — **no provenance through optional/error-union captures** (`if (opt) |ptr| { return ptr; }`), no field-level assignment tracking, minimal aliasing (`*ptr = &local`). Capture handling is the drift T5 must close or truth-up.
- **NullPointerAnalyzer** (`runNullAnalyzer:845`, `detectNullGuard:616`, `applyNullGuardRefinement:645`, `onNullStmt:800`): 4-state (`PtrState`) tracking across branches/loops; tag-blind member access (tech-debt §3.1) — a tagged-union `.tag` guarantee is not understood.
- **DoubleFreeAnalyzer** (`runDoubleFreeAnalyzer:874`, `handleFreeCall:245`, defer queue `:681`): alloc/free/ownership with errdefer path-awareness; recursion capped (tech-debt §1.1, resolved).
- Shared infra: `visitStatement:718` control-flow walk + `on_stmt_cb` (QUICK_REF "Analyzer detection paths"), `Provenance` enum `:31`, composite names `compositeNameId:216` (member/index nesting). Docs to truth-up at T5: `docs/design/static_analyzers.md`, `docs/sf/STATIC_ANALYZERS_p2.md`, `docs/tech_debt/static_analyzers.md`.

### 1.4 Corpus scan — reject fixtures whose only error sits in a comptime-dead `if` arm

**Verdict: ZERO hits. No STOP-present. T3's class-mover risk on pre-existing fixtures is clear.**

Search commands (run over the corpus universe `scripts/corpus/list_corpus_dirs.sh`, 1124 dirs, all `*.zig`):

```
grep -rn "@isWindows" --include="*.zig" repro/mi_matrix repro examples/z98 stdlib_test
grep -rn "if\s*(\s*(false|true)\s*)" --include="*.zig" repro/mi_matrix repro examples/z98 stdlib_test
grep -rn "while\s*(\s*(false|true)\s*)|if\s*(\s*comptime|switch\s*(\s*(false|true)\s*)" --include="*.zig" repro examples/z98 stdlib_test
grep -rn "false and|true and|false or|true or| and false| or true| and true| or false" --include="*.zig" repro/mi_matrix repro examples/z98 stdlib_test
grep -rn "= @isWindows()|if (is_|if (comptime|!true|!false" --include="*.zig" ...   # const-bound / negated forms
```

Class intersection (after the frozen classify, §3.2): the 174 FAIL+GREEN dirs intersected with the pattern set yields exactly 5 dirs — each adjudicated:

| dir (class) | pattern | where the errors sit | T3 effect |
|---|---|---|---|
| `array_size_struct_introspection_builtin_reject_xmod` (FAIL) | `[@isWindows()]u8` array size | `@isWindows()` as array-size **value** (not an if arm); reject is the non-integer-builtin rule | none (no if arm) |
| `enum_init_builtin_reject_xmod` (FAIL) | `enum(u8){A=@isWindows()}` | builtin value in enum init (not an if arm) | none |
| `f32_narrow_reject_xmod` (FAIL) | `if (true) n else 2.5` (`retIfTrueBad`) | 39 errors (18 FX3 + 15 FX9 + 6 FX10): live-arm/runtime/switch rows; `retIfTrueBad`'s reject is the **live** `n: i32` at f32 (fixture header: "a comptime-true condition makes the bad arm the taken one and still rejects"); dead arm `2.5` holds no error | class stays FAIL (38+ other errors); see Concerns C3 (header-pinned census) |
| `if_noelse_reject_xmod` (FAIL) | `if (false and run) 1`, `if (run and false/true) 1`, `if (false or run) 1`, `if (umax < 0) 3` | `error[3059]` at the **value use** of no-else ifs (the if-expr type is void); the dead then-arms hold clean literals | class stays FAIL (3059 gate fires on the value use regardless of arm elimination) |
| `try_return_type_reject_xmod` (FAIL) | `if (true) try gIF() else 0` (`ifv` row) | `error[3075]` at the `try` in the **live** arm (void fn); dead `else 0` is clean; 8 more 3075 rows outside if-shapes | class stays FAIL; census `3075 9` stable (live-arm diagnostic) |

All other pattern hits are OK-class (no errors at all): `target_is_windows_xmod`, `callconv_stdcall_decl_xmod`, `plat_stubs_missing_xmod`, `console_builtin_test`, `stdlib_time_monotonic_avail_xmod`, `stdlib_comptime_true_if_xmod`, `stdlib_comptime_noreturn_if_xmod`, `stdlib_f32_narrow_ok_xmod`, `stdlib_comptime_compare_xmod`, `m4_array_to_slice_len_xmod`, `if_expr_str_literal_xmod`, `emission_conflation_control_xmod` (GREEN control), `emission_array_copy_xmod` (its RED `fb = src;` sits in the **live** `if (true)` arm — stays FAIL under T3), `emission_labeled_ctrl_xmod`, plus the example trees (`rogue_mud*` `if (!@isWindows())`, `z9torr/console.zig`). `while (true)` bodies (39 sites) are live loops. Untracked z9play M6 WIP (`examples/z98/z9play/platform/audio_win9x*.zig`) is not imported by any entry (inert).

### 1.5 Rulings (this task)

- **R1 (fixture golden policy):** goldens are measured from the current pre-fix compiler wherever the program reaches runtime (the context convention). Where the defect itself prevents measurement (frontend reject → `expected.rc` + `expected_error.txt` reject-census shape, `git add -f`; emit/build/link-fail → no golden, `NOTES.md` red evidence + expected classification, the `zT_missing_fwd_xmod` shape). GREEN contracts for the post-fix goldens live in each `main.zig` header; the fixing task (T1/T2/T3/T4) captures them at flip time (`run_fixtures.sh --capture`). — why: the only honest "runtime output from the current compiler" for an unbuildable program is none. Cost if wrong: T1–T4 capture one golden per fixture instead of T0.
- **R2 (switch-form spelling):** `conditional_import_switch_xmod` uses `true`/`else` prongs because Z98's switch rejects exhaustive bool without `else` (`error[3068]`, measured) — the `true`/`false` observation is recorded in that fixture's NOTES (out of T4 scope). Cost if wrong: one prong rewrite if the operator wants the exhaustive spelling pinned as a separate reject fixture.
- **R3 (D2 fixture pair):** `iswindows_deadarm_errunion_xmod` = faithful weaponized repro (FAIL both targets, red = the defect consequence); `iswindows_deadarm_prune_xmod` = host-neutral twin carrying the pre-fix runtime golden + emission contract (OK class both ways; the corpus classifier compares CLASS files, not emitted C — gate 2's parenthetical). Cost if wrong: one redundant fixture.
- **R4 (baseline order):** the battery baseline (§3) is frozen on the tree BEFORE fixture landing (brief order); the class-file md5 anchor applies to the 1124-line pre-landing file; the post-landing file is 1130 lines with exactly the 6 new fixture lines (§2.2). Cost if wrong: none (both files are recorded).

---

## 2. Fixtures

All under `repro/mi_matrix/`; all sources + NOTES committed in `test(repro): T0 — D1/D2/conditional-import fixtures`. Pre-fix red measured with the gate compiler `/tmp/d1d2_build/zig1_5_clean` (md5 `f18b69ece1917bf970a036b276e5e403`), mode `-ffast` (oob-adjacent `-fsafe` noted per fixture).

### 2.1 Per fixture

| fixture | purpose | source | goldens + how measured | pre-fix red (expected-class) | post-fix contract / class |
|---|---|---|---|---|---|
| `fnptr_opt_aggregate_coerce_xmod` | D1 reproducer A: free fn `fn (*void) ?Key` → fn-ptr field coercion | `main.zig` (single file, defect-entry program) | `expected.rc`=`2`, `expected_error.txt`=`3000 1` — dump rc + stderr census measured pre-fix (1× `error[3000]: type mismatch in field initialization`, source: function / target: pointer). **No `expected.txt`** (cannot run pre-fix) | dump rc 2, 0 `.c` → **GREEN** (recorded pre-fix) | T1: runs, stdout `coerce sigint ok` rc 0 (goldens captured at T1) → **OK** (new-fixture flip) |
| `fnptr_opt_aggregate_emit_xmod` | D1 reproducer B: struct merely DEFINING `readKey_fn: fn (*void) ?Key` | `main.zig` + `contract.zig` (defect-entry contract) | none measurable (build dies in gcc); `NOTES.md` evidence | dump rc 0, 6 `.c`, gcc fails `zig_special_types.h:663:29: expected declaration specifiers or '...' before '*' token` → **FAIL** | T2: all `.c` gcc-clean, stdout `fnptr emit ok` rc 0 → **OK** |
| `iswindows_deadarm_errunion_xmod` | D2 faithful/weaponized: error-union fn ref in the opposite-comptime `@isWindows()` arm; platform-only `@cInclude`s | `main.zig` + `windep.zig` (`<windows.h>`) + `linuxdep.zig` (`<sys/ioctl.h>`) | none measurable (host gcc dies on wrong-platform include); `NOTES.md` evidence both targets | linux: dump rc 0, 8 `.c` **including `windep_*.c`** (dead arm), gcc `windep_*.h:6:10: fatal error: windows.h` → **FAIL**; `-osw`: both modules emitted, mingw `linuxdep_*.h:6:10: fatal error: sys/ioctl.h` → FAIL (measured) | T3: wrong-platform module absent both targets; stdout `iswindows deadarm ok` rc 0 → **OK** |
| `iswindows_deadarm_prune_xmod` | D2 emission-pruning twin (host-neutral modules) with PRE-FIX runtime golden | `main.zig` + `windep.zig` + `linuxdep.zig` (no `@cInclude`) | `expected.txt`=`iswindows prune ok\n` (19 B), `expected.rc`=`0` — measured pre-fix via `scripts/stdlib/run_fixtures.sh --capture` (3x byte-identical; CAPTURED) | runs clean but `windep_F4B0B95D.c` PRESENT in output (dead arm) → **OK** (class-stable; emission red documented) | T3: golden preserved + `windep_*.c` ABSENT (linux) / `linuxdep_*.c` ABSENT (`-osw`) → **OK** (no class mover) |
| `conditional_import_if_xmod` | §4 if/else conditional `@import` | `main.zig` + `a.zig` + `b.zig` | none measurable (gcc-invalid C); `NOTES.md` evidence | dump rc 0, 6 `.c` (NEITHER `a_*` nor `b_*` emitted), gcc `main_D1CCDD00.c:29:24: error: 'zT_4294967295' undeclared` → **FAIL** | T4: `impl`=live module; stdout `b ping\ncond import if ok` (linux) / `a ping\n…` (`-osw`) rc 0 → **OK** |
| `conditional_import_switch_xmod` | §4 switch-form conditional `@import` | `main.zig` + `a.zig` + `b.zig` | none measurable (link fail); `NOTES.md` evidence | dump rc 0, 6 `.c` (no a/b modules), gcc `-c` clean (implicit-decl tolerance), **link rc 1** `undefined reference to 'zT_1'` → class **OK** (compile-only classifier; red is link-fail — invisible to classify, see C4) | T4: links + runs, stdout `b ping\ncond import switch ok` rc 0 → **OK** |

### 2.2 Fixture classes in the canonical classifier (post-landing corpus)

`bash scripts/corpus/classify /tmp/d1d2_build/zig1_5_clean /tmp/d1d2_work/corpus_postfixture.txt` → 1130 dirs; `diff` vs the frozen 1124-line anchor is **pure additions** (0 common-dir movers):

```
> repro/mi_matrix/conditional_import_if_xmod FAIL
> repro/mi_matrix/conditional_import_switch_xmod OK
> repro/mi_matrix/fnptr_opt_aggregate_coerce_xmod GREEN
> repro/mi_matrix/fnptr_opt_aggregate_emit_xmod FAIL
> repro/mi_matrix/iswindows_deadarm_errunion_xmod FAIL
> repro/mi_matrix/iswindows_deadarm_prune_xmod OK
```

Designed post-fix trajectory (T1–T4; NEW fixtures only — pre-existing corpus must not move): coerce GREEN→OK (T1), emit FAIL→OK (T2), errunion FAIL→OK (T3), prune OK→OK + emission pruned (T3), cond_if FAIL→OK (T4), cond_switch OK→OK + becomes linkable (T4).

---

## 3. Runtime battery (frozen baseline — all 8 items)

Gate compiler `/tmp/d1d2_build/zig1_5_clean`. Measured on the tree BEFORE fixture landing where the gate is universe-wide (items 1–2 order per brief; items 3–8 fixture-independent).

### 3.1 Seed two-hop (item 1)
```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/d1d2_build
→ [seed] hop1 binary md5: f18b69ece1917bf970a036b276e5e403
  [seed] hop2 binary md5: f18b69ece1917bf970a036b276e5e403
  [seed] two-hop closure OK: hop1 == hop2 == f18b69ece1917bf970a036b276e5e403
  === [seed] Done: /tmp/d1d2_build ===
```
**hop1 == hop2 == expected fixed point `f18b69ece1917bf970a036b276e5e403` — MATCH.**

### 3.2 Corpus classify (item 2)
```
bash scripts/corpus/classify /tmp/d1d2_build/zig1_5_clean /tmp/d1d2_work/corpus_baseline.txt
→ wrote …: 1124 dirs
md5sum → 518eca1a9b5d3e1cc5a48abce214abd8   (== frozen anchor, byte-identical)
awk tally → 950 OK / 58 GREEN / 116 FAIL   (no ICE/CRASH/NOENTRY)
```
**MATCH: class file byte-identical `518eca1a9b5d3e1cc5a48abce214abd8`, `1124 = 950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`, 0 movers.** (Post-landing 1130-line file: §2.2.)

### 3.3 Goldens 5/5 (item 3)
Build (QUICK_REF recipe): `zig1 --dump-c89 <ENTRY> > g.c` + `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include g.c zig_runtime.c zig_pal.c -o g` — all 4: dump rc 0, gcc rc 0, 0 `error:`.

| golden | command | observed md5 | expected | match |
|---|---|---|---|---|
| gol (100 gens) | `timeout 120 ./gol > gol.out` rc 0 | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | **YES** |
| lisp `(+ 1 2)` | `printf '(+ 1 2)\n' \| timeout 60 ./lisp` rc 0 | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f8974da24ddbf9d389f3d7d97322` | **YES** |
| json | `cd examples/z98/json_parser && timeout 60 …/json` rc 0 | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a1ec07d14a301bc343df32bf8` | **YES** |
| mud server | `bash examples/z98/mud_server/demo/session.sh …` rc 0 | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0abb926cca7baf9a0d1692ab318` | **YES** |
| mud client | (same session) | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f0bbd983a9d844fea8b7a6fa7` | **YES** |

**5/5 MATCH.**

### 3.4 mi_matrix SET 25 + oob trap (item 4)
```
bash scripts/stdlib/run_fixtures.sh /tmp/d1d2_build/zig1_5_clean <the frozen 25 dirs>
→ run_fixtures: 25 PASS / 0 FAIL over 25 dirs
```
Frozen 25 (explicit enumeration; the load-bearing list — see C2): `array_of_struct_literal_xmod`, `catch_discard_struct_xmod`, `const_assign_ok_xmod`, `empty_named_struct_field_xmod`, `empty_named_struct_xmod`, `enum_subbyte_backing_xmod`, `f64_literal_precision_xmod`, `field_store_continue_nested_xmod`, `field_store_continue_xmod`, `fn_ptr_signature_ok_xmod`, `for_range_end_len_xmod`, `len_array_field_xmod`, `lexer_float_exponent_xmod`, `lit64_decimal_xmod`, `nested_loop_label_xmod`, `optional_void_present_xmod`, `packed_nested_whole_depth_ok_xmod`, `packed_nested_wholeliteral_xmod`, `packed_union_struct_wholemember_xmod`, `shadow_ok_xmod`, `sig_known_type_ok_xmod`, `slice_index_field_store_xmod`, `tagged_payload_whole_reassign_xmod`, `tagged_tag_member_shadow_xmod`, `tagged_tag_sugar_xmod`.

oob trap `slice_index_field_store_oob_xmod` (`-fsafe` recipe): dump rc 0, build rc 0, run **rc 133** (Trace/breakpoint trap), stdout 0 B md5 `d41d8cd98f00b204e9800998ecf8427e` = `expected.txt` (rc pin `133`). **MATCH.**

### 3.5 Examples 26/26 build + 26/26 run (item 5)
Build per dir (`zig1 -ffast -o <out> <entry>` + `sh build_target.sh linux <out>/prog`, CWD out-dir): **26/26 OK** (dump rc 0, ≥1 `.c`, build rc 0). Run (CWD=example dir, `timeout 25`, mud `timeout 8`, stdin `/dev/null`, rogue* fed `q\n`): **26/26 correct** — stdout md5s match the previous T0 run table on 25/26 (days_in_month `8c0d394c…`, fibonacci `b53b3a3d…`, func_ptr_return `f6a54779…`, gol `fcbf7e7c…`, heapsort `8cf0a784…`, hello `74630882…`, json* `8bda3d5a…`/`dc22fa47…`, lisp* `1c1f0a41…`×4, lzw `c3c7765e…`, mandelbrot `d5966775…`, mud rc 124 `9545fe1d…`, prime `d095a94d…`, quicksort `45d2f0fb…`, rogue* `3fb6709e…`×2, sort_strings `c6c047cb…`, tco `264ea6b1…`/`3d70c50b…`/`7421137a…`, z9torr rc 1 `f666af15…`); the 1 delta is z9play rc 1 `f35b7ef7d832cc4a` (usage-on-no-args text updated by z9play M5/M5b after that old table — output is the correct usage banner, see C1).

### 3.6 Stdlib (item 6)
```
bash scripts/stdlib/verify_stdlib.sh /tmp/d1d2_build/zig1_5_clean
→ run_fixtures: 285 PASS / 0 FAIL over 285 dirs
  STDLIB GATE OK
```
**285/0 MATCH.**

### 3.7 The 8 `--dump-c89` pins (item 7, frozen baseline)
`zig1 <mode> --dump-c89 <ENTRY> | md5sum` (repo root):

| entry | `-fsafe` (authoritative) | `-ffast` | QUICK_REF table (2026-10-16) | delta |
|---|---|---|---|---|
| `examples/z98/mud_server/main.zig` | `bbc02913a10af9b0b5ed0f292f4e3407` | `fa346108ed00d03a037c2f9331d3bdf8` | same | **0** |
| `examples/z98/game_of_life/main.zig` | `93c5e3fdc5b80b2f3db020d995abbe3f` | `01a4e2265b33c97a8ca6ff3dfa551231` | same | **0** |
| `examples/z98/lisp_interpreter_curr/main.zig` | `6da05d070acd414674b1b1ec947baa5c` | `e3970e33ac09c8dfaa316d2d69bf61ec` | same | **0** |
| `examples/z98/json_parser/main.zig` | `af3823fae0b29fa4d4ca58932538d631` | `24e0e812e7dffa5a43750135405ffe3f` | same | **0** |

**old→new: 8/8 UNCHANGED** (the table was re-baselined at the emitter-sanitization closeout on this same fixed point). These are the frozen T0 pin values; T1–T4 record old→new (MAY move per operator ruling).

### 3.8 Markers telemetry (item 8)
```
zig1 --markers --dump-c89 examples/z98/game_of_life/main.zig > mk.c 2> mk.bin
→ marker_lines=3437 bytes=38384
top prefixes: 2005 INT:new / 423 DC:k / 241 FE:p / 195 P / 195 FWD:n= / 122 RaD / 86 MT / 69 FE:
```
**3437 lines / 38384 B — MATCH** the closeout telemetry.

### 3.9 Baseline freeze summary (the anchor)

| gate | frozen observed value | vs spec §6 anchor |
|---|---|---|
| seed two-hop | hop1 == hop2 == `f18b69ece1917bf970a036b276e5e403` | MATCH |
| corpus class file | md5 `518eca1a9b5d3e1cc5a48abce214abd8`, `1124 = 950/58/116/0/0`, 0 movers | MATCH |
| goldens | gol `fcbf7e7c…`, lisp `b3d9f897…`, json `8bda3d5a…`, mud `66c8f0ab…`/`93147d0f…` | 5/5 MATCH |
| mi_matrix | 25 PASS / 0 FAIL + oob rc=133/empty `d41d8cd9…` | MATCH |
| examples | 26/26 build + 26/26 run correct | MATCH (C1: z9play usage text delta vs old table) |
| stdlib | 285 PASS / 0 FAIL / STDLIB GATE OK | MATCH |
| 8 pins | 8/8 == QUICK_REF 2026-10-16 table | recorded old→new: unchanged |
| markers | 3437 lines / 38384 B | MATCH |

---

## 4. Concerns

- **C1 (z9play example stdout):** `examples/z98/z9play` usage-on-no-args stdout md5 `f35b7ef7d832cc4a` differs from the previous T0 run table (`2016494d…`) — the usage banner was changed by z9play M5/M5b example work after that table. Output is the correct usage text (26/26-run gate is "run correct", not table-identity). No action.
- **C2 (anchor-set definition drift):** `iswindows_deadarm_prune_xmod` matches the mi_matrix runtime-anchor SET *definition* (non-stdlib ∧ non-empty `expected.txt` ∧ `expected.rc==0`), so definition re-enumeration now yields 26, not 25. The frozen 25 are enumerated by name in §3.4 (the load-bearing list); later tasks run that explicit list (optionally + prune). Updating `scripts/stdlib/expected_dirs.txt` is NOT needed (that pin governs `stdlib_*` dirs only).
- **C3 (f32 census watch for T3):** `f32_narrow_reject_xmod`'s error census (39) is header-pinned only (no `expected_error.txt`). The `retIfTrueBad` row's dead else arm participates in today's arm typing; T3's dead-arm elimination may shift that row's diagnostic count/attribution while the class stays FAIL. Re-verify the census at T3 and update the header if it moves (not a class mover).
- **C4 (classify blind spot):** `conditional_import_switch_xmod` is class OK pre-fix while its binary cannot LINK (implicit-decl tolerance in the binding gcc flag-set). Its red/green is verified at run level, not by the class file. No pre-existing mover risk either way.
- **C5 (spec drift, recorded not fixed):** (a) spec §2 text says all three composite caches are layout-guarded — actual code: Optional:814 + Array:869 are; ErrorUnion:839 caches unconditionally (still freezes a state-0 layout pre-resolution). (b) context cited `config.zig` for `host_is_windows`; the live wire is `ctx.cli.target_is_windows` (`main.zig:645`) and `config.zig:4` is an unused constant. (c) tuple GetOrCreate has no key-cache at all (T1 audit item). (d) D2's "dead func_ref" edge hypothesis is empirically wrong for the statement-position shape (§1.2 measured nuance) — T3 must pin the real channel.
- **C6 (untracked WIP in tree):** `examples/z98/z9play/platform/audio_win9x*.zig` (z9play M6 WIP, untracked) are not imported by any corpus entry; anchor class file matched byte-identical with them present. Left alone per GIT rules.
- **C7 (fixture convention deviation, ruled R1):** 5 of 6 fixtures carry no `expected.txt` (pre-fix runtime unreachable). Each carries `NOTES.md` with measured red + expected classification (the `zT_missing_fwd_xmod` precedent) and a GREEN contract in its `main.zig` header; T1–T4 capture goldens at flip time. Only `iswindows_deadarm_prune_xmod` + `fnptr_opt_aggregate_coerce_xmod` (reject-shape pins) carry measured goldens.
