# mi_matrix corpus — expected-fail manifest (v52 2026-09-02)

## RED FIXTURE — switch_expr_payload_capture_xmod (2026-09-02)

New corpus fixture `repro/mi_matrix/switch_expr_payload_capture_xmod/main.zig` (plan
`2026-09-02-switch-expr-payload-capture-fix-plan.md`, Task I-SWEXPR): a switch used as an
EXPRESSION with a payload-capture prong mis-lowers in zig1 — the payload binding
(`load_field` + `decl_local`) is emitted into the wrong block (dead default fall-through in an
exhaustive no-else switch, or the dispatch block before the case label with an `else` prong)
because at the expression-site (`lowerExprImpl`, sf/src/lower.zig ~4169-4171) the capture
emissions precede `self.current_bb = prong_bb_id;` (~4180). The capture is read UNINITIALIZED.
The statement-switch site (`lowerStmt`, ~5026 before ~5028-5052) is correct. Original repro:
U-JSON json_parser_upgraded rc=139 SIGSEGV; probes `/tmp/ujson/probes/pA.zig` (exhaustive
no-else, rc=139) + `pB.zig` (else-unreachable, garbage).

- **Expected GREEN stdout** (28 B, deterministic, both paths identical): `helloA\nhelloA\n
  helloB\nhelloB\n` (k=0 → payload `helloA`, k=1 → `helloB`; per k an expression-switch
  extraction line then a statement-switch sibling line).
- **Current RED status:** RUNTIME-gated guard — compile-gate OK (dump rc=0, 4 `.c`, 0 `error[`,
  0 PANIC on all 4 compilers; gcc `-c` + link rc=0) so the standard corpus compile sweep
  classifies it OK; the guard fires in run/golden-style batteries and the F-task gate. Measured
  on all 4 compilers (ref `/tmp/fx_subfolder/zig1` + the three `e2028dcf` self-host binaries):
  run rc=0 with stdout `\nhelloA\n\nhelloB\n` (16 B — the two expression-switch lines are EMPTY,
  the captured slice is uninitialized garbage read as empty; emitted `main_*.c` byte-identical,
  md5 `ec77cc10…`, across all four). Sibling shapes crash rc=139 SIGSEGV (pA probe, fixC
  write-loop variant); the committed fixture manifests as deterministic garbage-empty output.
  Emitted defect region (ref): the dispatch `switch (zT_11){case 0: goto z_bb_5; case 1: goto
  z_bb_6; default: goto z_bb_7;}` is followed by `z_bb_5: zT_14 = s;` (reads unassigned capture),
  a stranded `s_1 = kv.payload.A._0;` after the case-0 goto, and `s = kv.payload.A._0;` in the
  dead `z_bb_7` default — while the statement sibling emits `z_bb_1: s = kv.payload.A._0; r = s;`
  correctly inside its case block.
- **Rule:** the fixture MUST print the expected GREEN stdout above (rc=0) after any future change;
  a return of empty expr lines / SIGSEGV / garbage marks the switch-expression payload-capture
  regression.

## GATE — zig1 self-host closure plan, gate-record reconciliation (2026-09-02)

Final gate of the zig1 self-host closure plan (docs/superpowers/plans/2026-09-02-zig1-selfhost-closure-plan.md),
measured on the plan's fixed-point chain (reference `/tmp/fx_subfolder/zig1`, zig0-built md5 `29327e2c`,
vs the 5 byte-identical self-host binaries under `/tmp/zig1_5*`, md5 `e2028dcf`, size 2,930,952 B).
Docs-only task — no `sf/src`, fixture, or script change. Reconciliation notes for the
expected-fail/gate record:

- **4 MD5 gates UNCHANGED (no re-baseline):** gol `302df36b…` / lisp `3591bad9…` / json
  `76056b97…` / mud `4591fef0…` byte-identical on both new hops. Golden 9/9 PASS; matrix 21/21
  PASS (mud/rogue/gol timeout-gated rc=124 = PASS). Corpus 404 dirs at `-s0`: reference
  OK=394 / FAIL=10 (= exactly the 10 green-guards, unchanged set) / ICE=0 / CRASH=0, hop
  identical, **asymmetric = 0**.
- **`_upgraded` example dirs are NEW — exempt from the 4-MD5 gate:** `lisp_interpreter_upgraded`
  (commit `ab318b1e`) and `rogue_mud_upgraded` (commit `93d3ee79`) are new `examples/z98` dirs,
  not corpus/gate members; their emissions differ from the originals by design (source-only
  idiomatic rewrites), stdout byte-identical to the originals on all 4 compilers. The original
  gate dirs (gol/lisp/json/mud) are untouched — no re-baseline.
- **`json_parser_upgraded` DEFERRED (NOT committed) — recorded as a known deferred compiler
  gap:** the planned const-from-switch-expression rewrite (json.zig key extraction) SIGSEGVs
  rc=139 on all 4 compilers from a REAL zig1 emission bug (switch-as-expression with payload
  capture mis-lowers: payload binding emitted after the dispatch `goto` before the case label →
  skipped → uninitialized read). Statement-switch form emits correctly. Follow-up I/F task to
  fix the emission bug to be created by the controller; the untracked dir stays for that fix.

Determinism fixed point **CLOSED** (self-host chain byte-identical, `e2028dcf`); the bootstrap
cycle is closable via the future cInclude-zig1-only migration.

## GATE — spill backend config plan, FULL sweep + reconciliation (2026-09-02)

Final gate battery of the spill backend config plan
(docs/superpowers/plans/2026-09-02-spill-backend-config-plan.md), at HEAD `cc5c37c1`, measured
with `/tmp/fx_subfolder/zig1` (reference rebuilt at HEAD from the F-S self-host generation —
the zig0 bootstrap cannot compile modern `sf/src`; canonical std reinstalled at
`/tmp/fx_subfolder/lib/`) vs self-compiled `/tmp/zig1_5/zig1_5_clean`. Docs-only task — no
`sf/src`, fixture, or script change in this gate. **This is the plan-complete closeout of the
spill backend config: F-SIDE (AST value pools disk-backed) + F-FMT (RES 5 B/node) + F-SBackend
(`SpillStore` Disk/Ram routing) + F-MM (`-mm<N>` default 64 MB ACTIVE) + F-S (`-s<N>` decremental
levels).** The `-s<N>` level is a runtime storage choice — emission is **byte-identical at every
level `-s0`..`-s5`** (same data, different storage medium).

### Pool trajectory (pool= at self-compile, `--markers --track-memory`, self-hosted binary)

| level | pool= (K) | note |
|---|---|---|
| allocator-crux GATE (plan predecessor) | 25,742 | canonical anchor before the spill-config work |
| plan start (I-SIDE baseline) | 15,324 | reference on the pre-change tree |
| `-s0` (all disk, default) | **14,857** | fits the `-mm64` default (no flag needed) |
| `-s1` (+AST → Ram) | 33,290 | fits `-mm64` |
| `-s2` (+LIR → Ram) | 70,922 | **exceeds 64 MB → ICE rc=3 unless paired with `-mm128`** |
| `-s3` (+HASH → Ram) | 70,922 | needs `-mm128` |
| `-s4` (+RES → Ram) | 72,970 | needs `-mm128` |
| `-s5` (all Ram; max level) | **72,970** | Ram-mode resident pool; **no `.zig1_*.tmp` created** |

F-SBackend measured Disk 13,764 K / all-Ram 72,903 K on its intermediate tree; the 13.8–14.9 K
Disk band is the documented free-list segment-reuse noise (F-SBackend note 3), not a real change.
Only `-s0`/`-s1` hold the `-mm64` default on the self-compile workload; `-s2`..`-s5` need `-mm128`
(the documented `-mm`/`-s` pairing tradeoff). Small fixture/gate workloads fit every level
unflagged.

### Step 1 — full gate battery

1. **4 MD5 gates byte-identical at every level `-s0`..`-s5` (repo-root CWD, no re-baseline):** gol
   `302df36be57e9876549d6a8b4031bf95` / lisp `3591bad9726ca0947eae3f8a9a6e7273` / json
   `76056b978f6330c8af0c7f23b3244135` / mud `4591fef0346b42738874ce992c72f4c2` (dump rc=0 each,
   `timeout 120`). Storage-only difference → byte-identity holds at every level.
2. **Golden 9/9 fixtures 9/9 at every level `-s0`..`-s5`** (tco_return_try / tco_defer /
   tco_factorial / fn_ptr_struct_field / func_ptr_return / quicksort / hello /
   emission_assoc_chain_xmod / emission_lower_crash_xmod): runtime stdout + rc byte-identical to
   the F-S golden captures at each level.
3. **21-example matrix 21/21** dump/gcc/link rc=0 (19 RUN_OK + mud_server/rogue_mud
   server-timeout by design; 4 single-file entries func_ptr_return/mandelbrot/quicksort/sort_strings).
4. **Corpus sweep at `-s0` (404 dirs = 330 mi_matrix + 53 top-level repro + 21 z98; `slice_matrix`
   matrix-of-subdirs skipped):** **334 RUN_OK** (incl. `game_of_life` which completed rc=0 with the
   correct glider grid this run — the memory-refactor gate's gol RUN_TIMEOUT was a sweep-timing
   artifact, not a behavior change) + **56 LINK_FAIL** (extern-fn tests; identical
   `undefined reference` class — not a regression) + **10 DUMP_FAIL** (= the 10 green-guards
   exactly: eu_assign_incompat_payload / euvoid_val_catch / field_access_optional / var_declared_void /
   emission_pal_xmod / strictzig_brace_if_xmod / parsergap_selfblok_xmod / parsergap_strict_comma_xmod /
   parsergap_slice_expr_xmod / self_embed_optional_cycle) + **2 RUN_TIMEOUT** (mud_server / rogue_mud,
   servers) + **2 RUN_FAIL** (known symmetric crashes both compilers: `intcast_range_check` rc=134,
   `voiddecl_xmodtype_xmod` rc=139). Garbage dirs `emission_void_temp_enum_xmod` and
   `voiddecl_payload_xmod` classified RUN_OK rc=0 (output unstable by design — NOT a bug). **0
   asymmetric failures, 0 NEW failures** vs the documented baseline (the only delta is gol
   timeout→OK, a timing artifact). Corpus unchanged since the memory-refactor gate (0 new `main.zig`).
5. **Self-compile:** `build_zig1_5.sh` → dump rc=0, **42 `.c`, 0 `error[`, 0 PANIC** (42 = 41 + the
   `spill_store` module — the plan's "41" is stale); rebuilt `zig1_5_clean` runs hello **byte-equal**
   to reference (`Hello, world!\n`). Reference emission vs self-emission: **same 42-file set,
   0 byte-different pairs** (the compiler's own C at HEAD is byte-identical to its self-compile).
6. **`--track-memory` self-compile at `-s0`:** `pool=14857K`; the pool= trajectory is above.

### Step 2 — `-mm` enforcement

- **`-mm64` default is ACTIVE and HOLDS self-compile** at `-s0`/`-s1` (pool 14,857/33,290 K <
  65,536 K).
- **`-s2`..`-s5` at the default ICE rc=3** — `memory limit exceeded: pool limit=65536K pool=70-73M`
  + `ICE: out of memory at allocator.zig:28`; pairing with **`-mm128`** compiles cleanly
  (rc=0, 42 `.c`, 0 err, 0 PANIC) at every level — the documented tradeoff, not a regression.
- **Canary `-mm1` self-compile ICEs rc=3** — `memory limit exceeded: pool limit=1024K pool=6513K`
  + `ICE: out of memory at allocator.zig:28` (budget now live by default; was an inert 16 GiB opt-in).
- Spill-file ladder confirms the prefix deactivation: `-s0` all `.zig1_*.tmp` present,
  `-s1` drops `.zig1_ast.tmp`, `-s2` also `.zig1_lir.tmp`, `-s3` also `.zig1_hash.tmp`,
  `-s4` also `.zig1_res.tmp`, `-s5` none.

### Step 3 — warning-clean confirmation

`gcc -m32 -std=c89 -O3 -Wall -Wextra -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration -I sf/src/include -fsyntax-only` on BOTH
`/tmp/fx_subfolder/*.c` (reference) AND `/tmp/zig1_5/gen/*.c` (self-emitted): **0 warnings,
0 errors** on both, with the 1 pre-authorized `-Wbuiltin-declaration-mismatch` fwrite carve-out
each (`/tmp/fx_subfolder/pal_388A8A1B.c:700` and `/tmp/zig1_5/gen/pal_388A8A1B.c:700` — same
fwrite declaration class, not a defect).

### Milestone statement

The spill backend config plan is **complete**: I-SIDE (AST side-table census) + F-SIDE (AST value
pools `identifiers`/`int_values` disk-backed, −568 K realized) + I-FMT/F-FMT (RES dense record
10→5 B/node, source half → sparse only-on-Set resident map; `.zig1_res.tmp` halves) +
I-SBackend/F-SBackend (`SpillStore` Disk/Ram routing of all five spills, scalar per-spill flags,
uniform `SPILL_SEEK_MAX`; Ram mode = resident, no `.zig1_*.tmp`) + I-MM/F-MM (`-mm<N>` MB hard
budget, default 64 MB ACTIVE) + F-S (`-s<N>` decremental levels, help/README docs). 4 MD5 gates
byte-identical at every level (no re-baseline). Golden 9/9 at every level. Matrix 21/21. Corpus
404 dirs **0 asymmetric**. Self-compile 42 `.c` / 0 err / 0 PANIC, hello byte-equal, reference
emission byte-identical to self-emission. Warning-clean both builds. **pool= at `-s0` = 14,857 K
(same order as the plan-start 15,324 K); the pool rises with `-s` as designed (33,290 → 70,922 →
72,970 K) — a storage tradeoff, not a regression; the `-mm64` default holds `-s0`/`-s1` and the
higher levels need `-mm128` (documented).**

## GATE — zig1 memory-refactor execution plan, FULL battery + reconciliation (2026-08-26)

Final gate battery of the zig1 memory-refactor execution plan
(docs/superpowers/plans/2026-08-26-zig1-memory-refactor-execution-plan.md),
at HEAD `179257dc`, measured with `/tmp/fx_subfolder/zig1` (reference oracle rebuilt at HEAD;
canonical std reinstalled at `/tmp/fx_subfolder/lib/`) vs self-compiled `/tmp/zig1_5/zig1_5_clean`
(built from HEAD by `scripts/self_compile/build_zig1_5.sh`). Docs-only task — no `sf/src`,
fixture, or script change in this gate. **This is the plan-complete closeout of the memory
refactor.** The ≤16,384 K (16 MiB) pool target is **NOT reached**; the S-series outcome is the
DOCUMENTED RESIDUAL (see trajectory below).

### Memory trajectory (pool= at self-compile, `--track-memory --markers`)

| phase | pool= (K) | event |
|---|---|---|
| baseline (pre-S) | 50,501 | canonical anchor (roadmap §1) |
| S-LIR | 42,513 | LIR streaming |
| S-HASH | 44,678 | +2,164 K (input growth + one extra 2 MiB doubling boundary; operator-ruled transient) |
| S-TOKEN | 55,038 | +10,360 K transient (interner-order + lexer window; operator-ruled transient) |
| S-AST | 35,973 | −19,065 K (AST streaming, block-backed 8-slot window) |
| S-RES | 25,738 | −10,235 K (resolved_types dense per-node array) |
| **GATE re-measure** | **25,742** | `track-memory: perm=1661K mod=2047K scr=2047K pool=25742K type_db=246K total=5755K` (Δ4 K = input growth noise vs S-RES) |

**≤16,384 K target NOT reached — documented residual.** Gap = 25,742 − 16,384 = **9,358 K (≈9.14 MiB)**.
Closures/verdicts: **M5** (AST side arrays + token value union slice) closed-unfeasible (S-AST's
block-backed window makes the ~1 MB side-array prize inapplicable); **S-INTERNER** closed-unfeasible
(measured interner text 294,744 B ≈ 0.29 MiB, not the ~4 MB plan estimate — ~3% of the gap at
highest risk, keep-resident); **I-COMPACT** no-go (16-B AstNode is a byte-identical shuffle under a
disk record — record delta 0 or +16,384 B/block worse, +2.2 MiB pool ADD if spans go resident;
migration cost 47 span-read + 45 child_2 sites for ≤0 memory effect). Remaining gap lives in
module-arena live tables / growth-chain levers, out of scope for this plan.

### Step 1 — full gate battery

1. **4 MD5 gates byte-identical (repo-root CWD, no re-baseline):** gol
   `302df36be57e9876549d6a8b4031bf95` / lisp `3591bad9726ca0947eae3f8a9a6e7273` / json
   `76056b978f6330c8af0c7f23b3244135` / mud `4591fef0346b42738874ce992c72f4c2` (dump rc=0 each,
   `timeout 120`). The memory refactor is byte-neutral for the 4 gates.
2. **21-example matrix 21/21** dump/gcc/link rc=0 per program (4 non-`main.zig` entries use their
   own names: `func_ptr_return.zig` / `mandelbrot.zig` / `quicksort.zig` / `sort_strings.zig`).
3. **Corpus sweep (404 dirs = 330 mi_matrix + 53 top-level repro + 21 z98; `slice_matrix`
   matrix-of-subdirs skipped):** **0 ASYMMETRIC diffs** (zig1 == zig1_5 behavior everywhere).
   Distribution: **333 RUN_OK** (rc+output match ref; emitted C byte-identical modulo the
   path-derived std-module hash — the self compiler resolves std from `/tmp/zig1_5/lib`, ref from
   `/tmp/fx_subfolder/lib`, so `std_*.c` names differ but content matches except the
   self-referential `#include` line) + **56 LINK_FAIL** (extern-fn tests; identical
   `undefined reference` for the reference — not a regression) + **10 DUMP_FAIL** (= the 10
   green-guards, both compilers identical) + **2 RUN_FAIL** (known symmetric crashes, both
   compilers: `intcast_range_check` rc=134, `voiddecl_xmodtype_xmod` rc=139) + **3 RUN_TIMEOUT**
   (game_of_life / mud_server / rogue_mud, both compilers; game_of_life glider grid output
   truncated-identical, mud_server boots). **1 garbage OUT_DIFF** = `emission_void_temp_enum_xmod`
   (uninitialized enum temp, output unstable by design — ref `-180421700` vs self `-172545092`,
   both rc=0; NOT a bug; `voiddecl_payload_xmod` the other known garbage dir happened to be EQ
   this run — both non-deterministic). W2-1 fixture `emission_global_alias_xmod` RUN_OK, output
   EQ.
4. **Self-compile:** `build_zig1_5.sh` → dump rc=0, **41 `.c`, 0 `error[`, 0 PANIC**; rebuilt
   `zig1_5_clean` runs hello **byte-equal** to reference (`Hello, world!\n`).
5. **`--track-memory` self-compile:** **`pool=25742K`**, `total=5755K`; residual gap to
   16,384 K = **9,358 K**.

### Step 2 — warning-clean confirmation

`gcc -m32 -std=c89 -O3 -Wall -Wextra -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration -I sf/src/include -fsyntax-only` on BOTH
`/tmp/fx_subfolder/*.c` (reference) AND `/tmp/zig1_5/gen/*.c` (self-emitted): **0 warnings,
0 errors** on both, with the 1 pre-authorized `-Wbuiltin-declaration-mismatch` fwrite carve-out
each (`/tmp/fx_subfolder/pal.c:41` reference; `/tmp/zig1_5/gen/pal_388A8A1B.c:700` self-emitted —
the same fwrite declaration class, not a defect).

### Milestone statement

The zig1 memory-refactor plan is **complete**: Phase 1 (M0/M3/M4) + Phase 2 warnings (W-1..W-4
ref + W2-1..4 gen, both 0-warning) + M1 (AstNode 32→24 B) + M2 (LirInst 32→24 B) + M5
(closed-unfeasible) + M7 (markers) + S-series (S-LIR/S-HASH/S-TOKEN/S-AST/S-RES streaming +
S-INTERNER closed-unfeasible + S-FIX-1..14 correctness) + I-COMPACT no-go. 4 MD5 gates
byte-identical (no re-baseline). Matrix 21/21. Corpus 404 dirs **0 asymmetric**. Self-compile
41 `.c` / 0 err / 0 PANIC, hello byte-equal. Warning-clean both builds. **pool=25,742 K,
target 16,384 K NOT reached — documented residual 9,358 K** (S-series outcome + I-COMPACT verdict).

## GATE — @as + TCO self-emission plan, FINAL sweep + reconciliation (2026-08-26)

Final gate sweep of the @as + TCO self-emission plan
(docs/superpowers/plans/2026-08-26-as-tco-selfcompile-plan.md),
at HEAD `dd83723f`, measured with `/tmp/fx_subfolder/zig1` (rebuilt at HEAD `dd83723f`;
canonical std reinstalled at `/tmp/fx_subfolder/lib/`). Docs-only task — no `sf/src`,
fixture, or script change in this gate. **This is the plan-complete closeout: residual
A+B (the `@as` cast builtin, ONE shared root cause) and residual C (the TCO
self-recursion back-edge) are BOTH CLOSED.**

### Residual A+B CLOSED — `@as` cast builtin unhandled in self-emission (F-AS `50be26f5`)

A (missing fn-ptr typedefs — the 4 `_FN_`/`_FP_` GCC_FAIL dirs) and B (`fn_ptr_struct_field`
compiler SEGV) share ONE root cause: `@as` had no lowering branch. The flag read
`if ((ty.flags & @as(u32, 1)) != @as(u32, 0))` at `sf/src/c89_emit.zig:736` fell through →
uninitialized temp → non-deterministic `'P'`/`'N'` cname char per `getCTypeName` call → the
var-decl references a `_FN_*` name whose `_FP_*` typedef body was emitted under a different
name → gcc `unknown type name 'zT_…_FN_…'` (observed BOTH directions: P-body/N-ref in 5
fixtures, N-body/P-ref in `inferred_errorset_fnptr`); and the `@as(u32, fi)` addend at
`sf/src/type_registry.zig:851-852` produced NO emitted instruction → uninitialized index
into `self.xt_items` → READ SEGV in `typeRegistryIsAssignable` (3/3 rc=139 reproducible).
F-AS `50be26f5` (ONLY `semantic_analyzer.zig` + `lower.zig`, 8 insertions): the `@as`
name_id is interned in both lowerer/sema init, `semanticAnalyzerIsTypeValueCast`
recognizes it, and the lowerer cast branch emits `LirInst.int_cast` (`is_checked=0`) —
mirrors the F-ASSOC `@intToEnum` precedent. All 6 A-fixtures
(`emission_void_call_xmod` / `emission_void_call_control_xmod` / `func_ptr_return_type` /
`inferred_errorset_fnptr` / `quicksort` / `func_ptr_return`) now dump/gcc/link/run rc=0
under self-compiled zig1_5 with run output matching the reference. **This SUPERSEDES the
stale "expected gcc error (class 5, `void value not ignored`)" RED snapshot in
`emission_void_call_xmod/NOTES.md`** — the void fn-ptr statement call now emits `f();`
with no assignment, gcc `-c` rc=0 (historical snapshot retained, not rewritten).
`fn_ptr_struct_field` SEGV → dump rc=0 (no SEGV), run rc=0 (empty output, as reference).
**A+B CLOSED.**

### Residual C CLOSED — TCO self-recursion back-edge (F-C `dd83723f`)

The `tco_return_try` / `tco_defer` / `tco_factorial` self-emitted recursion ran with the
recursive call dropped (no back-edge → wrong counts). Root cause: the tagged-union `.tag`
field READ had no lowering case in `field_access` (`sf/src/lower.zig`) — the result temp
was reserved at `:2676` but never filled for `.tag` reads. F-C `dd83723f` (ONLY
`sf/src/lower.zig`, +8): a `.tag` case in the tagged_union branch (after the variant-name
loop + `.payload` case) interns "tag", looks up the base's name_id, emits
`load_field { field_id = TU_FIELD_TAG (=0), result = tid }`, returns tid — mirrors the
`.payload` sibling and the store-side tag pattern. Self-emitted emissions now contain the
TCO back-edge `goto z_bb_0;` inside the recursive fn. `tco_return_try` rc 139→0
(`count(10)=10\ncount(100000)=100000`, byte-equal ref); `tco_defer` 2 `D` byte-equal ref;
`tco_factorial` unchanged. **C CLOSED.**

### Corpus (329 dirs): `OK=319 / FAIL=0 / ICE=0 / CRASH=0 / green-guards=10` (319+0+0+0+10=329)

Full sweep (per-dir dump + per-file `gcc -c`, measured at HEAD `dd83723f`) classifies
OK=319, FAIL=0, ICE=0, CRASH=0; the 10 green-guards UNCHANGED (`eu_assign_incompat_payload`
/ `euvoid_val_catch` / `field_access_optional` / `var_declared_void` error[3000];
`parsergap_slice_expr_xmod` / `strictzig_brace_if_xmod` / `parsergap_selfblok_xmod` /
`parsergap_strict_comma_xmod` error[2000]; `self_embed_optional_cycle` error[24];
`emission_pal_xmod` error[20]). **No new FAIL/ICE/CRASH vs the 329-dir baseline.**

### 21-example matrix + 4 MD5 gates

21-example matrix **21/21** dump/gcc/link rc=0. 4 MD5 gates byte-identical (repo-root
CWD): gol `eed963e0640a073ed4eebb292f136e05` / lisp `c3c5847798e4553b2e34950e085bb6c6` /
json `089e4f046464ce3882aa2b2c4e585013` / mud `a1d0dd55aada9c3fd904ae33f54de32e` (F-AS
and F-C are byte-neutral for the 4 gates — no re-baseline).

### Runtime sweep (self-compiled zig1_5 vs reference) + self-compile

Full runtime sweep of 403 programs (repro top-level 53 + mi_matrix 329 + z98 21) with
`/tmp/zig1_5/zig1_5_clean` vs `/tmp/fx_subfolder/zig1`: **333 RUN_OK** (rc+output match
ref) + **2 non-deterministic-garbage dirs** (`voiddecl_payload_xmod`,
`emission_void_temp_enum_xmod` — output unstable by design, NOT a bug) + **10 DUMP_FAIL**
(= the 10 green-guards, both compilers identical) + **56 LINK_FAIL** (extern-fn-dependent;
reference fails to link identically — not a regression) + **2 RUN_TIMEOUT** (mud_server +
rogue_mud, both compilers; mud_server boots "MUD server listening on port 4000").
Expected-change fixtures ALL RUN_OK with output matching ref: `emission_void_call_xmod` /
`emission_void_call_control_xmod` / `func_ptr_return_type` (`15`) /
`inferred_errorset_fnptr` / `fn_ptr_struct_field` (was SEGV, rc=0) / `quicksort` (asc/desc
sorted) / `func_ptr_return` (`10+5=15`) / `tco_return_try` rc=0
(`count(100000)=100000`) / `tco_defer` (2 `D`) / `tco_factorial`. Self-compile:
`build_zig1_5.sh` → **40 `.c`, 0 `error[`, 0 PANIC**; rebuilt `zig1_5_clean` runs the
R-A/R-B/C fixtures green — `func_ptr_return_type` (`15`), `fn_ptr_struct_field` (rc=0),
`tco_return_try` (rc=0) — all matching reference.

### Milestone statement

Residual A+B (`@as` cast builtin: fn-ptr `_FP_`/`_FN_` cname mismatch + `typeRegistryIsAssignable`
SEGV) + residual C (TCO back-edge: tagged-union `.tag` field_read lowering) BOTH CLOSED.
4 MD5 gates byte-identical (no re-baseline). 21-example matrix 21/21. Corpus 329 dirs
`OK=319 / FAIL=0 / ICE=0 / CRASH=0 / GREEN=10`. No residual remains from the @as + TCO
self-emission plan.

## GATE — assoc-chain misparse + pending_scope nest-safety plan, FINAL sweep + reconciliation (2026-08-26)

Final gate sweep of the assoc-chain misparse + pending_scope plan
(docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md, AMENDMENT 4),
at HEAD `0b9c8ef6`, measured with `/tmp/fx_subfolder/zig1` (rebuilt at HEAD `0b9c8ef6`;
canonical std reinstalled at `/tmp/fx_subfolder/lib/`). Docs-only task — no `sf/src`,
fixture, or script change in this gate. **This is the plan-complete closeout: residual R-1
(self-emission operator-associativity gap) and residual I-1 (`pending_scope` nest-safety)
are BOTH CLOSED.**

### Residual R-1 CLOSED — self-emission operator-associativity gap (F-ASSOC `9574208d`)

The v48 hypothesis ("likely `OpInfo.right_assoc` mis-read") was **WRONG**. I-ASSOC traced the
reversal to a single self-emission fidelity gap: **`@intToEnum` lowering** (`sf/src/parser.zig:1896-1898`
`precFromInt(v: u8) Prec { return @intToEnum(Prec, v); }` — the only `@intToEnum` in sf/src) fell
through the cast block at `sf/src/lower.zig:3510-3542` (which had branches for `@intCast`/`@intToFloat`/
`@ptrCast`/`@intToPtr` but NO `@inttoEnum`) → emitted `return zT_1;` (declared temp, never assigned) →
`next_min = precFromInt(precToInt(info.prec) + 1)` fed uninitialized garbage into the precedence-climbing
RHS parse → every binary op behaved right-associative for the second operator's RHS. F-ASSOC `9574208d`
(ONLY `sf/src/lower.zig`, 9 insertions): new `inttoenum_name_id` registered in `lowererInit`
(lower.zig:443-444/:518) + new `inttoEnum` branch in the cast block (lower.zig:3542-3546) emitting a
`LirInst.int_cast` (`is_checked=0`, no range-check) → self-emitted `precFromInt` is now
`zT_1 = (zT_2B10107F_Prec)v;`. RED fixture `emission_assoc_chain_xmod` (40485a1d) now GREEN:
self-compiled `/tmp/zig1_5/zig1_5_clean` prints `3 5 0 6 24 55 321` (was `9 2\0 0 6 2\0 5\0 3\0\0`;
reference unchanged `3 5 0 6 24 55 321`). fibonacci `5\0`-class corruption gone. **R-1 CLOSED.**

### Residual I-1 CLOSED — `pending_scope` single-slot non-nest-safety (F-PENDSCOPE `0b9c8ef6`)

I-1 (B3b-review IMPORTANT: a capture inside a for-range END expr, `for (0..if (rt) |x| x else 0) |t|`,
reused + consumed the loop capture's single-slot pending scope, orphaning `t` to a `load_local` fallback)
is fixed by **AMENDMENT 4 option (c) — reorder the for-range lowering**: the capture-add block
(`maybeDisambiguateCapture` + `addLocalDecl` + `decl_local` for `t`) moved from BEFORE the end-expr
lower to AFTER it (`sf/src/lower.zig:4821-4823` → 4818-4823). This eliminates the pending-scope window
entirely (no stack, no fresh/reuse selector, no boundary low-watermark — the operator-ruled design over
the patchy LIFO-stack; see task-PENDSCOPE-report.md). I-1 repro now emits `total + t` DIRECT capture use
(no `zT = t` load_local); the capture-less end-expr shape (`for (0..if (rt) 1 else 0) |t|`) is fixed too.
for-slice captures (`:4891/:4892`) untouched. Byte-neutral for the 4 gates (gol/lisp/mud have no
for-loops; json uses only for-slice) — no re-baseline. **I-1 CLOSED.**

### Corpus (329 dirs): `OK=319 / FAIL=0 / ICE=0 / CRASH=0 / green-guards=10` (319+0+0+0+10=329)

Corpus grew 328→329 (+1: this plan's R fixture `emission_assoc_chain_xmod`, 40485a1d — classifies
**OK**, 4 `.c`, gcc clean). Full sweep (per-dir dump + per-file `gcc -c`) classifies OK=319, FAIL=0,
ICE=0, CRASH=0; the 10 green-guards UNCHANGED (`eu_assign_incompat_payload` / `euvoid_val_catch` /
`field_access_optional` / `var_declared_void` error[3000]; `parsergap_slice_expr_xmod` /
`strictzig_brace_if_xmod` / `parsergap_selfblok_xmod` / `parsergap_strict_comma_xmod` error[2000];
`self_embed_optional_cycle` error[24]; `emission_pal_xmod` error[20]). **No new FAIL/ICE/CRASH vs the
328-dir baseline.**

### 21-example matrix + 4 MD5 gates

21-example matrix **21/21** dump/gcc/link rc=0. 4 MD5 gates byte-identical (repo-root CWD): gol
`eed963e0640a073ed4eebb292f136e05` / lisp `c3c5847798e4553b2e34950e085bb6c6` / json
`089e4f046464ce3882aa2b2c4e585013` / mud `a1d0dd55aada9c3fd904ae33f54de32e`.

### Self-compile re-count + self-compiled binary

`/tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/gf_sc sf/src/main.zig` → **rc=0, 40
`.c`, 0 `error[`, 0 PANIC**. Self-compiled `/tmp/zig1_5/zig1_5_clean` (rebuilt via
`scripts/self_compile/build_zig1_5.sh`): R-ASSOC fixture `emission_assoc_chain_xmod` → dump/gcc/link/run
rc=0 prints **`3 5 0 6 24 55 321`** (matches reference — the self-emission fidelity gap is closed); real
std-importing program `emission_lower_crash_xmod` → dump/link/run rc=0 prints **3**.

### Milestone statement

Residual R-1 (self-emission operator-associativity gap) + residual I-1 (`pending_scope` nest-safety)
BOTH CLOSED. Self-compiled zig1_5 now parses left-assoc chains correctly and runs std-importing programs
rc=0. 4 MD5 gates byte-identical (no re-baseline). 21-example matrix 21/21. Corpus 329 dirs `OK=319 /
FAIL=0 / ICE=0 / CRASH=0 / GREEN=10`. No residual remains from the assoc-chain / pending_scope plan.

## GATE — labeled-block break + self-compiled lowering crash plan, FINAL sweep + reconciliation (2026-08-26)

Final gate sweep of the labeled-break + self-compile crash plan
(docs/superpowers/plans/2026-08-25-labeled-break-and-selfcompile-crash-plan.md, AMENDMENTs 1-3),
at HEAD `a7a207f7`, measured with `/tmp/fx_subfolder/zig1` (rebuilt at the last sf/src code
commit `a7a207f7`; canonical std reinstalled at `/tmp/fx_subfolder/lib/`). Docs-only task — no
`sf/src`, fixture, or script change in this gate. **This is the plan-complete closeout: the
labeled-block break (Phase A) and the self-compiled lowering crash (Phase B) are both CLOSED.**

### Phase A — labeled-block break (A2 F-LABELBREAK `ee092e3b` + docs `e18a424f`)

`break :blk` on a labeled block now resolves to a block-exit jump instead of being silently dropped.
Mechanism (A1a per AMENDMENT 1): `LoopInfo` gains `is_loop: u8`; `labeled_stmt` with a block body
creates an exit BB and pushes a breakable loop_stack entry (`is_loop=0`); `break` resolves the
labeled entry → jump to the block exit; `continue` skips `is_loop==0` entries in both the
unlabeled-innermost and the labeled scans. Fixture `emission_labeled_ctrl_xmod` prints
`3\n6\n10\n1` (the literal shape-A `blk: { var a = 1; break :blk; a = 2; }` now prints `1`).
`emission_orelse_labeled_xmod` + `emission_catch_labeled_xmod` still RUN correctly (prints `0` / `7`);
their emitted bytes gained a dead orphan `z_bb_N` block — the ACCEPTED AMENDMENT-1 dead-code
emission (runtime-identical, re-baseline-default, NOT a gate violation).

### Phase B — self-compiled lowering crash (B3a F2 `ea6882ac` + B3b F1 `a7a207f7`)

The self-compiled zig1_5 SEGV (F2, the crash) and the latent stale-sibling-capture (F1) are CLOSED
(AMENDMENT 2 split, operator-ruled B3a-then-B3b):
- **F2 (crash driver, c89_emit) — B3a F-EMITMAP `ea6882ac`:** the `fl_temps`/`fl_name_ids`
  temp→name map is now growable (was fixed `[128]`), both 128-caps dropped, and the name-dedup
  removed so each `decl_local` registers its OWN temp→name entry (capture shadowing). Self-compiled
  zig1_5 now runs the B1 fixture `emission_lower_crash_xmod` rc=0 (prints 3); reference rc=0.
  **F2 crash CLOSED.**
- **F1 (latent, lower) — B3b F-SCOPERES `a7a207f7`:** architectural lexical scope chain
  (parent-pointer scope nodes); one shared resolver walks the enclosing-scope chain innermost-first,
  replacing BOTH the LDS forward-scan max-scope loop (`lower.zig:2288-2317`) and the `findLocalTemp`
  backward-scan (`:1309-1317`); re-captured names resolve to the lexically-enclosing binding.
  **F1 CLOSED.**

### gol/lisp MD5 re-baseline (AMENDMENT 3, operator ruling A — AUTHORITATIVE)

The pin-mandated fl_temps dedup-removal necessarily changes emitted bytes for any function that
re-declares a name (gol `main` re-declares `var x` in two sibling while-loops; lisp re-uses capture
names). Per operator ruling A, **gol + lisp are RE-BASELINED** (runtime-identical verified: gol
glider grid + lisp REPL outputs diff-clean pristine-vs-candidate, both rc=0). New authoritative
hashes: gol `eed963e0640a073ed4eebb292f136e05` (old `4afb203f…`), lisp
`c3c5847798e4553b2e34950e085bb6c6` (old `5f886646…`). json `089e4f04…` + mud `a1d0dd55…`
UNCHANGED. The MD5 table in docs/sf/QUICK_REF.md carries the re-baseline note.

### Corpus (328 dirs): `OK=318 / FAIL=0 / ICE=0 / CRASH=0 / green-guards=10` (318+0+0+0+10=328)

Corpus grew 323→328 (+5): `emission_enum_switch_xmod` (b9bc3f1d) + `emission_enum_ext_xmod`
(f83912f6) + `emission_tu_switch_xmod` (ba3f0f70) + `emission_labeled_ctrl_xmod` (ac0b7e43) [prior
enum-switch/labeled fidelity-gap plan] + `emission_lower_crash_xmod` (22e0bc6f, this plan's B1).
Full sweep (per-dir dump + per-file `gcc -c`, `/tmp/fx_subfolder/zig1`) classifies **OK=318,
FAIL=0, ICE=0, CRASH=0**; the 10 green-guards unchanged (`eu_assign_incompat_payload` /
`euvoid_val_catch` / `field_access_optional` / `var_declared_void` / `parsergap_slice_expr_xmod`
error[3000]; `strictzig_brace_if_xmod` / `parsergap_selfblok_xmod` / `parsergap_strict_comma_xmod`
error[2000]; `self_embed_optional_cycle` error[24]; `emission_pal_xmod` error[20]). All 5 new dirs
classify OK. **No regression.**

### 21-example matrix + 4 MD5 gates

21-example matrix **21/21** dump/gcc/link rc=0. 4 MD5 gates byte-identical at the AMENDMENT-3
hashes (repo-root CWD): gol `eed963e0640a073ed4eebb292f136e05` / lisp
`c3c5847798e4553b2e34950e085bb6c6` / json `089e4f046464ce3882aa2b2c4e585013` / mud
`a1d0dd55aada9c3fd904ae33f54de32e`.

### Self-compile re-count + self-compiled binary

`bash scripts/self_compile/build_zig1_5.sh` → dump rc=0, 40 `.c`, in-script gcc -c clean;
independent re-count (`cd /tmp/zig1_5/gen && gcc -c *.c`) → **0 `: error:` lines, 40 files**.
Self-compiled `/tmp/zig1_5/zig1_5_clean` runs the B1 fixture `emission_lower_crash_xmod` rc=0
(prints 3, main_3DF5832C.c byte-identical to reference) AND the std-importing real program
`days_in_month` rc=0 with output BYTE-IDENTICAL to reference (all 12 month-day counts). `fibonacci`
runs rc=0 (output differs — see residual R-1).

### Deferred residuals (recorded, NOT fixed — do not regress-gate on these)

1. **Self-emission operator-associativity gap (R-1 — pre-existing, newly observable):** the
   self-compiled zig1_5 mis-parses SAME-PRECEDENCE left-associative operator chains — `a - b - c` →
   `a - (b - c)`, `a - b + c` → `a - (b + c)`, `a / b / c` → `a / (b / c)` — i.e. every binary op
   behaves right-associative for the second operator's RHS (self-emission defect; likely
   `OpInfo.right_assoc` mis-read, mechanism not fully traced — out of scope). Impact: any program
   compiled BY the self-compiled binary that uses a same-precedence chain mis-computes; concretely
   breaks `printInt`'s digit reversal (`std_io.zig:48` `out[pos] = tmp[len - 1 - k]`), so
   self-compiled-emitted binaries print wrong multi-digit integers via `printInt` (fibonacci prints
   `5\0` not `55`, rc=0). **Pre-existing, NOT this plan's regression:** the self-compile emission
   is byte-identical between pre-B3 HEAD `ee092e3b` and current `a7a207f7` (all 40 emitted modules
   diff-clean — A2/B3a/B3b did not change it); the defect was masked until the B3a crash fix let the
   self-compiled binary actually run std-importing programs. Same deferred class as the documented
   self-emission fidelity gap. Programs without same-precedence chains (B1 fixture `1 + 2`,
   `days_in_month` print-`{}` path) run byte-correct. Requires its own R/I/F plan.
2. **`pending_scope` single-slot non-nest-safety (I-1, B3b review IMPORTANT — documented, NOT
   fixed):** `pending_scope` in lower.zig is a single slot, not nest-safe. A capture inside a
   for-range END expr (`for (0..if (rt) |x| x else 0) |t|`) reuses + consumes the loop capture's
   pending scope, orphaning `t` from the scope chain — the resolver falls through to a raw
   `load_local`. Runtime stays CORRECT (emitted `zT = t; total + zT` vs control `total + t`); no
   gate/corpus fixture triggers it. A naive reorder of the pending-scope sites risks MD5
   temp-ordering — recorded for a follow-up F-task, NOT fixed.

### Milestone statement

Phase A (labeled-block break) + Phase B (self-compiled lowering crash) CLOSED. F2 crash CLOSED
(self-compiled zig1_5 runs the B1 fixture rc=0, prints 3). F1 scope-chain CLOSED. gol/lisp MD5
RE-BASELINED per AMENDMENT 3. Self-compile gcc-CLEAN (0 errors); the self-compiled binary RUNS
std-importing programs rc=0. 21-example matrix 21/21. Corpus 328 dirs `OK=318 / FAIL=0 / ICE=0 /
CRASH=0 / GREEN=10`. Residuals: R-1 self-emission associativity gap + I-1 `pending_scope`
nest-safety (both pre-existing / documented, NOT fixed).

## GATE — out-of-scope residual closeout, FINAL sweep + reconciliation (2026-08-25)

Final gate sweep of the out-of-scope residual closeout plan
(docs/superpowers/plans/2026-08-24-out-of-scope-residual-closeout-plan.md, AMENDMENTs 1-6),
at HEAD `ec306847`, measured with `/tmp/fx_subfolder/zig1` (rebuilt at the last sf/src code
commit `a9ea91f0`; canonical std reinstalled at `/tmp/fx_subfolder/lib/`). Docs-only task —
no `sf/src`, fixture, or script change in this gate. **This is the plan-complete closeout:
the entire FAIL=9 residual set is closed (FAIL → OK or → green-guard), FAIL 9→0, CRASH 1→0.**

### Corpus (323 dirs): `OK=313 / FAIL=0 / ICE=0 / CRASH=0 / green-guards=10` (313+0+0+0+10=323)

Corpus grew 322→323 (+1: the R-OPTFPTR fixture `emission_opt_fptr_wrap_xmod`). Full sweep
(per-dir dump + per-file `gcc -c`) classifies OK=313, FAIL=0, ICE=0, CRASH=0; the 10
green-guards = 5 auto-detected error[3000] rejections + 5 manual clean-rejections
(error[2000]/[24]/[20], 0 `.c`, no ICE/crash) reclassified by oracle rulings. **Every
fixture that changed classification this plan:**

| fixture | old | new | mechanism / SHA |
|---|---|---|---|
| `plat_stubs_missing_xmod` | CRASH | **OK** | ASan SEGV gone — F-PLATSTUBS `7d1b512d` (kind-gated recursion, Option B) |
| `emission_orelse_labeled_xmod` | FAIL | **OK** | F-LABELED `2cbf1fd3` (labeled_stmt orelse RHS no first-param leak) |
| `emission_catch_labeled_xmod` | FAIL | **OK** | F-LABELED `2cbf1fd3` (labeled_stmt catch RHS) |
| `emission_opt_fptr_wrap_xmod` | — | **OK** | new fixture (R `70af559c`) — F-OPTFPTR `53b9f1b6` (optional fn-ptr wrap) |
| `parsergap_specifier_xmod` | FAIL | **OK** | F-SPECIFIER `a9ea91f0` ({x} = lowercase hex, no prefix) |
| `field_store_drop` | FAIL | **OK** | fixture corrected `3ef2e8c8` (canonical `pal.zig` import + `std.io.printInt`; temp-0 sentinel superseded — Task 5.5 code fix MOOT) |
| `strictzig_brace_if_xmod` | FAIL | **GREEN** | brace-less `if;else` correct rejection (oracle); green-guard |
| `parsergap_selfblok_xmod` | FAIL | **GREEN** | brace-less `if;else` correct rejection (oracle); green-guard |
| `parsergap_strict_comma_xmod` | FAIL | **GREEN** | missing call-arg comma clean `error[2000]` (oracle); green-guard |
| `parsergap_slice_expr_xmod` | FAIL | **GREEN** | scalar-base slice clean reject `error[2000]`, no `error[3043]` ICE; green-guard |
| `self_embed_optional_cycle` | FAIL | **GREEN** | `error[24]` circular-type is CORRECT per AMENDMENT 6 (real Zig rejects `?X` value self-reference); green-guard |
| `emission_pal_xmod` | GREEN | **GREEN** | unchanged (pal green-guard, `error[20]`) |

Green-guard set (10) = `eu_assign_incompat_payload`, `euvoid_val_catch`,
`field_access_optional`, `var_declared_void` (error[3000]) + `parsergap_slice_expr_xmod`
(error[3000]) + `strictzig_brace_if_xmod`, `parsergap_selfblok_xmod`,
`parsergap_strict_comma_xmod` (error[2000]) + `self_embed_optional_cycle` (error[24]) +
`emission_pal_xmod` (error[20]).

### Oracle rulings (authoritative, recorded this plan)

- **`{x}` format specifier** = lowercase hex, no `0x` prefix (langref `0x{x}`). Z98
  `std.io.print("{x}\n", .{65})` prints **`41`** (F-SPECIFIER `a9ea91f0`; run-verified).
- **Brace-less `if (cond) stmt; else stmt;`** is correctly REJECTED (real-Zig grammar takes
  the `SEMICOLON` first → dangling `else`). The fix was migrating the 3 sf/src sites
  (type_resolver.zig:980-981/:987-990, diagnostics.zig:295-296) to braced form
  (F-BRACEMIG `22006588`); the fixtures are green-guards, not leniency.
- **`?*X` optional-POINTER** is the real-Zig self-reference pattern (pointer-sized, null=0;
  langref linked-list `prev: ?*Node, next: ?*Node`). Optional **VALUE** `?X` embeds by value →
  infinite-size → real Zig rejects. Z98's `error[24]` for `next: ?X` is therefore CORRECT
  (AMENDMENT 6, `ec306847`). Open question (not a blocker): whether Z98 supports `?*X`
  optional-pointer self-reference.

### json gate re-baseline (AMENDMENT 4, authoritative)

`d31e43b1…` → **`089e4f046464ce3882aa2b2c4e585013`** — the NULLWRAP fix (F-NULLWRAP
`a6fe169b`: optional-wrapped extern-call results emit `has_value = result != 0`) changes
json_parser's emitted C (same latent `fopen ?*File` NULL bug repaired). Runtime-identical on
every normal path (fopen succeeds → has_value=1 either way), repairs the NULL path (orelse
now fires). gol/lisp/mud byte-identical. **`089e4f04…` is the json hash for all future gates.**

### Deferred residuals (recorded, NOT fixed — do not regress-gate on these)

1. **Self-emission fidelity gap:** the self-compiled binary RUNS crash-free but misparses
   basic operators (`1 + 1`, `y = 5`, `x.len`, `y == 0`) → mass `error[2000]` self-dumping
   `sf/src/main.zig` (proven independent of NULLWRAP: parser.c/lexer.c/token.c/ast.c
   byte-identical pre/post). Requires its own dedicated R/I/F plan.
2. **`?*X` optional-pointer self-reference support:** open question, not a blocker.

### Milestone statement

Self-compile: **gcc-CLEAN AND LINK-green AND self-compiled binary RUNS crash-free** —
`bash scripts/self_compile/build_zig1_5.sh` → dump rc=0, 40 `.c`, in-script `gcc -c` clean
(0 `: error:` lines), BOTH `zig1_5_clean` + `zig1_5_asan` link rc=0 (c_exit linked via
`aa552f5d`), and the self-compiled binary runs on real input (crash-free rc=2 = the
misparse of the deferred self-emission gap, NOT a regression). `test_analyzer_bin` PASS
(rc=0, "Analyzer tests passed."). 21-example matrix **21/21** dump/gcc/link rc=0.
4 MD5 gates byte-identical: gol `4afb203f…`, lisp `5f886646…` (repo-root CWD), json
`089e4f04…`, mud `a1d0dd55…`.

## GATE — self-compile residual closeout R2/R1, final sweep + reconciliation (2026-08-24)

Final gate sweep of the self-compile closeout plan
(docs/superpowers/plans/2026-08-23-self-compile-closeout-r2r1-plan.md). Docs-only task — no
`sf/src` changes (all fixes landed in the plan's prior F tasks). All gates re-verified with
`/tmp/fx_subfolder/zig1` (rebuilt by F-ACOPY at HEAD `0af060d8`, canonical std reinstalled at
`/tmp/fx_subfolder/lib/`), under the operator ruling **AMENDMENT 5** (`935374d9`) — record
`plat_stubs_missing_xmod` truthfully, no new fix task:

- **4 residual fixes landed (all controller-verified this plan):**
  - **F-R2** (`143766e2`) — array-`.len` emits VOID instead of a bogus `unsigned int` value
    (the R2 `zT_<n> undeclared` ×6 class).
  - **F-ORELSEBLK** (`7a7f5928`) — orelse-block terminator fixed (the R2 orelse-block ×5
    class). Fix A (labeled-stmt orelse/catch RHS → block_terminated guard) did NOT close
    `emission_orelse_labeled_xmod` / `emission_catch_labeled_xmod` — recorded truthfully below.
  - **F-R1** (`a8ec24f7`) — R1 `Opt_10` incompatible-assign closed (×1).
  - **F-ACOPY** (`0af060d8`) — array-copy direct assign emits no bogus `dst = src` (the
    AMENDMENT-1 array-copy live RED; `emission_misc_xmod` residual now GREEN).
- **MAJOR MILESTONE — self-compile gcc-CLEAN (12→0):** `bash scripts/self_compile/build_zig1_5.sh`
  → dump rc=0, 40 `.c` emitted, in-script gcc -c clean (warnings only). Independent re-count:
  `cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
  -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c
  2>/tmp/emit_errs_final.txt` → gcc rc=0, **0 `: error:` lines, 40 files**. The 12 residuals
  (R2 array-`.len`→VOID ×6, orelse-block terminator ×5, R1 Opt_10 ×1) are all closed. The
  script's final LINK still fails `undefined reference to 'c_exit'` — the documented
  pre-existing out-of-scope issue (build_zig1_5.sh never links `sf/src/c_exit.c`; the gcc -c
  re-count gate is the authority for the milestone).
- **Corpus (322 dirs): `OK=307 / FAIL=9 / CRASH=1 / ICE=0 / green-guards=5`** (307+9+1+5=322).
  Corpus grew 310→322 (+10 A-ADD `emission_*_xmod` dirs + the 2 R-task dirs
  `emission_temp_index_drift_xmod` [F-R2] + `emission_opt10_assign_xmod` [F-R1]). **Documented
  FAIL=7 set unchanged** (byte-identical to the v45 baseline): `field_store_drop` (error[3048]) +
  `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) +
  `parsergap_slice_expr_xmod` (error[2000]+[3000], clean-reject) + `parsergap_specifier_xmod`
  (error[3013]) + `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod`
  (M1 hard-RED fixture, FAIL **by design**).
- **FAIL +2 (A-ADD live-RED labeled shapes — recorded truthfully, out of this plan's fix
  scope):** `emission_orelse_labeled_xmod` + `emission_catch_labeled_xmod` (the po1/pco1
  labeled-stmt classes) remain RED: gcc rc=1 `error: incompatible types when assigning to type
  'int' from type 'zT_…_Slice_zT_…_u'` at `zT_6 = prefix;` / `zT_4 = prefix;`. F-ORELSEBLK's
  Fix A did NOT close them — separate live bugs, documented as out-of-scope.
- **Green-guards = 5** = documented 4 (`eu_assign_incompat_payload` / `euvoid_val_catch` /
  `field_access_optional` / `var_declared_void`, all error[3000], 0 `.c`) + **`emission_pal_xmod`
  (error[20] reject = pal green-guard per AMENDMENT 1)**.
- **CRASH = 1 — `plat_stubs_missing_xmod` (PRE-EXISTING CRASH — mis-recorded previously, now
  corrected):** ASan SEGV in `resolveStmtTypes` (front_resolution.zig:131), 0 `.c`, dump rc=1.
  Bisected NOT caused by this plan (crashes at plan-start HEAD `b9256f2e`; last-known-good ~Aug 18
  `f4_fix_zig1`; suspected window = the silent-drop u32-widening `378c71fa`/`50ebbf82`,
  unverified). Every prior gate sweep (voiddecl/widthbits/residual/GATE-CLOSE) mis-recorded it as
  OK — the sweeps' "identical rc+stderr" comparisons masked a crash present in both reference and
  new compilers. **Operator ruling (AMENDMENT 5, `935374d9`): record truthfully, no new fix task.**
- **21-example matrix: 21/21 dump/gcc/link rc=0** (PASS=21, FAIL=0; 17 via main.zig + 4
  single-file func_ptr_return/mandelbrot/quicksort/sort_strings). Runs: json_parser parses
  test.json rc=0 from its dir; game_of_life renders the glider grid rc=0; rogue_mud boots
  "Welcome to Rogue MUD!" rc=0; mud_server "MUD server listening on port 4000" (timeout-gated
  server).
- **4 MD5 gates byte-identical (no re-baseline):** gol `4afb203f…` + lisp `5f886646…`
  (repo-root CWD) + json `d31e43b1…` + mud `a1d0dd55…` — all 4 match the v45 values.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).

## GATE — self-compile 194-error plan closeout, final sweep + reconciliation (2026-08-24)

Final gate sweep of the self-compile 194-error plan
(docs/superpowers/plans/2026-08-22-self-compile-194-closeout-plan.md). Docs-only task — no
`sf/src` changes (all fixes landed in the plan's prior F tasks). Self-compile re-count is
observational only (soft gate) — per-F fixture GREEN (gcc -c rc=0) was the hard gate;
runtime-identity governs:

- **5 fixes landed + AMENDMENTs 4/5 (all controller-verified this plan):**
  - **F-MIGRATE** (`1a06716b` + `df9c3017`) — bare `pal` → `pal_mod` migration (spec-compliant
    module alias) + undeclared-identifier diagnostic instead of silent VOID emission (`pal`
    class ×5 → 0).
  - **F-A** (`6b44d7a3`) — LirInst tag-emission emits the variant's declared tag constant
    (`incompatible types when assigning` class, 48 errors).
  - **F-B** (`6d4892bf` + `56a80136`) — hoisted-local disambiguation by type (name-keyed
    conflation; 108 errors).
  - **F-ORELSE** (`f8e3d914`) — orelse return/continue emits the orelse value, not the first
    param (6 errors).
  - **F-C** (`cb378f17`) — no-member + misc emission classes (8 + 5 errors).
  - AMENDMENTs 4 (`f5ab3bc3`, slice-argv main support) + 5 (`05ea274d`, canonical many-pointer
    main + fixture fix) — docs commits.
- **Self-compile residual state (194-plan FINAL):** NOT buildable. `timeout 120
  /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig` →
  **12 remaining gcc errors** = **R2 `zT_<n>` undeclared ×11 + R1 `Opt_10` assign ×1**
  (11+1=12) — the 194-plan's residual, deferred to the R2/R1 implementation plan →
  **FORWARD: docs/superpowers/plans/2026-08-23-self-compile-closeout-r2r1-plan.md.**
- **Corpus (310 dirs):** 303 → 310 (+7 emission-fixture dirs from this plan's R tasks:
  `emission_assign_xmod`, `emission_zT_undeclared_xmod`, `emission_request_member_xmod`,
  `emission_no_member_xmod`, `emission_pal_xmod`, `emission_misc_xmod`, `emission_orelse_xmod`).
- **4 MD5 gates:** json **`9720478c…` → `d31e43b19f752e40b9fd4b8885b13600` RE-BASELINED**
  (operator-approved during F-ORELSE — runtime-identical; the orelse fix repairs the
  semantically-broken null path); gol `4afb203f…` + lisp `5f886646…` (repo-root CWD) + mud
  `a1d0dd55…` unchanged.

## GATE — self-compile residual closeout, final sweep + reconciliation (2026-08-22)

Final gate sweep of the self-compile residual closeout plan
(docs/superpowers/plans/2026-08-20-self-compile-residual-closeout-plan.md, AMENDMENT 12
re-scope). Docs-only task — no `sf/src` changes (all fixes landed in the plan's prior F
tasks). All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt at HEAD `b9256f2e`,
canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **4 residual fixes landed (all controller-verified this plan):**
  - **F-C3-tighten** (`6534a65b`) — `local_decl_is_capture` flag gates the var-decl rename;
    `json_parser_workaround` stdout BYTE-IDENTICAL to base (md5 `dc22fa473650bd3dcdf4d8a1559a260b`);
    RV 21/21 runtime-identical.
  - **F-A2EXT** (`b019c671`) — Option A `ts_ref_set` owner-module type-storage defs/externs;
    self-compile `zG_` **9→0**.
  - **F-E2DOWN** (`9e00bec7`) — void-payload union-literal store guard (`lower.zig:3757`);
    self-compile `TokenValue has no member 'none'` **62→0**.
  - **F-SWITCH** (`b9256f2e`) — switch-on-plain-enum case values now correct (`case 0/1/2`;
    `enum_value_table` no longer resolves cross-module enum literals against a wrong, larger
    enum's field list). Fixture `emission_type_storage_extern_xmod` prints **3**
    (`case 0/1/2`), `emission_mangler_collision_xmod` prints **4** (NOTES corrected 3→4,
    doc error).
- **Self-compile residual state (AMENDMENT 12 — terminal gate re-scoped):** NOT buildable.
  `timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89 --output-dir /tmp/sc
  sf/src/main.zig` → **194 remaining gcc errors** (`incompatible types when assigning` ×86
  enum-temp-typed-as-`unsigned int`, `zT_<n> undeclared` ×68, `request for member` ×22,
  `has no member` ×8, `pal` ×5, misc ×5) = **deferred NEW residual classes** (out of this
  plan's scope, recorded for a future plan). Scoped gates HOLD: `zG_` re-count **0**,
  `TokenValue.none` **0**, `json_parser_workaround` runtime-correct. This plan's success =
  the 4 scoped fixes landed + all gates run + docs reconciled.
- **Corpus (303 dirs): `OK=292 / FAIL=7 / ICE=0 / CRASH=0 / green-guards=4`** (292+7+4=303).
  Corpus grew 287→303 (+16 emission-fixture dirs from this plan's R tasks — all 16 classify
  **OK**; the plan's R fixtures `emission_type_storage_extern_xmod`, `emission_sibling_payload_scale_xmod`,
  `emission_void_temp_scale_xmod` + the AMENDMENT 7/8 variation fixtures + the Task D legacy
  fixtures `emission_mangler_collision_xmod` etc., all RED→OK). **FAIL=7 set unchanged**
  (byte-identical to the v43 baseline): `field_store_drop` (error[3048]) +
  `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) +
  `parsergap_slice_expr_xmod` (error[2000]+[3000], clean-reject) + `parsergap_specifier_xmod`
  (error[3013]) + `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod`
  (M1 hard-RED fixture, FAIL **by design**). Green-guards unchanged
  (`eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` /
  `var_declared_void`). **No regression.**
- **21-example matrix: 21/21 dump/gcc/link rc=0** (PASS=21, FAIL=0; 17 via main.zig + 4
  single-file func_ptr_return/mandelbrot/quicksort/sort_strings). Runs: json_parser parses
  test.json rc=0 (CWD-sensitive — from its dir); game_of_life + mud_server + rogue_mud
  timeout-gated rc=124 with correct output (boots "Welcome to Rogue MUD!", "MUD server
  listening on port 4000") — counted PASS.
- **4 MD5 gates (2 RE-BASELINED, 2 UNCHANGED — runtime-priority override):**
  - gol **`9cf758d9…` → `4afb203fdde7a880ec6e7aed32543691`** RE-BASELINED — the documented
    baseline predated the F-attempt emission changes (this plan's F tasks); current HEAD
    emits `4afb203f…` (matches the AMENDMENT 12 controller-verified value). Runtime-identity
    justification: gol renders the glider grid rc=0 (md5 `40cfee96…` for 100 gen), corpus
    classification unchanged — per the operator's runtime-priority rule the runtime is the
    gate, not byte-identity.
  - lisp **`88dcb7f9…` → `5f886646b164a70c52bf042eb54bda78`** (repo-root CWD) RE-BASELINED —
    the gate-documented v43 value `88dcb7f9…` predates the F-attempt emission changes (the
    residual plan's Global Constraints carried an intermediate AMENDMENT-5 value `851c9ed3…`,
    now superseded); runtime-identity justification: REPL evaluates `(+ 1 2)`→3 /
    `(define x 10)` / `(+ x 5)`→15 / `(car (quote (5 6)))`→5 rc=0.
  - json `9720478c937409a29fe23ae0199821cf` — **UNCHANGED** (matches).
  - mud `a1d0dd55aada9c3fd904ae33f54de32e` — **UNCHANGED** (matches).
  Historical gol `9cf758d9…` / lisp `88dcb7f9…` refs below carry the `[→ 4afb203f…]` /
  `[→ 5f886646…]` forward-pointer.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).

## GATE — voiddecl-family plan closeout, final sweep + reconciliation (2026-08-20)

Final gate sweep of the voiddecl-family plan (docs/superpowers/plans/2026-08-18-voiddecl-family-plan.md,
GATE task lines 351-357, re-amended at :459/:481). Docs-only task — no `sf/src` changes (all fixes
landed in the plan's prior F tasks). All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt
2026-08-20 at HEAD `df82d010`, canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **VOID-decl family FULLY FIXED** — the 9 self-compile `error[3000] cannot-declare-variable-of-type-void`
  sites (main.zig:588, symbol_registrator:258/:357, lower.zig:4410/:5218/:5275/:5319/:5395/:5403):
  - **Root 1 — untyped module-level const/var collapse, FIXED by F1 (`27c71619`):** dedicated
    front-resolution pass (own file, I-FRONTRES design) resolving every module-level `var_decl` init
    type via the semantic-analyzer resolver, writing `sym.type_id` + `nameCachePut`, order-independent
    fixpoint; the leaking `main.zig:448-455` nameCachePut block + `resolveStmtTypes` moved INTO the pass.
  - **Root 2 — tagged-union `.tag` discriminator gap, FIXED by F2 (`660ff8e2`):**
    `resolveFieldAccess` tagged_union_type branch (`semantic_analyzer.zig:473-476`/`:570-591`) now
    returns `tp.tag_type` when `field_name_id == interner("tag")`.
  - Self-compile `error[3000]`: **9 → 0** (this gate: 0 non-9999 error[3000]).
- **F-ICE (`fd56da3b`) — slice_expr ICE `error[3043]` → 0 whole-tree:** 3-loci fix (zero-length array
  `type_resolver.zig:1002`; array-init element resolution `semantic_analyzer.zig:2120-2124`; sentinel
  collision `lower.zig:3907` `TYPE_UNDEFINED`→`TEMP_NONE`) **+ Fix A** (`semantic_analyzer.zig:2115-2141`
  array-init full child resolution) **+ Fix B** (`:841-852` FN3 fn-call arg resolution) — **ratified via
  AMENDMENT 5** (operator ruling 2026-08-19; Fix A/B exceeded the brief's 3 loci to satisfy the
  `error[3043]→0` gate). `parsergap_zeroarr_slice_xmod` RED→GREEN (runs rc=0, prints `0`).
- **F-REJECT (`838935ce`) — scalar-base slice clean reject:** sema `semanticAnalyzerResolveSliceExpr`
  base-is-sliceable check (array/slice/many-ptr allowed; scalar → proper diagnostic). R-ICE fixture
  `parsergap_slice_expr_xmod`: `rc=3 ICE` → `rc=2 error[2000]` (`cannot slice base type: expected array,
  slice, or many-pointer`), 0 `.c`, no `internal:` message.
- **R/I/F-PAYLOAD (`19d919bd`) — tagged-union `.payload` accessor (2-locus, AMENDMENT 6 ruling
  2026-08-20):** Locus 1 sema `semantic_analyzer.zig` tagged_union branch (after the `.tag` block,
  before the fields read — first non-void variant field type, mirroring the `:583-586` array→ptr
  conversion); Locus 2 lower `lower.zig:2450-2461` value path (load_field `TU_FIELD_PAYLOAD`, symmetric
  to the existing store mapping `:1018-1029`). `voiddecl_payload_xmod` RED→OK (compile gate: dump rc=0,
  gcc rc=0, runs rc=0; fixture uses `undefined` so runtime prints are NOT the gate).
- **Corpus (286 dirs): `OK=275 / FAIL=7 / ICE=0 / CRASH=0 / green-guards=4`** (275+7+4=286). Corpus grew
  277→286 (+9 dirs this plan: `parsergap_slice_expr_xmod`, `parsergap_zeroarr_slice_xmod`,
  `voiddecl_ifexpr_xmod` + `voiddecl_ifexpr_ctl_xmod` (R1 two-fixture), `voiddecl_switchexpr_xmod`,
  `voiddecl_u64cast_xmod`, `voiddecl_xmodtype_xmod`, `voiddecl_tagprobe_xmod`, `voiddecl_payload_xmod`).
  FAIL=7 = `field_store_drop` (error[3048]) + `self_embed_optional_cycle` (error[24]) +
  `parsergap_selfblok_xmod` (error[2000]) + `parsergap_specifier_xmod` (error[3013]) +
  `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL
  **by design**) + `parsergap_slice_expr_xmod` (**now clean-reject FAIL** — the F-REJECT ICE→FAIL flip,
  intended). Green-guards unchanged (`eu_assign_incompat_payload` / `euvoid_val_catch` /
  `field_access_optional` / `var_declared_void`). **No regression.**
- **21-example matrix: 21/21 dump/gcc/link rc=0** (PASS=21, FAIL=0; 17 via main.zig + 4 single-file
  func_ptr_return/mandelbrot/quicksort/sort_strings). Runs: json_parser parses test.json rc=0
  (CWD-sensitive — from its dir); game_of_life + mud_server + rogue_mud timeout-gated rc=124 with
  correct output — counted PASS.
- **4 MD5 gates:** gol `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22]
  (repo-root CWD — CWD-sensitive), mud `a1d0dd55aada9c3fd904ae33f54de32e` **byte-identical**; **json
  RE-BASELINED** `fc357296537347a0ef58af49b5a40081` → `9720478c937409a29fe23ae0199821cf` (AMENDMENT 3
  ruling 2026-08-19: the F1 front-resolution pass types json_parser's untyped module
  `var g_arena = std.arena.create(1048576)`, so 5 temp decls in emitted C change `unsigned int` →
  `Arena*`; runtime-identical — rc=0, byte-identical stdout — corpus classification unchanged).
  Historical json `fc357296…` refs carry the `[F1 re-baselined 2026-08-19 → 9720478c…]` forward-pointer.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).
- **Next blocker (recorded, NOT fixed):** PANIC `c89_emit.zig:5002` — `width_bits = @intCast(u8, size*8)`
  u8 overflow on a 40-byte tagged-union temp. Self-compile `timeout 120 zig1 --markers --dump-c89
  --output-dir /tmp/sc sf/src/main.zig` → rc=134 (`PANIC: integer cast overflow` at
  `/tmp/fx_subfolder/zig_runtime.h:154`; `STN:width_bits=zT_16/4528/4600` + `P1:t3254T94N5002` markers),
  with **error[3000]==0 AND error[3043]==0** (gate holds). Identical abort point to F-ICE/F-REJECT/
  F-PAYLOAD — the frontier of this plan, NOT fixed.
- **Documented latents (recorded, NOT fixed):** (1) **mixed-type-union `.payload` static-type dialect
  limitation** (AMENDMENT 6): `.payload`'s static type = first non-void variant field type
  (deterministic); on a MIXED-type union (`{a: u32, b: i64}`) the single static type is inherently
  arbitrary — a runtime active variant differing from the first non-void variant emits
  `.payload.<first>._0` reading the wrong width. 0 sites in sf/src. (2) **`.tag` read-load asymmetry**
  (AMENDMENT 6): F2 fixed `.tag` sema-only; bare `.tag` value-reads OUTSIDE a switch still no-load
  (pre-existing, disclosed in I-PAYLOAD §5, accepted by operator).

## GATE — widthbits-overflow plan closeout, final sweep + reconciliation (2026-08-20)

Final gate sweep of the widthbits-overflow plan (docs/superpowers/plans/2026-08-20-widthbits-overflow-plan.md,
STOP ruling 2026-08-20, AMENDMENT 2 `f3b0b916`). Docs-only task — no `sf/src` changes (the F1 fix landed in
the plan's prior task, commit `d5a966f7`). All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt
2026-08-20 at HEAD `d5a966f7`, canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **Width-bits mechanism (F1 `d5a966f7` — the LAST self-compile blocker, now FIXED):** the self-compile PANIC
  `c89_emit.zig:5002` was `width_bits = @intCast(u8, bty.size * @intCast(u32, 8))` — a u8 integer-cast
  overflow when emitting a `.int_const` for a >31-byte tagged-union temp (40 bytes: 40*8 = 320 > 255).
  **3-site class** (every `@intCast(u8, <size>*@intCast(u32, 8))` width computation): `c89_emit.zig:5002`
  (the `.int_const` PANIC locus), `c89_emit.zig:3190` (`emitSatBinary` — int-only operands, size ≤ 8,
  overflow-unreachable), and **`comptime_eval.zig:139` — the second LIVE site** (I-WIDTHBITS blast-radius
  correction; comptime-side `@intCast` fold reachable from a >31-byte non-int target). **Fix (Option B u32
  widening, per the STOP ruling):** `width_bits`/`wb` u8→u32 across the full enumerated surface — c89_emit.zig
  17 edit lines / 6 contiguous regions (`:3160/:3167/:3174/:3181` sat-helper params + their `@intCast(u8,…)`
  comparisons, `:3190/:4992/:5002` compute sites, `:3313/:3428` op-21/22 consumers, `:5020/:5028` `<64`
  guards; `:5024` keeps `sb: u8`), comptime_eval.zig 17 edit lines / 5 contiguous regions (`:16` field,
  `:56` `maxw`, the 8 literal constructions `:119/:128/:160/:173/:175/:177/:178/:196`, `:139` second live
  site, `:141/:144/:146/:183-188` consumers; `:203` pass-through untouched). **STOP-approved `>=`
  shift-guard hardening:** `comptime_eval.zig:141` and `:185` changed `wb == @intCast(u32, 64)` →
  `wb >= @intCast(u32, 64)` (eliminates synthetic-only u64 shift-by->63 UB on >31-byte non-int `@intCast`
  targets; behavior-identical for all int/char/bool targets). Shift-guard invariant preserved: every
  `1 << width_bits` is lexically inside the `is_signed != 0` block (`c89_emit.zig:5018`), tagged unions
  never set `is_signed`, so widths at any shift site stay ≤ 64 — widening introduces zero shift-UB.
  Whole-tree scan: **zero remaining `@intCast(u8, <size>*8)` width computations**; 61 `width_bits` hits
  confined to the 2 files; zero cross-file consumer of `ComptimeVal.width_bits`.
- **R1 fixture (`582bfc4e`, `widthbits_union_intconst_xmod`): RED→GREEN.** Pre-fix: `PANIC: integer cast
  overflow` (rc=134) at `zig_runtime.h:154` on the `.int_const` tag emission for a 40-byte tagged-union
  temp. Post-fix: dump rc=0, gcc rc=0, correct `.tag =` emission. Corpus 286→287 with the fixture counted;
  it now classifies **OK**.
- **Corpus (287 dirs): `OK=276 / FAIL=7 / ICE=0 / CRASH=0 / green-guards=4`** (276+7+4=287). Corpus grew
  286→287 (+1 dir this plan: the R1 fixture `widthbits_union_intconst_xmod`, RED→OK). **FAIL=7 set
  unchanged** (byte-identical to the v42 baseline): `field_store_drop` (error[3048]) +
  `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) +
  `parsergap_slice_expr_xmod` (error[2000]+[3000], clean-reject) + `parsergap_specifier_xmod` (error[3013]) +
  `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL **by
  design**). Green-guards unchanged (`eu_assign_incompat_payload` / `euvoid_val_catch` /
  `field_access_optional` / `var_declared_void`). **No regression.**
- **21-example matrix: 21/21 dump/gcc rc=0** (PASS=21, FAIL=0; 17 via main.zig + 4 single-file
  func_ptr_return/mandelbrot/quicksort/sort_strings).
- **4 MD5 gates byte-identical** (all MATCH the v42 baselines, no re-baseline this plan): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22] (repo-root CWD —
  CWD-sensitive), json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`.
  Byte-identity by construction: emitted width-dependent output runs only for int temps ≤ 64 bits; no
  gate/corpus/example uses a >31-byte tagged-union `.int_const`.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).
- **MAJOR MILESTONE — self-compile FULLY GREEN:** `timeout 120 /tmp/fx_subfolder/zig1 --markers --dump-c89
  --output-dir /tmp/sc sf/src/main.zig` → **rc=0, 40 `.c` emitted, zero `error[` non-9999, zero PANIC**. The
  widthbits fix was the **LAST self-compile blocker — next frontier blocker: NONE** (recorded explicitly;
  nothing invented). Informational only, NOT a blocker: the `--markers` emitted .c do not pass strict
  single-file `gcc -c` (`zT_68 undeclared`, `zF_..._main` arg-count mismatch) — a pre-existing `--markers`
  emission quirk unrelated to this widening; no gate requires gcc of self-compile output.

## GATE — self-compile silent-drop plan closeout (R-ladder + I-DROP + F1 u16→u32 sweep) (2026-08-19)

Final gate sweep of the self-compile silent-drop plan
(docs/superpowers/plans/2026-08-18-self-compile-silent-drop-plan.md). Docs-only task — no `sf/src`
changes (the F1 code fix landed in the plan's prior task, commits `378c71fa` + `50ebbf82`). All
gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt 2026-08-19 at HEAD `50ebbf82`, canonical
std reinstalled at `/tmp/fx_subfolder/lib/`):

- **R-ladder fixtures (6, all GREEN):** the plan's scale probes ruled out module-count / chain-depth /
  identifier-volume / tree-shape triggers — nothing below the 65,536-entry boundary trips:
  - `voiddecl_struct_xmod_r1` (`d1ad390b`) — sanity baseline: cross-module struct return at 2
    modules, GREEN.
  - `voiddecl_chain_r2` (`d3405b00`) — import-chain depth probe (N ∈ {5,10,20,40}), GREEN — depth
    alone does NOT trip.
  - `voiddecl_count_r3` (`f35e1835`) — sibling-module-count probe (N up to 39), GREEN — module count
    alone does NOT trip.
  - `voiddecl_volume_r4` (`3badc5cc`) — interned-identifier volume probe (up to 10k ids), GREEN —
    volume alone does NOT trip.
  - `voiddecl_nested_r5` (`44f7d210`) — nested import-tree probe (6 children × 4 grandchildren, 24
    leaf make()s), GREEN — tree shape does NOT trip.
  - `voiddecl_mimic_r6v2` (`7c61c462`) — self-hosting-shape mimic (39 modules), GREEN — shape+scale
    does NOT reconstruct the drop.
- **I-DROP mechanism (isolated — the true trigger, fixed by F1):** u32 span-start overflow in
  `astStoreAddExtraChildren` (`sf/src/ast.zig:424`). The module_root decl span is packed as
  `(start << 16) | count`; when `store.extra_children.len >= 65536` during self-compile, `start << 16`
  wraps to `start & 0xFFFF`, so every module parsed at/after the boundary decodes to the wrong
  (early) extra_children region and **silently registers 0 named types** (m1 = 0 symbols, m2-m4 =
  4/18/10 stray garbage `var_decl`s; `RN:` absent for all of m1-m4). Every cross-module ref to their
  types falls back to TYPE_VOID (`resolveFnSignatures`, type_resolver.zig:1214) → the 213×
  `error[3000]`. The trigger is **aggregate extra_children length**, not module count (sf/src modules
  are large). Isolated by instrumentation (task-I-DROP-report); NOT a registration skip, NOT OOM, NOT
  cyclic re-entrancy (CYE=0/CYF=0).
- **Two boundary repro fixtures (both now GREEN):**
  - `voiddecl_boundary_xmod` (`069b6b35`) — the silent-drop RED form: N=7 × 10k-const modules; the
    bare-`std` module (imported first, parsed last under the LIFO import queue) is silently dropped →
    dump/gcc/run rc=0 but EMPTY stdout (expected `1 7`). Post-F1 GREEN: run prints `1 7`.
  - `voiddecl_boundary_xmod_err` (`b4993838`) — the error[3000] RED form: same shape with m1 imported
    first (parsed last, start wrapped 65539→3) → `rc=2`, `error[3000]: cannot declare variable of type
    void` at `main.zig:10:4`, 0 `.c` emitted. Post-F1 GREEN: run prints `1`.
- **F1 whole-class sweep (the fix):** `AstNode.payload` u32→u64, encoding `(start << 32) | count`
  (decode `>> 32` / `& 0xFFFFFFFF`); every `*_start: u16` index into the two unbounded arrays
  (`ast.extra_children`, `type_registry.xt_items`/`xn_items`) widened to u32 — `*_count` stays u16.
  Commits `378c71fa` (type_registry path) + `50ebbf82` (extra_children path). **Commit order reversed
  from the plan staging** (type_registry landed first) — operator accepted.
- **New self-compile status:** `error[3000]` **213x → 9**; modules 1-4 now register cleanly
  (`RN:m1`/`RN:m2`/`RN:m3`/`RN:m4` markers present, `RN:m5n38` boundary control present). The 9
  residual `error[3000]` are the **same pre-existing VOID-decl family, newly reached** — recorded,
  **NOT fixed** (all `cannot declare variable of type void`). **Next blocker = the VOID-decl family
  (9 sites).**
- **Corpus (277 dirs): `OK=267 / FAIL=6 / ICE=0 / CRASH=0 / green-guards=4`** (267+6+4=277). Corpus
  grew 266→277: +3 signed wrap/sat emission probes (`sat_i64_mul` / `sat_signed_battery` /
  `wrap_signed_battery`, commit `13991817`, landed post-v40-gate) + the 6 R-ladder fixtures + the 2
  boundary repros — all 11 new dirs **OK**. FAIL=6 **unchanged** (byte-identical to the v40
  baseline): `field_store_drop` (error[3048]) + `self_embed_optional_cycle` (error[24]) +
  `parsergap_selfblok_xmod` (error[2000]) + `parsergap_specifier_xmod` (error[3013]) +
  `parsergap_strict_comma_xmod` (error[2000]) + `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL
  **by design**). Green-guards unchanged (`eu_assign_incompat_payload` / `euvoid_val_catch` /
  `field_access_optional` / `var_declared_void`). **No regression.**
- **21-example matrix: 21/21 dump/gcc/link rc=0** (PASS=21, FAIL=0). Runs: json_parser parses
  test.json rc=0 (CWD-sensitive — run from its dir); game_of_life prints the correct glider grid then
  loops on the missing `cls` — timeout-gated rc=124, counted PASS; mud_server rc=124 (timeout-gated
  server); rogue_mud boots + exits on `q` rc=0.
- **4 MD5 gates byte-identical** (all MATCH the v40 baselines, no re-baseline this plan): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22] (repo-root CWD —
  CWD-sensitive), json `fc357296537347a0ef58af49b5a40081` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).
- **Trigger isolation (recorded, NOT fixed):** the silent module 1-4 drop was the u16 span-start
  overflow (I-DROP mechanism above) — FIXED by F1. The newly-reached 9 `error[3000]` VOID-decl sites
  (main.zig:588, symbol_registrator:258/:357, lower.zig:4410/:5218/:5275/:5319/:5395/:5403) are the
  next genuine blocker — the same pre-existing VOID-decl family as the `var_declared_void`
  green-guard, **recorded, NOT fixed** (see the QUICK_REF baseline line).

## GATE — self-compile-gaps plan closeout (wrap/sat operators + multi-line string + switch-prong) (2026-08-18)

Final gate sweep of the self-compile-gaps plan (docs/superpowers/plans/2026-08-18-self-compile-gaps-plan.md).
Docs-only task — no `sf/src` changes. All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt
2026-08-18, canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **F tasks included in this closeout:**
  - F2 (`fdcf3b54`): multi-line string literal migration to escaped `\n` (c89_emit.zig:1881) —
    self-compile construct passes.
  - F1 (`9cb844b4` + `541092b4` + `10ba14e9`): full wrapping/saturating operator family
    (`+% -% *%` + prefix `-%` + `+%= -%= *%=` then `+| -| *| <<|` + `+|= -|= *|= <<|=`),
    signed+unsigned — `parsergap_wrap_arith_xmod` RED→OK, `hash.zig:18 *%` self-compile passes.
  - F3 (`3079df02`): value-less `return` in switch prongs (return-only per STOP ruling) —
    `parsergap_switch_comma_xmod` RED→OK, `lexer.zig` value-less-return site passes.
- **Corpus (266 dirs): `OK=256 / FAIL=6 / ICE=0 / CRASH=0 / green-guards=4`** (256+6+4=266). The
  FAIL=6 set is **unchanged** (byte-identical to the v39 baseline): `field_store_drop` (error[3048]) +
  `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) +
  `parsergap_specifier_xmod` (error[3013]) + `parsergap_strict_comma_xmod` (error[2000]) +
  `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL **by design**). Green-guards unchanged
  (`eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` / `var_declared_void`).
  Corpus grew 264→266 (this plan's R1 `parsergap_wrap_arith_xmod` + R3
  `parsergap_switch_comma_xmod`), **both RED→OK** — OK=254→256, FAIL=6 unmoved (R1/R3 were never
  part of the FAIL=6 baseline set). **No regression.**
- **21-example matrix: 21/21 dump/gcc/link rc=0.** Runs spot-checked: days_in_month rc=0 (all 12
  month-day counts); game_of_life 100 generations rc=0; rogue_mud boots "Welcome to Rogue MUD!" +
  exits on `q` rc=0; json_parser parses test.json rc=0 (CWD-sensitive — run from its dir).
- **4 MD5 gates byte-identical** (all MATCH the v39 baselines, no re-baseline this task): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22] (repo-root CWD —
  CWD-sensitive), json `fc357296537347a0ef58af49b5a40081` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **test_analyzer_bin PASS** (build_test.sh battery "5 passed, 4 failed" — unchanged baseline).
- **Self-compile re-check:** `zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig`
  (timeout 120, rc=2): all 3 plan constructs pass — 0 `util/hash.zig:18` `*%` hits, 0
  `c89_emit.zig:1881` hits, 0 `lexer.zig` value-less-return hits. **Remaining pre-existing blocker:**
  **210 `error[3000] cannot-declare-variable-of-type-void` sema errors** (the VOID-decl family —
  same class as the `var_declared_void` green-guard, but real gap in self-compile sources). The F3
  report's suspicion of a `lexer.zig slice_expr` error[3043] ICE is **NOT reproduced** — the filtered
  self-compile stderr shows 210× error[3000] and ZERO ICE-class errors. Recorded, NOT fixed.

## GATE — parser-gaps followup plan closeout + F6 json historical pointer (2026-08-18)

Final gate sweep of the parser-gaps followup plan (docs/superpowers/plans/2026-08-17-parser-gaps-followup-plan.md).
Docs-only task — no `sf/src` changes. All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt
2026-08-18, canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **F tasks included in this closeout:**
  - F1-followup (`1b3a1b5c`): tuple-literal→array init element-wise lowering (parsergap_many_ptr_xmod
    dependency, operator ruling 2026-08-18).
  - F1 (`84470c61`): many_ptr type-alias registration (parsergap_many_ptr_xmod RED→OK).
  - F2 (`7bb775ad`): restore strict fn-call arg comma/close diagnostics (parsergap_strict_comma_xmod).
  - F3 (`9963858f`): invalid print specifier is a compile error, error[3013] (parsergap_specifier_xmod).
  - F4 (`e8321314`): Site B — innermost-local resolution for shadowed vars (parsergap_shadow_local_xmod).
  - F5: **dropped** — became the strict-zig migration plan (M0-M4 + M8, commits `54e7e8b7`..`29132823`),
    all committed separately.
  - F6 (this task): EXPECTED_FAIL historical json `066c9997…` entries at :169/:186 get the
    `→ fc357296…` forward-pointer (see the two F-CLOSEOUT sections below).
- **Corpus (264 dirs): `OK=254 / FAIL=6 / ICE=0 / CRASH=0 / green-guards=4`** — byte-identical to the
  strict-zig M3 sweep (254+6+4=264). Real FAIL=6 = `field_store_drop` (error[3048]) +
  `self_embed_optional_cycle` (error[24]) + `parsergap_selfblok_xmod` (error[2000]) +
  `parsergap_specifier_xmod` (error[3013]) + `parsergap_strict_comma_xmod` (error[2000]) +
  `strictzig_brace_if_xmod` (M1 hard-RED fixture, FAIL **by design**). Green-guards unchanged
  (`eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` / `var_declared_void`).
  Corpus grew 258→264 (5 followup parsergap dirs + the M1 fixture) at the M3 sweep; no movement this task.
- **21-example matrix: 21/21 dump/gcc/link rc=0.** Runs: 19 exit rc=0 (incl. days_in_month all 12
  month-day counts rc=0, Feb 2024 = 29; json_parser parses test.json rc=0, object fields
  comma-separated, no trailing comma — B-F2 runtime-identity; game_of_life 100 generations rc=0);
  mud_server rc=124 ("MUD server listening on port 4000", timeout-gated server); rogue_mud boots
  "Welcome to Rogue MUD!" + exits on `q` rc=0.
- **4 MD5 gates byte-identical** (all MATCH the current baselines, no re-baseline this task): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22] (repo-root CWD —
  CWD-sensitive), json `fc357296537347a0ef58af49b5a40081` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **test_analyzer_bin PASS** ("Analyzer tests passed.", rc=0).
- **Self-compile re-check:** `zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig`
  (timeout 120) passes the M2 blockers (type_resolver.zig:981/:987-990 — 0 hits) AND the M4-fix 4th
  site (`c89_emit.zig:410-412` — 0 hits). **Remaining pre-existing blockers (ALL recorded, ALL out of
  scope, NOT fixed):** (1) `util/hash.zig:18:21` — `*%` saturating-mul, error[2000]; (2)
  `c89_emit.zig:1881-1882` — unterminated string literal, error[0] (+cascades 1939); (3)
  `lexer.zig:236-239` — error[2000] expected-expression/unexpected-token report sites.

## GATE — M4-fix: 4th ;-before-else site + verification expansion + docs correction (2026-08-18)

M4 final review found the plan's "exactly 3 sites" premise was incomplete: a 4th `;`-before-`else`
site existed at `sf/src/c89_emit.zig:410-412` in the self-compile closure (missed because M2/M3
verification grepped only the first error). Per operator ruling (2026-08-18), this gate fixes that
site, expands the self-compile verification to a tree-wide scan, and corrects the docs' false
"sole next blocker" claim. All gates re-verified with `/tmp/fx_subfolder/zig1` (rebuilt 2026-08-18
at HEAD `31d55084` + M4-fix, canonical std reinstalled at `/tmp/fx_subfolder/lib/`):

- **Fix (this gate):** `sf/src/c89_emit.zig:410-412` migrated to braced form (same mechanical
  change as M2) — the `nameManglerMangle` kind-char chain:
  `if (kind == 0) { ... } else if (kind == 1) { ... } else if (kind == 2) { ... }`.
  This is the 4th and last `;`-before-`else` site in the self-compile closure; the fix is
  **byte-identical** (measured, not assumed).
- **Tree-wide scan (verification expansion):** after the fix, the full self-compile
  (`zig1 --markers --dump-c89 --output-dir /tmp/scX sf/src/main.zig`, timeout 120) scans ALL
  non-9999 errors — **ZERO `';' not allowed before 'else'` errors remain anywhere in the closure.**
  Source-tree scan (awk, `;`-ending line followed by `else` on the next line):
  `for f in $(find sf/src -name '*.zig'); do awk 'prev ~ /;[ \t]*$/ && $0 ~ /^[ \t]*else\b/ { print FILENAME ":" FNR ": " prev " ||| " $0 } { prev = $0 }' "$f"; done`
  → **0 hits**. (The only `; else` text left in sf/src is the emitted-C string literal
  `"; else goto z_bb_"` at `c89_emit.zig:3833` — not a Z98 construct.)
- **4 MD5 gates byte-identical** (baselines unchanged): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22] (repo-root CWD), json
  `fc357296537347a0ef58af49b5a40081` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **Corpus spot-check (byte-identical, expect no movement):** `strictzig_brace_if_xmod` FAIL by
  design (M8's diagnostic fires on the fixture's invalid form — the M1 hard-RED fixture),
  `parsergap_selfblok_xmod` FAIL (`error[2000]`), `field_store_drop` FAIL (`error[3048]`) — no
  movement vs v37.
- **Self-compile re-check — TRUE remaining blockers (ALL pre-existing, ALL out of scope, recorded
  only), in order of appearance:**
  1. `sf/src/util/hash.zig:18:21` — `*%` saturating-mul (`hash = hash *% 16777619;`),
     `error[2000]` expected expression / unexpected token.
  2. `sf/src/c89_emit.zig:1881-1882` — unterminated string literal on a line-split string,
     `error[0]` (cascades at 1939).
  3. `sf/src/lexer.zig:236-239` — `error[2000]` expected expression / unexpected token report
     sites.
  The v37 narrative ("next gap = hash.zig:18") implied a sole blocker and was FALSE — the filtered
  stderr also showed c89_emit.zig:411-412 (now fixed), c89_emit.zig:1881-1882, and lexer.zig:236-239.
  Corrected here and in QUICK_REF.

## GATE — strict-zig-if migration plan closeout, gate sweep + reconciliation (2026-08-18)

Final gate sweep of the strict-zig-if migration plan (M1 fixture + M2 migration). All gates
re-verified with `/tmp/fx_subfolder/zig1` (rebuilt 2026-08-18 at HEAD `1585adf2`, canonical std
reinstalled at `/tmp/fx_subfolder/lib/`):

- **M2 fixes landed (this plan):** the 3 invalid `;`-before-`else` if/else sites migrated to
  braced form (`sf/src/type_resolver.zig:980-981` + `:987-990`, `sf/src/diagnostics.zig:295-296`)
  — commit `1585adf2`. No `sf/src` changes in this gate task (docs-only).
- **Corpus (264 dirs): `OK=254 / FAIL=6 / ICE=0 / CRASH=0 / green-guards=4`.** 254+6+4=264.
  Real FAIL=6 = `field_store_drop` (bare `@import("pal")`, `error[3048]`),
  `self_embed_optional_cycle` (C89 fundamental, `error[24]` circular type),
  `parsergap_selfblok_xmod` (`error[2000]`), `parsergap_specifier_xmod` (`error[3013]`),
  `parsergap_strict_comma_xmod` (`error[2000]`) — the plan's expected FAIL=5, UNCHANGED — plus
  `strictzig_brace_if_xmod` (the M1 hard-RED fixture, `error[2000]`, FAIL **by design** — it ships
  the invalid `;`-before-`else` form). Green-guards unchanged (`eu_assign_incompat_payload` /
  `euvoid_val_catch` / `field_access_optional` / `var_declared_void`, all `error[3000]`, 0 `.c`).
  Delta vs plan expectation (263 dirs, FAIL=5): actual = 264 dirs — the +1 is the M1 fixture
  `strictzig_brace_if_xmod` landing in the corpus, counted as FAIL per its gate role (264 =
  258 at the parser-gaps closeout + 5 followup parsergap dirs [many_ptr / selfblok / shadow_local
  / specifier / strict_comma] + 1 M1 fixture). OK=254 unchanged (no fixture flipped; migration
  is byte-identical). ICE=0, CRASH=0.
- **21-example matrix: 21/21 dump/gcc/link rc=0.** Runs: 19 exit rc=0 (incl. json_parser +
  json_parser_workaround rc=0 from their dirs with test.json present, game_of_life 100 generations
  rc=0); mud_server rc=124 ("MUD server listening on port 4000", timeout-gated server); rogue_mud
  boots "Welcome to Rogue MUD!" + exits on `q` rc=0.
- **4 MD5 gates byte-identical** (all MATCH the plan/M2 baselines, measured with the rebuilt
  compiler): gol `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `88dcb7f9abf215aa6420f63e0e67e9c3` [→ `5f886646…`, residual-closeout GATE re-baselined 2026-08-22]
  (repo-root CWD — CWD-sensitive), json `fc357296537347a0ef58af49b5a40081` [→ `9720478c…`, F1 re-baselined 2026-08-19], mud
  `a1d0dd55aada9c3fd904ae33f54de32e`. Byte-identity proof: the migration emits byte-identical C.
- **test_analyzer_bin PASS** ("Analyzer tests passed.", rc=0).
- **Self-compile re-check:** `zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig`
  (timeout 120) now passes the M2 blocker — **0 hits for `type_resolver.zig:98x`** in filtered
  stderr (the braced migration at :981/:987-990 compiles). It proceeds into type resolution and
  hits the next pre-existing gap at `sf/src/util/hash.zig:18:21` (`error[2000]` expected expression /
  unexpected token — the `*%` saturating-mul construct `hash = hash *% 16777619;`). **Recorded,
  out of scope — not fixed** (next self-compile blocker; see QUICK_REF).

## GATE — parser-gaps plan closeout, final gate sweep + reconciliation (2026-08-17)

Final gate sweep of the parser-gaps plan (Workstream A + B). All gates re-verified with
`/tmp/fx_subfolder/zig1` (HEAD `830c5691` + A-F1..A-F3 + B-F1..B-F2), canonical std installed at
`/tmp/fx_subfolder/lib/`:

- **Fixes landed (this plan):** A-F1 (`7209f5b4`, discard capture `|_|` in if-stmt/if-expr),
  A-F2 (`891f06fc`, bare array type as const value), A-F3 (`ef425586`, trailing comma in fn-call
  args), B-F1 (`4f1200de`, specifier-driven print dispatch `{}`/`{d}`/`{c}`), B-F2 (`830c5691`,
  for-index capture disambiguation).
- **Corpus (258 dirs): `OK=252 / FAIL=2 / ICE=0 / CRASH=0 / green-guards=4`.** FAIL=2 =
  `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle` (C89
  fundamental, `error[24]` circular type); green-guards = `eu_assign_incompat_payload` /
  `euvoid_val_catch` / `field_access_optional` / `var_declared_void`. Corpus grew 252→258 since the
  F-CLOSEOUT baseline (the 3 parsergap fixtures + `parsergap_value_if_xmod` +
  `parsergap_value_if_xmod_cross` + `pathnorm_dup_xmod`), all 6 new dirs OK. The 3 parsergap repros
  (`parsergap_discard_if_xmod` / `parsergap_array_type_xmod` / `parsergap_trailing_comma_xmod`) —
  previously deferred FAIL — are now **OK** (A-F1/A-F2/A-F3). Measured: **OK=252 / FAIL=2 / ICE=0 /
  CRASH=0 / green-guards=4 over 258 dirs** (252+2+4=258). (Note: the plan's expected corpus size was
  255 dirs; the actual corpus is 258 — the +3 is `parsergap_value_if_xmod`,
  `parsergap_value_if_xmod_cross`, `pathnorm_dup_xmod` landing after the plan was written. Real
  numbers recorded here.)
- **21-example matrix: 21/21 dump/gcc/link rc=0.** mud_server run rc=124 ("MUD server listening on
  port 4000", timeout-gated); rogue_mud run rc=0 (boots "Welcome to Rogue MUD!", exits on `q`).
- **4 MD5 gates byte-identical:** gol `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp
  `524d2872daefb2677c8ddc1ac8f34cf5`, json `fc357296537347a0ef58af49b5a40081` (B-F2 re-baseline)
  [→ `9720478c…`, F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **test_analyzer_bin PASS** (build_test.sh "5 passed, 4 failed" — unchanged baseline).
- **Self-compile re-check:** `zig1 --markers --dump-c89 --output-dir /tmp/sc sf/src/main.zig`
  (timeout 120) now progresses PAST the three pre-fix blockers (cinclude.zig:23 / lower.zig:2283 /
  main.zig:759 — all 0 `error[` hits at those sites) into type resolution (type_resolver markers
  `RN:`/`CLS:`/`T01` stream), where a NEW pre-existing gap blocks at `type_resolver.zig:981`
  (`error[2000]` expected expression / unexpected token in the const-array-size evaluator
  `evalConstU32Full` sub/div/mod arms, plus lexer.zig:236-239 report sites). Out of scope for this
  plan — recorded, not fixed.
- **days_in_month + json_parser runtime correct per B fixes:** days_in_month prints all 12 month-day
  counts (Feb 2024 = 29, leap year) rc=0; json_parser parses `test.json` rc=0 with object fields
  comma-separated and no trailing comma (B-F2 runtime-identity).

## B-F2 — for-index capture disambiguation, json MD5 re-baseline (2026-08-17)

Compiler fix task of the parser-gaps plan (Workstream B). All gates re-verified with
`/tmp/fx_subfolder/zig1` (HEAD `4f1200de` + B-F2 Site A fix), canonical std installed at
`/tmp/fx_subfolder/lib/`:

- **Fix:** for-loop INDEX capture is now name-disambiguated like the element capture
  (`sf/src/lower.zig` — index capture runs through `maybeDisambiguateCapture`, TYPE_USIZE). The
  `.Object` loop's `i` in json_parser resolves to its own counter (disambiguated `i_2`), not the
  stale `.Array` counter. Site A only; Site B (LDS innermost-scan) NOT implemented.
- **json MD5 RE-BASELINED:** `066c99974f6052317636854dc4c2a2d5` → `fc357296537347a0ef58af49b5a40081`
  [→ `9720478c…` F1 re-baselined 2026-08-19, see the v42 GATE entry].
  Runtime-identity proof (AMENDMENT B): fixed binary parses `test.json` rc=0, object fields
  comma-separated (`"status": "alpha",` / `"bugs": null`), NO trailing comma after last field —
  pre-fix had no object-field commas + trailing `,` after `"meta"`. Array elements unchanged.
- **gol/lisp/mud byte-identical** (no for-index collisions): gol `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22],
  lisp `524d2872daefb2677c8ddc1ac8f34cf5`, mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **21-example matrix: 21/21 dump/gcc rc=0** (re-verified 2026-08-17 with the fixed compiler —
  17 via main.zig + 4 single-file entries: func_ptr_return/mandelbrot/quicksort/sort_strings).
  No repro dirs touched; fix is lowerer-internal — json_parser is the only example with
  `for ... |item, i|` index captures.

## F-CLOSEOUT — std-lib fallback demotion (2026-08-14)

Final gate sweep of the std-lib fallback-demotion plan (Task F fallback demotion, Option A root-cause
fix). All gates re-verified with `/tmp/fx_subfolder/zig1` (HEAD `5c1e17e4`), canonical std installed
at `/tmp/fx_subfolder/lib/`:

- **Root-cause fix (4 sites):** the bare name-cache key (`name_id`) collides with module-0's scoped
  key (`(0<<32)|name_id == name_id`), so any un-scoped `nameCacheGet` silently resolved module-0-first.
  Fixed across **4 sites** — `type_resolver.zig` (`resolveTypeExprFull` `ident_expr` arm reordered
  current-module-first), `symbol_registrator.zig` (`registerDecl` ident_expr alias branch scoped to
  the declaring module), `const_alias_prepass.zig` (Phase-2 seed scoped to the alias declaring
  module), and `semantic_analyzer.zig` (`semanticAnalyzerResolveFnCall` return-type fallback now
  routes through `resolveTypeExprFull`; dead manual scan removed). The bare-key fallback is now
  **primitive + module-0 named type** (module-0 named types share the bare key — that IS the
  collision).
- **4 `r_fallback_*` repros added** (Task R): `r_fallback_fnret` (fn-return-type bare `Foo` in mod_b
  vs module-0's `Foo`, RED→GREEN), `r_fallback_constalias` (`pub const Bar = Foo` ident_expr alias,
  RED→GREEN), `r_fallback_constalias_prepass` (const-alias via prepass, RED→GREEN), and
  `r_fallback_fnret_ctl` (control — no module-0 collision, stays GREEN). All 4 classify OK.
- **Corpus (252 dirs): `OK=246 / FAIL=2 / ICE=0 / CRASH=0 / green-guards=4`.** FAIL=2 =
  `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle` (C89
  fundamental, `error[24]` circular type); green-guards = `eu_assign_incompat_payload` /
  `euvoid_val_catch` / `field_access_optional` / `var_declared_void`. Corpus grew 248→252 (the 4
  `r_fallback_*` repros).
- **21-example matrix: 21/21 dump/gcc/link rc=0.** mud_server run rc=124 ("MUD server listening on
  port 4000", timeout-gated); rogue_mud run rc=0 (boots "Welcome to Rogue MUD!", exits on `q`).
- **4 MD5 gates byte-identical** (unchanged from the F3 AMENDMENT B baseline): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `524d2872daefb2677c8ddc1ac8f34cf5`, json
  `066c99974f6052317636854dc4c2a2d5` → `fc357296537347a0ef58af49b5a40081` [B-F2 re-baselined
  2026-08-17, see gate table; → `9720478c…` F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **test_analyzer_bin PASS** (build_test.sh "5 passed, 4 failed" — unchanged baseline).

## F-CLOSEOUT — std-lib closeout (2026-08-14)

Final gate sweep of the std-lib closeout plan (F1+F2+F3 fixes). All gates re-verified with
`/tmp/fx_subfolder/zig1` (HEAD `c5856928`), canonical std installed at `/tmp/fx_subfolder/lib/`:

- **4 fixes landed:** **D2** (module-instance ≥1 incomplete type — FIXED in
  `sf/src/type_resolver.zig`, module-scoped bare-ident resolution; `arena_multi_inst_xmod`
  RED→OK), **host_is_windows** config const (`sf/src/config.zig`), **printInt INT_MIN**
  (i64-widened negation in `sf/src/std_io.zig`), **emitSocketSelect #ifdef** guard +
  spec-catalog sig corrections (`sf/src/c89_emit.zig` + the std-lib migration spec).
- **21-example matrix: 21/21 dump/gcc/link rc=0.** mud_server run rc=124 ("MUD server listening
  on port 4000", timeout-gated); rogue_mud run rc=0 (boots "Welcome to Rogue MUD!", exits on `q`).
- **4 MD5 gates byte-identical** (F3 re-baseline, AMENDMENT B): gol
  `9cf758d96f25d41980379564a5501bc8` [→ `4afb203f…`, residual-closeout GATE re-baselined 2026-08-22], lisp `524d2872daefb2677c8ddc1ac8f34cf5`, json
  `066c99974f6052317636854dc4c2a2d5` → `fc357296537347a0ef58af49b5a40081` [B-F2 re-baselined
  2026-08-17, see gate table; → `9720478c…` F1 re-baselined 2026-08-19], mud `a1d0dd55aada9c3fd904ae33f54de32e`.
- **Corpus (248 dirs): `OK=242 / FAIL=2 / ICE=0 / CRASH=0 / green-guards=4`.** FAIL=2 =
  `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle` (C89
  fundamental, `error[24]` circular type); green-guards = `eu_assign_incompat_payload` /
  `euvoid_val_catch` / `field_access_optional` / `var_declared_void`. `arena_multi_inst_xmod` is
  the 248th dir (new RED→OK repro — the D2 fix).
- **test_analyzer_bin PASS** (build_test.sh "5 passed, 4 failed" — unchanged baseline).

**Tracking entries (stay LATENT, documented — NOT fixed):**

- **Win32 WSAStartup** — `std_net.init()` is a no-op on Windows (returns 0, no `WSAStartup`/
  `WSACleanup`); a Windows build must add WinSock startup/cleanup before `createTcpServer`/`select`
  work. `std_net.cleanup()` is likewise empty.
- **Win-arm / OpenWatcom `#ifdef` arms untested** — the socket builtin bodies are emitted with a
  `#ifdef _WIN32 / #else` guard (mirroring `net_runtime.c`), but only the Linux `#else` arm is
  exercised here; the Win-arm / OpenWatcom arms remain untested.

## F-GATE — search-path gate sweep + reconciliation (2026-08-14)

Final gate sweep of the std-lib search-path plan (Task F + F-MIGRATE). All gates re-verified with
`/tmp/fx_subfolder/zig1` (HEAD `51fa4342`), canonical std installed at `/tmp/fx_subfolder/lib/`:

- **21-example matrix: 21/21 dump/gcc/link rc=0.** mud_server run rc=124 ("MUD server listening on
  port 4000", timeout-gated); rogue_mud run rc=0 (boots "Welcome to Rogue MUD!", exits on `q`).
- **4 MD5 gates byte-identical** (post-migration re-baseline): gol `4074946027f8f72a325fafaa459bc8ec`,
  lisp `b71a0e0c3d3ad78349e219a9e72c8b35`, json `b47f9498c56a3f6995f803600968dd3b`, mud
  `447c491b4877e65b2ca2b87089a3021b`. Runtime-identical proof (AMENDMENT B): gol renders grid (100
  generations, 0 literal `{}`/`{c}` specifiers); lisp REPL evaluates `(+ 1 2)`→3 / `(define x 10)`
  / `(+ x 5)`→15 / `(car (quote (5 6)))`→5; json parses test.json rc=0; mud rc=124.
- **Corpus (247 dirs): `OK=241 / FAIL=2 / ICE=0 / CRASH=0 / green-guards=4`.** FAIL=2 =
  `field_store_drop` + `self_embed_optional_cycle`; green-guards =
  `eu_assign_incompat_payload` / `euvoid_val_catch` / `field_access_optional` / `var_declared_void`.
- **test_analyzer_bin PASS** (build_test.sh "5 passed, 4 failed" — unchanged baseline).

**Search-path record.** The **D1 defect** (bare `@import("std")` unresolved) is **resolved**: Task F
wired the search path (tiers: importer dir → `-I`/`--lib-dir` dirs in CLI order → default install
path `<exe_dir>/lib` → CWD), F-MIGRATE migrated all 34 example + 57 repro sources to bare
`@import("std")` / `@import("std_net")` / `@import("std_arena")` and deleted all **181** local
`std*.zig` copies (kept `std_import_bare_xmod/local/` as the `--lib-dir` GREEN fixture).
Reclassifications: `test_stub_0` + `std_import_bare_xmod` **FAIL→OK**. `std_import_bare_xmod` is a
**two-state gate**: RED (bare `@import("std")` unresolved without the search path — pre-Task-F) vs
GREEN (resolves either via `--lib-dir local/` OR the default install path `<exe_dir>/lib`).

## F-MIGRATE — std-lib search-path migration closeout (2026-08-14)

All `examples/z98/*/` + `repro/mi_matrix/*/` sources migrated from local `@import("std.zig")` /
`@import("std_net.zig")` / `@import("std_arena.zig")` (and rogue_mud's `../mud_server/std.zig`
cross-refs) to bare `@import("std")` / `@import("std_net")` / `@import("std_arena")`, resolved via
the Task F search path to the canonical `sf/src/std*.zig` installed at `<exe_dir>/lib`
(`/tmp/fx_subfolder/lib`). All **181** local `std*.zig` copies deleted (kept:
`std_import_bare_xmod/local/{std,std_io}.zig` — the Task R `--lib-dir` GREEN fixture). The 14
`std.debug.print`/`printInt` sites (10 example dirs incl. `hello`, plus rogue_mud's 3 test files)
rewritten to `std.io.print`/`printInt`, with `sf/src/std_io.zig` `print` made variadic
(`print(s: [*]const c_char, ...)`) so the compiler's enhanced print lowering (fn name `print` +
≥2 args) still fires — format specifiers stay interpolated.

**Reclassifications (bare `@import("std")` now resolves via the default install path):**
- `test_stub_0` — **FAIL → OK** (was `error[3048]` std-lib-deferred; now resolves + emits).
- `std_import_bare_xmod` — **FAIL → OK** (bare `@import("std")` resolves via `<exe_dir>/lib`; its
  `--lib-dir local/` GREEN path unchanged).

**Corpus (247 dirs, std installed): `OK=241 / FAIL=2 / ICE=0 / CRASH=0 / green-guards=4`.**
FAIL=2 = `field_store_drop` (bare `@import("pal")`, `error[3048]`) + `self_embed_optional_cycle`
(C89 fundamental). No new FAIL; OK improved 239→241. **21-example matrix 21/21** dump/gcc/link OK
(mud_server + rogue_mud link+run with the canonical `std.zig` io+arena re-export — the F4-D2
arena-instance emission bug no longer triggers).

## Totals (246 dirs / 236 manifest repros)

- **CURRENT (2026-08-13 F3 closeout — lisp_interpreter lowerer-defects plan): raw sweep of all
  246 dirs (gcc-exit classifier, `/tmp/fx_subfolder/zig1`, fresh F6-source build, HEAD
  `31de6800`): OK=239 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4** (239+3+4=246). FAIL=3
  unchanged: 2 std-lib-deferred (`field_store_drop` + `test_stub_0`, both `error[3048]`) +
  `self_embed_optional_cycle` (C89 fundamental). Green-guards unchanged:
  `eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
  **No new corpus FAIL introduced by the lisp-defects plan (F1-F6).** The 6 plan repro dirs
  (`union_literal_nested_xmod`, `global_null_init_xmod`, `nested_field_store_xmod`,
  `nested_field_store_xmod2`, `sizeof_struct_union_xmod`, `union_emission_layout_xmod`) all
  classify **OK** (246 = 236 manifest + 10 separately-tracked). **21-example matrix: 21/21
  end-to-end working** — the sole
  gcc-FAIL `lisp_interpreter` (pre-existing builtins.zig `zT_N` lowerer defect) is now
  dump/gcc/link/run rc=0 AND functionally correct (evaluates `nil`/`true`/`+`/`(quote 5)`/
  `cons`; Defects A-E fixed). `json_parser_workaround` run rc=0 (its F4-exposed SEGFAULT
  resolved by the Defect D+E fixes) — parses test.json, prints the full tree. mud_server boots
  (server, timeout-gated). 4 MD5 gates byte-identical: gol `ff47d18d…`, lisp `c1cb748b…`, json
  `376fd681…`, mud `fd0fdaa4…`. test_analyzer_bin PASS (build_test.sh 5/4 unchanged). See the
  F3 closeout section below. Corpus dirs = 236 manifest repros (230 at F7 + the 6 plan repros)
  + 10 separately-tracked dirs (`opt_slice_null_return`, `ptr_to_int_void_xmod`,
  `mod_silent_drop_xmod`, `zT_missing_fwd_xmod`, `plat_stubs_missing_xmod`,
  `tagged_union_cmp_xmod`, `extern_runtime_symbol_xmod`, `io_builtin_test`,
  `console_builtin_test`, `net_builtin_test`).
- Prior: OK=233 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4 over 240 dirs (2026-08-13 F7 —
  std-lib plan CLOSEOUT; measured with `/tmp/fx_subfolder/zig1`, fresh F6-source build).
  FAIL=3 unchanged: 2 std-lib-deferred
  (`field_store_drop` + `test_stub_0`, both `error[3048]`) + `self_embed_optional_cycle` (C89
  fundamental). Green-guards unchanged: `eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`. **No new corpus FAIL introduced by the std-lib plan
  (F1-F6).** The 3 std-lib-plan repro dirs (`io_builtin_test`, `console_builtin_test`,
  `net_builtin_test`) all classify **OK**. The D2 (`arena_alloc_default` → `std_arena.zig`, F3)
  and D4 (`plat_*` console stubs → builtins, F5) deferred gaps are **CLOSED**; `json_parser`,
  `json_parser_workaround`, `rogue_mud`, `extern_runtime_symbol_xmod`, `plat_stubs_missing_xmod`
  all link+run on the standard sf runtime (no legacy object, no `net_runtime.c`). **21-example
  matrix: 20/21 end-to-end working** (lisp_interpreter gcc-FAIL is the pre-existing
  builtins.zig `zT_N` lowerer defect; mud_server boots — server, timeout-gated). 4 MD5 gates:
  gol `b246a2fe…`, lisp `141994cc…`, json `f50ce1e6…` byte-identical; mud `fd0fdaa4…` (F6
  migration + F6-review null-coalesce re-baseline; mud is NOT an MD5 gate per the operator).
  test_analyzer_bin PASS (build_test.sh 5/4 unchanged). See the F7 closeout section below.
  Corpus dirs = 230 manifest repros + 10 separately-tracked dirs (`opt_slice_null_return`,
  `ptr_to_int_void_xmod`, `mod_silent_drop_xmod`, `zT_missing_fwd_xmod`,
  `plat_stubs_missing_xmod`, `tagged_union_cmp_xmod`, `extern_runtime_symbol_xmod`,
  `io_builtin_test`, `console_builtin_test`, `net_builtin_test`).
- Prior: OK=223 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 230 (2026-08-07 F4 gate sweep — char_literal switch + opt_slice null fixes CLOSEOUT). Measured with
  FAIL=3 / green-guards=4 / ICE=0 / CRASH=0** over **230 repros** (223 + 3 + 4 = 230; raw
  classifier FAIL = 7 — the 4 green-guards are a sub-bucket of the raw count). Measured with
  `sf/build/out_release/zig1` at HEAD (compiler source = F1 `e0a4d6d6` char_literal switch +
  F2 `5c515a7d` opt_slice null, commits 7dc119a6..7a732cb3; battery commits are repro-only).
  Corpus = 231 dirs (230 manifest repros + `opt_slice_null_return`, OK-by-gate/type-incorrect,
  tracked separately). The 15 battery repros ALL classify **OK** under the gcc-exit gate and are
  now **fully OK** — the F1/F2 fixes landed: the **12 Battery A char_literal switch-case repros
  no longer runtime-gap-tracked** (F1 emits real `case 'a':` labels at lower.zig:3202 expr /
  :3941 stmt; all 12 now print their expected post-fix output — `120`, `1120`, `19`, `1`, `109`,
  etc., verified by run), and the **3 Battery B opt_slice null-payload repros are no longer
  latent** (F2 Option B drops the dead `int zT_N; zT_N = NULL;` payload temp — 0 `-Wint-conversion`
  warnings, 0 `= NULL;` sites, still print `1`, verified by run). The 3 FAILs unchanged: 2
  std-lib-deferred (`field_store_drop` + `test_stub_0`, both `error[3048]`) +
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4 green-guards unchanged:
  `eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
  No other repro flipped. Note: `opt_slice_null_return` remains OK-by-gate (type-incorrect,
  tracked separately, see the F5 section). 4 MD5 gates: gol byte-identical; mud/lisp/json
  RE-BASELINED by F2 (mud `6c0a83f1…`, gol `0d8f0092…`, lisp `fad41183…`, json
  `c403f079…` — full hashes in QUICK_REF). [F2 2026-08-08: `extern_runtime_symbol_xmod` added
  as a 232nd dir — OK-by-gate/latent, std-lib-deferred, tracked separately like
  `opt_slice_null_return`; manifest count and all totals UNCHANGED. See the F2 section below.]
  [F4 2026-08-08: `plat_stubs_missing_xmod` documented as OK-by-gate/latent,
  std-lib-deferred (the D4 platform-stub gap — 5 console/platform-detect stubs,
  `plat_is_windows` + `plat_console_*`, all rogue_mud-only); tracked separately
  like `opt_slice_null_return` / `extern_runtime_symbol_xmod`; manifest count
  and all totals UNCHANGED. See the F4 section below.]
  [F5 2026-08-13: the D4 plat-stub gap is CLOSED via the F2 console builtins —
  `rogue_mud/ui.zig`'s 5 `plat_*` console externs → `@isWindows`/
  `@consoleClear`/`@consoleGotoxy`/`@consoleSetColor`/`@putChar`; main.zig's
  `ui_mod.plat_is_windows()` → comptime `@isWindows()`; `plat_stubs_missing_xmod`
  migrated to the builtins → **FULLY OK** (link rc=0, run rc=0), its
  OK-by-gate/latent deferral CLEARED; rogue_mud links (rc=0, both recipes) +
  runs (rc=0, ANSI console verified). Manifest counts UNCHANGED (223/3/4/0/0,
  raw FAIL 7). See the F5 section below.]
- Prior: OK=208 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 215 (2026-08-07 F5 gate sweep — rogue_mud emission-defects plan closeout; Verified with `/tmp/zf5/zig1` — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors). `switch_mixed_case_argtype`
  **FAIL→OK** (added 2026-08-07 by the rogue_mud I-task): the sema mid-switch abort in
  `resolveSwitchExpr` — the MIX else-branch at semantic_analyzer.zig:1167 `return
  type_mod.TYPE_VOID;` aborted the whole switch when two prong bodies had non-coercible types
  (assignment→i32 vs empty-block→void), skipping all later prongs — so the call prong was never
  sema'd and `call_arg_types` was never populated, making the lowerer fallback type arg slots as
  raw lowered types (`unsigned int` for `&arena`, `char*` for the string literal). Now the
  MIX else-branch `continue`s (keeps resolving remaining prongs) while keeping the
  `resolvedTypeTableSet(..., TYPE_VOID)` (Option A, operator ruling; I4-validated). dump rc=0,
  gcc-clean, link rc=0, run rc=0; emitted arg temps correctly typed `Sand*` / `Slice_u8`. The 3
  remaining FAILs: 2 std-lib-deferred (`field_store_drop` + `test_stub_0`, both
  `error[3048]`) + `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4
  green-guards unchanged: `eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`. No other repro flipped. Note: `opt_slice_null_return`
  is OK-by-gate (type-incorrect, tracked separately). Known adjacent bug (out of scope, tracked
  as follow-up): char-literal switch `case` labels dropped at lower.zig:3858-3860/:3121-3123 (refs superseded — actual sites lower.zig:3183 expr / :3920 stmt), so
  this repro's switch still takes `default` at runtime (see the F4 section below).
- Prior: OK=207 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 214 (2026-08-07 F3: cross-module pub const resolves)
- Prior: OK=206 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 213 (2026-08-07 F2: undefined struct-array field init emits valid C)
- Prior: OK=205 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 212 (2026-08-07 F1: duplicate-typed struct fields emit correctly)
- Prior: OK=203 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 210 (2026-08-07 F1: labeled statement support in parser, sema, lowerer)
- Prior: OK=202 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 210 (2026-08-07 I-task: rogue_mud build attempt — labeled_stmt_unhandled added as FAIL)
- Prior: OK=202 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 209 (2026-08-06 Task F7 gate sweep, 4-item plan closeout)
- Prior: OK=200 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 208 (2026-08-06 F2 u64-safe int_literal marker)
- Prior: OK=199 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 207 (2026-08-06 F1 @intCast range-check)
- Prior: OK=198 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 206 (2026-08-06 F9 gate sweep)
- Prior: OK=197 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 205 (2026-08-06 F7: comptime_u64_fold_overflow)
- Prior: OK=196 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 204 (2026-08-06 P0 fix wave 1)
- **2026-08-01 ADD: `comptime_neg_int`** — RUNTIME GAP, not counted in the compile-only totals above. `const N = @intCast(i32, -5);` dumps rc=0, gcc clean, but emitted C never assigns `N` (comptime-folded negative dropped) → run prints garbage not `-5`. Tracks via runtime gate; the gcc-exit classifier reports it OK. Reproduces "comptime int cannot be negative". **FIXED post-F-1..F-8 (2026-08-04): prints `-5` correctly.**
- Prior: OK=162 / FAIL=4 / ICE=0 / CRASH=0 (2026-07-16: extern-fn ABI-wrap — c89_emit .call_direct wrapping for extern fn optional/EU returns; 5/5 extern-fn repros fixed; opt_extern_ptr_file FIXED; json_parser HARD gate 0 errors; EU representation (3) now FIXED by error-set pipeline)
- Prior: OK=148 / FAIL=14 / ICE=0 / CRASH=0 (2026-07-16: folded 13 ungated RED repros from top-level `repro/` tree into gated corpus)
- Prior: OK=148 / FAIL=1 / ICE=0 / CRASH=0 (2026-07-16: error-set crash fix chain — F-SEMA Gap A/B sema arms + shared helper `typeRegistryErrorSetMemberIndex`; F-C5C7 Fix A+B valid module/type_alias temps + Fix C symreg `populateTypePayload` error_set_decl case + Fix E/F lowerer member lookups + module-base field_access branch; F-LISP module-qualified fn refs via func_ref machinery; F-C6 c89_emit `emitErrorSetType` typedef + per-member `#define` constants; F-TEMPNONE dedicated temp-index sentinel `TEMP_NONE=0xFFFFFFFF`; F-REMOVE unconditional 3042 tripwire + module-as-value warning[3023] + observability repro)
- Prior: OK=147 / FAIL=1 / ICE=0 / CRASH=0 (2026-07-15: error-set pipeline fix — T1 symbol_reg, T2 sema, T3 lowerer, T4 c89_emit)
- Prior: OK=144 / FAIL=2 / ICE=2 / CRASH=0 (2026-07-14: Phase D repros — actual state; earlier manifest erroneously claimed 147/1/0/0)
- Prior: OK=136 / FAIL=5 / ICE=1 / CRASH=0 (2026-07-14: sema-diagnostics v2)
- Prior: OK=122 / FAIL=15 / ICE=1 / CRASH=0 (2026-07-13: xmod_field_store_index fixed)
- Prior (132 repros): OK=117 / FAIL=14 / ICE=1 / CRASH=0 (v4 idiomatic baseline)

---

## ICE (7 — all from syntax coverage category A-E, 2026-07-30)

7 new ICE repros added for categories A-E. All hand-rolled tagged union patterns (A1-A3) trigger `error[3043]: internal: unsupported field-store base`. Inferred error set patterns (B1-B2) trigger `error[3011]: error literal not found in error set`.

### Error[3043] — hand-rolled tagged unions (3)
- `tu_field_store_ptr` — union field-store through @ptrCast pointer
- `tu_uninit_data_void` — uninitialized union data for void-variant tag
- `tu_ptrcast_copy` — hand-rolled tagged union copy through @ptrCast

### Error[3011] — bare `!` error sets (2)
- `inferred_errorset_fnptr` — @ptrCast to fn(!T) through *void
- `inferred_errorset_xmod` — cross-module bare ! error inference

### Error[2000] — parser (2, defined in category F)
- `define_mutate_closure` — `fn (i32) i32` type syntax not parseable
- `define_mutate_closure_green` — same parse failure

**Prior:** All error-set SEGV/ICE crashes eliminated. **Accidental-revert history:** commit `a4bb08c4` ("use structural hash for optional C typedef naming") accidentally reverted 4 earlier error-set commits — `9f2236e2` (c89_emit error_set typedef + member emission), `c0803328` (symreg error_set payload population), `d0104d33` (sema error_set member handlers), `b4d78651` (lowerer module-base field_access branch) — which is why an earlier manifest claimed 147/1/0/0 when actual was 144/2/2/0. This plan's upstream fix chain correctly restored all 4 layers.

- `lzw_cross_module_error_set` (C5) — **FIXED** — was ICE (SEGV at hoisted_temps[18] OOB). Fixed by: sema member resolution via shared helper, symreg payload, lowerer valid module temp + module-base field_access branch + member lookup via helper, c89_emit cross-module typedef emission.
- `lzw_error_set_member_comparison` (C6) — **FIXED** — was ICE → partial F2 error[3042] → now compilable C. Fixed by: sema Gap A/B arms, c89_emit `emitErrorSetType` typedef + per-member `#define` ordinals.
- `lzw_eu_return_mismatch` (C7) — **FIXED** — was ICE (SEGV same class as C5). Fixed by: sema member resolution, symreg payload, lowerer valid type_alias temp + member lookup via helper, `.is_error=1` wrap_error_err EU-wrap coercion path.

---

## FIXED (2026-07-16 — optional-wrap coercion family: 6/7)

### Orelse unwrap (F-REPROFIX + F-SEMA-ORELSE)
- `orelse_void` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (orelse void coercion). Fixed by: repro rewritten to valid z98 syntax + sema :806 coercion recording.
- `optstar_void_orelse` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (*void orelse coercion). Fixed by: repro rewritten to valid z98 syntax + sema :806 coercion recording.
- `file_const_single` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (file-level const optional). Fixed by: repro rewritten to valid z98 syntax + sema :806 coercion recording.

### Catch EU unwrap (F-SEMA-CATCH + F-CATCHRETURN)
- `eu_optional_value` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (error union optional value). Fixed by: sema :1187 coercion recording + lower.zig `lowerExprOrBlock` stmt routing.
- `mi_eu_opt_val` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (module-import variant of eu_optional_value). Fixed by: sema :1187 coercion recording + lower.zig `lowerExprOrBlock` stmt routing.

### Var_decl type pollution (F-LOWERIDENT2)
- `opt_value_decl` — **FIXED** — gcc `incompatible types when assigning to type 'zT_*_Opt_*'` (optional payload in decl init). Previously fixed by band-aid `3c8c1e92`, now fixed at ROOT via sema :1559 guard against resolvedTypeTable pollution.

---

### FIXED by extern-fn ABI-wrap (1)
- `opt_extern_ptr_file` — **FIXED (F-ABI)** — was deferred `??*T FILE* gateway`. extern-fn ABI-wrap (`c89_emit .call_direct` wrapping for extern fn optional/EU returns) now wraps raw `FILE*` into `Opt_*` type. gcc 0 errors. No longer deferred.
---

## FAIL (6) — [2 remain FAIL post-F-1..F-8; see F-1..F-8 section above]

### VOID decl-skip / undeclared-temp (2) — out-of-scope
- `var_declared_void` — gcc `'x' undeclared` (VOID-typed variable skipped in C decl emission). **Still FAIL post-F-1..F-8** (sema doesn't reject void vars).
- `field_store_drop` — **STILL FAIL post-F-1..F-8** — now via `error[3048]: could not resolve imported file 'pal'` (its `const pal = @import("pal")` can't be resolved — pre-existing import-resolver gap; F-5 AMENDMENT C).

### Aggregate / anon-init (2) — out-of-scope
- `anon_init_orelse_rhs` — gcc `incompatible types` (anonymous init on orelse RHS). **FIXED post-F-1..F-8 (F-6+F-8)** → OK.
- `array_tagged_union_read` — gcc `incompatible types` (tagged union indexing on array). **Still FAIL post-F-1..F-8** (union payload assigned from `unsigned int`).

### Syntax coverage new FAILs (2) — 2026-07-30
- `tu_uninit_data_void` — gcc `void tag/data declared` (hand-rolled tagged union with uninitialized data variant). **FIXED post-F-1..F-8 (F-3)** → OK.
- `module_var_mutable` — gcc `'x' undeclared` (global mutable var, C emission misses global declaration). **FIXED post-F-1..F-8 (F-7)** → OK.

Note: FAIL=4 count reflects 2 remaining out-of-scope families (VOID decl-skip, aggregate/anon-init) = 4 repros total (2+2). EU representation (3 repros: eu_err_ret, eu_value_ret, mi_eu_err) now FIXED by error-set pipeline (F-C5C7 Fix A/B) — gcc 0 errors.

---

## Folded 13 RED repros (2026-07-16)

Gated 13 ungated top-level repros into `repro/mi_matrix/` corpus. **As of 2026-07-16, 9/13 FIXED (see FIXED sections above).** Remaining 4 still classify as FAIL (gcc errors):

- **EU representation** (3): `eu_err_ret`, `eu_value_ret`, `mi_eu_err` — **FIXED by error-set pipeline (F-C5C7 Fix A/B)** — gcc 0 errors. Was previously FAIL (incompatible types in error-union payload/return coercion).
- **VOID decl-skip / undeclared-temp** (2): `var_declared_void` — `'x' undeclared` (VOID-typed variable skipped in C declaration). `field_store_drop` — `'zT_23'/'zT_32' undeclared` (undeclared temps from field-store lowering; same root cause as var_declared_void VOID-decl-skip path). Fix owned by future plan.
- **Aggregate / anon-init** (2): `anon_init_orelse_rhs` — anon init on orelse RHS. `array_tagged_union_read` — tagged union indexing on array.

---

## Repro added 2026-07-16

- `module_as_value` — **OK (warning[3023] non-fatal)**. Bare module ident in value position (`_ = h;`) emits `warning[3023]: module used as value expression`. VOID temp prevents C-decl pollution (TYPE_VOID=1 skipped by c89_emit decl loop). zig0 oracle: accepts silently (rc=0). C compiles cleanly (gcc 0 errors). Class: OK.
  - **REGRESSION + F-9 FIX (2026-08-04):** post-F-1..F-8 this was FAIL — emitted `main_6D0C3706.c` had
    `(void)zT_0;` with `zT_0` undeclared (module-ident branch returned a VOID temp). **Fixed F-9** (module
    branch now returns `TEMP_NONE`) — classified **OK** again.

---


## FIXED (2026-07-16 — extern-fn ABI-wrap: 5/5)
- `opt_extern_ptr_file` — **FIXED (F-ABI)** — was deferred `??*T FILE* gateway`. extern-fn ABI-wrap (`c89_emit .call_direct` wrapping for extern fn optional/EU returns) now wraps raw `FILE*` into `Opt_*` type. gcc 0 errors. No longer deferred.
- `extern_fn_opt_return` — **OK (F-ABI)** — optional return from extern fn; ABI-wrap emits wrapper that calls extern, builds `Opt_*` struct from raw return. gcc 0 errors.
- `extern_fn_opt_return_cross` — **OK (F-ABI)** — cross-module variant of extern_fn_opt_return. gcc 0 errors.
- `extern_fn_eu_return` — **OK (F-ABI)** — error-union return from extern fn; ABI-wrap emits caller-side wrapper. gcc 0 errors.
- `error_set_unknown_member` — **OK (F-ABI)** — error-set member resolution across modules; was expected FAIL per original plan but passes gcc 0 errors after extern-fn ABI fixes. Class: OK (not fail).

---

## FIXED (2026-07-15 — lowerer-errors-deep-dive)

- `euvoid_val_catch` — **FIXED (F1)** — `lowerExprImpl` now handles `AstKind.block` in expression context. `return {}` coerced to `E!void` no longer ICEs.
- `lzw_local_var_undeclared` — **FIXED (F3)** — sema caches non-ident type annotations (`[256]u8`, `*T`, `?T`) in `resolvedTypeTable`. Lowerer emits `decl_local` — `buf` declared in C.

## Repro added 2026-07-14

- `field_access_optional` — **FIXED (ERR_3000)** — `?S.x` now produces `error[3000]: cannot access field on optional type` instead of lowerer ICE. Matches zig0 oracle (rejects `.` on optional). Green guard — no C emitted. → reclassified **green-guard (P3-1)**; see Green-guards section.
- `lzw_error_set_typedef` — **GREEN at HEAD** — simple error-union case passes.

## Previously FIXED (2026-07-14)

- `eu_assign_incompat_payload` — **FIXED** — `E!i64 → E!i32` now emits `error[3000]` at sema (EU payload mismatch severity check). → reclassified **green-guard (P3-1)**; see Green-guards section.
- `euoptptr_val_orelse` — **FIXED** — optional C typedef naming uses `getCTypeName` instead of `name_id=0`.
- `optptr_val_orelse` — **FIXED** — same c89_emit fix.
- `optptr_null_orelse` — **FIXED** — same c89_emit fix.
- `eu_assign_incompat_errorset` — **WARNING** — different error sets produce warning[3000] but same C struct compiles.
- `typeres_unhandled_node` — **FIXED (2026-07-14)** — range handler + lowerer demote.

## Previously FIXED (2026-07-13)

- `xmod_field_store_index` — EX1 fix (broad name-cache prepass)
- `array_value_copy` — EX3 fix (indexed elem type + emitter)
- `array_manyptr_type` — EX4 fix (c89_emit * sanitize)
- `func_ptr_return_type` — EX5 fix (FN_/FP_ prefix + ident_expr)

---

## Syntax Coverage Repro — 2026-07-30 (13 repros, categories A-F)

Repros discovered from broken examples (lisp_interpreter, json_parser_workaround, rogue_mud, lisp_adv). All hand-rolled tagged union patterns trigger error[3043]. Inferred error set patterns trigger error[3011]. GREEN regression guards pass where applicable.

| Category | Repro | GREEN | RED | Pattern |
|----------|-------|-------|-----|---------|
| A1 | `tu_field_store_ptr` | OK | **OK (F-3)** | union field-store through @ptrCast ptr |
| A2 | `tu_uninit_data_void` | — | **OK (F-3)** | uninitialized union data for void tag |
| A3 | `tu_ptrcast_copy` | — | **OK (F-3)** | hand-rolled tagged union copy |
| B1 | `inferred_errorset_fnptr` | OK | **OK (F-1)** | @ptrCast to fn(!T) through *void |
| B2 | `inferred_errorset_xmod` | OK | **OK (F-1)** | cross-module bare ! error set |
| C1 | `catch_block_implicit_expr` | OK | OK(no RED) | catch block expression works |
| D | `ptroint_arena_offset` | OK | FAIL | @intToPtr/@ptrToInt arena arithmetic |
| E | `module_var_mutable` | OK | **OK (F-7)** | global mutable var missing C decl |
| F | `define_mutate_closure` | ICE(2000) | ICE(2000) | fn ptr type not parseable by zig1 |

**Total (A-F): 13 new (10 unique + 3 GREEN guards), 2 new FAILs, 7 ICEs, 4 OK (all GREEN + C1 RED that unexpectedly passes)**

---

## Syntax Coverage G — 2026-07-30 (3 repros, cross-module struct literal)

Cross-module struct literal pattern discovered from json_parser_workaround. Creating a struct literal with an imported struct type causes the variable declaration to be missing from C output. Adding a field-store after the literal escalates to ICE(3043).

| Category | Repro | GREEN | RED | Pattern |
|----------|-------|-------|-----|---------|
| G1 | `ptrcast_slice_field_void` | OK | **OK (F-4)** | xmod struct + slice field + field-store |
| G2 | `ptrcast_slice_field_xmod` | OK | **OK (F-4)** | xmod struct + scalar fields + field-store |
| G3 | `ptrcast_slice_field_type` | OK | **OK (F-4)** | xmod struct literal only (no field-store, undeclared var) |

**Note:** Category F (define_mutate_closure) removed from corpus — `fn (i32) i32` syntax not parseable by zig1.

---

## Syntax Coverage H — 2026-07-30 (1 repro, cross-module &extern_var + union field-store)

Full json_parser_workaround chain: `&zig_default_arena` (address-of extern var) → `arena_alloc_default` → `@ptrCast` to struct with union data → field-store to union member → ICE(3043).

| Category | Repro | GREEN | RED | Pattern |
|----------|-------|-------|-----|---------|
| H1 | `xmod_amp_arena_union_store` | OK | **OK (F-3)** | &extern_var + extern alloc + @ptrCast + union field-store |

## Std-Lib Phase 1 — 2026-08-03 (6 repros, std-lib migration syntax-gap candidates)

Defensive repros for the std-lib migration design spec — each probes a Z98 syntax feature with ZERO prior corpus coverage. Classified per QUICK_REF (dump + per-file gcc -c). Full evidence in each dir's `NOTES.md`.

| Pattern | Repro | Result | Note |
|---------|-------|--------|------|
| struct fn-ptr field (vtable) | `fn_ptr_struct_field` | OK | **FIXED (F-2)** — was FAIL (`'write_fn' declared void`); struct FieldEntries back-patch + void-field guard |
| pub module var (scalar) | `module_pub_var_int` | OK | **runtime gap FIXED (F-7)** — `= 42` init now emitted; prints `43` |
| pub module var (struct) | `module_pub_var_struct` | OK | **runtime gap FIXED (F-7)** — prints `7` |
| module const fn-call init | `module_const_fn_call` | OK | **runtime gap FIXED (F-7)** — `getInit()` now called; prints `42` |
| local fn-ptr (bare, no errset) | `fn_ptr_local_bare` | OK | gcc-clean, runs correctly (prints 3); sema warning[3000] non-fatal |
| cross-module `extern "c"` | `import_extern_c` | OK | 2 .c emitted, gcc-clean, runs correctly (prints hello) |

**Total active repros in v16: 192. Classification: OK=173, FAIL=8, ICE=11, CRASH=0.** *(pre-F-1..F-8 snapshot — see F-1..F-9 section for post-fix OK=184 / FAIL=8 / ICE=0)*

---

## F-1..F-9 corpus-RED fixes — 2026-08-04 (measured with /tmp/zb/zig1)

Post-fix state: **OK=184 / FAIL=8 / ICE=0 / CRASH=0** over 192 repros.

Post-P1+guard state (this file, 197 repros): **OK=188 / FAIL=9 / ICE=0 / CRASH=0** — see
"Defensive repros (Plan 1, 2026-08-04)" below. The +1 FAIL is `self_embed_optional_cycle`
(its own documented F-8 residual); the other 4 new repros classify OK.

All 6 pre-fix `error[3043]` ICEs eliminated (moved to OK):
- `tu_field_store_ptr`, `tu_ptrcast_copy`, `xmod_amp_arena_union_store`, `struct_field_store_subscript`
  (F-3), `ptrcast_slice_field_void`, `ptrcast_slice_field_xmod` (F-4).

Former FAIL/ICE repros now OK (verified per-file gcc clean):
- `inferred_errorset_fnptr`, `inferred_errorset_xmod`, `bare_error_union_return` (F-1 error[3011] fixed)
- `fn_ptr_struct_field` (F-2)
- `tu_uninit_data_void`, `tu_field_store_ptr`, `tu_ptrcast_copy`, `xmod_amp_arena_union_store`,
  `struct_field_store_subscript` (F-3)
- `ptrcast_slice_field_type`, `ptrcast_slice_field_void`, `ptrcast_slice_field_xmod` (F-4)
- `anon_init_orelse_rhs` (F-6+F-8)
- `module_var_mutable` (F-7)
- `opteu_err_if_expr`, `opteu_err_switch`, `module_as_value` (F-9)
- Runtime gaps now FIXED (run-verified): `comptime_neg_int` → `-5`, `module_pub_var_int` → `43`,
  `module_pub_var_struct` → `7`, `module_const_fn_call` → `42`.

Remaining 8 FAIL (0 ICE) — as measured with /tmp/zb/zig1 pre-P2; see the P2-3 green-guard
section below for the var_declared_void/euvoid_val_catch reclassification:
- **Emission defects (dump rc=0, gcc rejects):** `array_tagged_union_read` (**FIXED by P2-2**,
  2026-08-04), `ptroint_arena_offset` (**FIXED by P2-4**, 2026-08-05), `var_declared_void` (**now a
  green-guard, P2-3**).
  - NOTE: `module_as_value`, `opteu_err_if_expr`, `opteu_err_switch` were FAIL in the F-1..F-8
    baseline (undeclared `zT_0` temp / incompatible int→`Opt_` assign) but are now **OK — fixed F-9
    2026-08-04** (Option B optional-of-EU unwrap in the error-literal sema handler + module branch
    `TEMP_NONE`). Verified per-file gcc clean; see "Former FAIL/ICE repros now OK" above.
- **Frontend gaps (5, 0 `.c` emitted; 2 now green-guards P3-1):** `catch_block_value_producing`
  (error[2000]), `eu_assign_incompat_payload` (error[3000] — **now a green-guard, P3-1**),
  `field_access_optional` (error[3000] — **now a green-guard, P3-1**), `field_store_drop`
  (error[3048], pal-import — see QUICK_REF known-issues), `test_stub_0`
  (error[3048], imports nonexistent `"std"`).

---

## Defensive repros (Plan 1, 2026-08-04) — +4 repros (192 → 196)

Four defensive repros guarding deferred items from the F-1..F-9 review (cross-module global
field-access, F-8 optional self-embed residual, F-7 array `load_global` copy-loop, anonymous
error-set comparison). Classified with `/tmp/zb/zig1` per the QUICK_REF corpus classifier
(dump rc + emitted `.c` count + per-file `gcc -c`; runtime verified for the runnable ones).

| Repro | RED | GREEN | Classification (measured) | Guards |
|-------|-----|-------|---------------------------|--------|
| `xmod_global_field_access` | runtime gap | OK (prints 2) | **FIXED (P1-2)** — dump rc=0, gcc-clean, prints `2` (two bumps → counter=2) | F-7 review I-1: cross-module global field-access — FIXED by Plan 1 Task P1-2 (lower.zig SymbolKind.global branch + header extern decls) |
| `self_embed_optional_cycle` | FAIL | — | **FAIL** — dump rc=0, 1 `.c`, gcc `unknown type name 'zT_DD0C1E27_X'` (incomplete-type) | F-8 residual: `struct X { next: ?X }` → infinite-size C type; guards, not fixes |
| `load_global_array_copy` | OK | — | **OK** — dump rc=0, 1 `.c`, gcc clean, runs: prints `3` and `15` (concatenated `315`, print_int adds no newline) | F-7 array `load_global` copy-loop correctness (dead copy-temps, correct but wasteful) |
| `anon_errset_comparison` | OK (prints 1) | OK (prints 1) | **OK (semantically verified, P3-3)** — dump rc=0, 1 `.c`, gcc clean, RED prints `1`, GREEN prints `1`; RED==GREEN==1 on zig1 AND zig0 oracle (matches oracle) | bare-`!` error-set member comparison (`err == error.Bad`) — **semantically correct (P3-3)**: anon error literal carries the raw name_id (unique-per-name, program-stable interner code), so same name ⟹ same code, distinct names never collide |

**Updated totals: OK=187 / FAIL=9 / ICE=0 / CRASH=0 over 196 repros.** The +1 FAIL is exactly
`self_embed_optional_cycle`'s own documented status (F-8 residual). The other 3 new repros
classify OK, so the FAIL increase does not exceed the new repros' own documented status; no
regressions in the existing 192.

**Notes:**
- `xmod_global_field_access` was a RUNTIME GAP (counted OK in the compile-only gate) and is now **FIXED by Plan 1 Task P1-2** — prints `2` (was 1).
- `self_embed_optional_cycle` FAIL is the documented F-8 residual. Naive C emission would produce
  `struct X { struct X next; int has_value; }`; today the struct typedef is dropped entirely
  (`unknown type name`), so the residual is guarded, not fixed.
- `anon_errset_comparison`: RED and GREEN both print `1` — the bare-`!` set comparison is
  **semantically correct (P3-3, Option A)**. name_id is a unique-per-name, program-stable
  interner code; same name ⟹ same code, distinct names can never collide within one program.
  Verified RED==GREEN==1 on zig1 and the zig0 oracle. Investigation resolved — see the P3-3
  section below.

---

## Task P1-4 guard repro — 2026-08-04 (+1 repro, 196 → 197)

Guards the analyzer `analyzeExpr` builtin_call crash that crashed `examples/z98/lzw` at HEAD
(regression `532420cb`, last-good `7bc6e4d1`). Single-file repro of `main.zig:17`:
`@intCast` inside an `if` condition. `builtin_call.child_0` is the builtin's **name_id**, not a
node index (parser.zig:611); `analyzeExpr`'s generic child fallback recursed into it and formed a
cycle when the name_id collided with the enclosing `if_stmt`'s node index → infinite recursion →
stack overflow. Full analysis: `.superpowers/sdd/I-lzw-regression-report.md`.

| Repro | RED | Classification (measured) | Guards |
|-------|-----|---------------------------|--------|
| `lzw_builtin_call_crash` | CRASH pre-fix | **CRASH pre-fix** (dump rc=139 SIGSEGV, 0 `.c`; bypassed by `--no-null-check --no-lifetime-check --no-leak-check`); **OK post-fix** (dump rc=0, gcc-clean, links, runs → prints `invalid` on stdin EOF) | P1-4 analyzer `builtin_call` arg-walk fix (analyzer.zig:495-502) |

**Updated totals post-fix: OK=188 / FAIL=9 / ICE=0 / CRASH=0 over 197 repros.** The +1 total is
the new repro, which counts OK post-fix. FAIL count unchanged (9) vs the P1-3 baseline; no existing
repro flipped OK→FAIL; the lzw example itself now dumps, compiles, links, and runs.

---

## Green-guards (correct rejection, not a defect) — P2-3 (2026-08-04)

Reclassified per operator ruling (AMENDMENT P2-3). A green-guard is a valid-Z98 program that is
CORRECTLY rejected by the frontend with a diagnostic — it guards the rejection, it is not a compiler
gap. Green-guards are counted SEPARATELY from FAIL; a green-guard moving to OK/FAIL is a regression.
Classifier rule: dump emits 0 `.c` with the documented `error[NNNN]` diagnostic.

| Repro | Classification | Correct rejection (measured; P2 rows /tmp/p2v/zig1, P3-1 rows /tmp/p3/zig1) |
|-------|----------------|--------------------------------------------------|
| `var_declared_void` | **green-guard (was emission-defect FAIL)** | dump rc=2, `error[3000]: cannot declare variable of type void`, 0 `.c` emitted. `var x = noop();` (void init) — sema now rejects VOID-typed var decls (semantic_analyzer.zig:1674-1677) |
| `euvoid_val_catch` | **green-guard (was OK)** | dump rc=2, `error[3000]: cannot declare variable of type void`, 0 `.c` emitted. `var r = h() catch {};` (void-typed init) — latent void-var acceptance bug; Zig forbids void variables |
| `eu_assign_incompat_payload` | **green-guard (was frontend-gap FAIL)** | dump rc=2, `error[3000]: type mismatch in assignment — internal type representations differ`, 0 `.c` emitted. `E!i64 → E!i32` payload mismatch at sema; zig0 oracle rejects identically (`error: type mismatch`) |
| `field_access_optional` | **green-guard (was frontend-gap FAIL)** | dump rc=2, `error[3000]: cannot access field on optional type; use .? to unwrap first`, 0 `.c` emitted. `.` on `?S`; zig0 oracle rejects identically (`error: type mismatch`) |

Post-P2-3 accounting: **OK=188 / FAIL=7 / green-guards=2 / ICE=0 / CRASH=0 over 197 repros.**
(var_declared_void: FAIL→green-guard; euvoid_val_catch: OK→green-guard; FAIL 9→7 counting
green-guards separately; array_tagged_union_read moved FAIL→OK in P2-2.) No other repro flipped.

**Post-P3-1 accounting (2026-08-05): OK=189 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 197
repros** (189 + 4 + 4 = 197). `eu_assign_incompat_payload` and `field_access_optional` reclassified
FAIL→green-guard (verified correct rejections matching the zig0 oracle — see table). No other repro
flipped.

**Updated totals (raw classifier, 197 repros): OK=189 / FAIL=8 / ICE=0 / CRASH=0.** Of the 8
classifier-FAILs, 4 are green-guards (this section): `eu_assign_incompat_payload`,
`field_access_optional`, `var_declared_void`, `euvoid_val_catch` (green-guards are a sub-bucket of
the raw 8, counted separately from FAIL).

---

## P2-4 — ptroint_arena_offset FIXED (2026-08-05)

`ptroint_arena_offset` moves emission-defect **FAIL → OK** via **Option A + SCOPED Option B**:

- **Option A (root cause, semantic_analyzer.zig:495,498):** `semanticAnalyzerResolveArithmetic`
  now treats `TYPE_INT_LIT` as a valid pointer-arithmetic offset (`&buf + 64` → pointer type
  instead of TYPE_VOID), covering `ptr ± lit` and `lit + ptr`.
- **SCOPED Option B (emission hardening, c89_emit.zig:2729,2732):** the `written_type` override in
  `emitHoistedDecls` now applies only when the hoisted temp's `type_id ∈ {TYPE_VOID, TYPE_UNDEFINED}`
  AND the derived `written_type` is valid (`!= 0xFFFFFFFF`) and `!= TYPE_VOID`. Zero-blast-radius
  (verified in `.superpowers/sdd/P2-optB-report.md`); the unscoped variant regressed the corpus.
- **Gates:** self-host build 0 gcc errors; repro dump rc=0, gcc-clean, links, runs rc=0
  (`zT_8` declared as `Arr_unsigned_char_6*`); full corpus **OK=189 / FAIL=8 / ICE=0 / CRASH=0**
  (raw classifier; FAIL −1 exactly, `ptroint_arena_offset` removed, no other flips); 4 MD5 gates
  byte-identical (mud `4644ad13…`, gol `d0d3051d…`, lisp `f84c8748…`, json `3492a935…`).

**Post-P2-4 accounting: OK=189 / FAIL=6 / green-guards=2 / ICE=0 / CRASH=0 over 197 repros**
(189 + 6 + 2 = 197). FAIL 9→8 raw; the 2 green-guards (`var_declared_void`, `euvoid_val_catch`)
count separately. Remaining 6 FAIL: 5 frontend gaps (`catch_block_value_producing`,
`eu_assign_incompat_payload`, `field_access_optional`, `field_store_drop`, `test_stub_0`) and
1 gcc-visible emission defect `self_embed_optional_cycle` (F-8 residual) — all documented above.

---

## P3-1 — reclassify 2 correct rejections as green-guards (2026-08-05)

`eu_assign_incompat_payload` and `field_access_optional` are **CORRECT rejections** matching the
zig0 oracle — green-guards, not defects (both documented as FIXED above; now formally reclassified
out of the FAIL count into the "Green-guards" section). Verified with /tmp/p3/zig1:

| Repro | zig1 (dump rc, error) | 0 `.c` | zig0 oracle |
|-------|------------------------|--------|-------------|
| `eu_assign_incompat_payload` | rc=2, `error[3000]: type mismatch in assignment — internal type representations differ` | yes | rejects: `error: type mismatch` (rc=1) |
| `field_access_optional` | rc=2, `error[3000]: cannot access field on optional type; use .? to unwrap first` | yes | rejects: `error: type mismatch` (rc=1) |

**Post-P3-1 accounting: OK=189 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 197 repros**
(189 + 4 + 4 = 197). Raw classifier FAIL stays **8** (green-guards are a sub-bucket of the raw 8).
The 4 green-guards: `eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`,
`euvoid_val_catch`. The 4 real FAILs: 2 import-gap (`field_store_drop`, `test_stub_0`, both
`error[3048]`) + `catch_block_value_producing` (`error[2000]`) + `self_embed_optional_cycle`
(F-8 residual, gcc incomplete-type). No other repro flipped.

---

## P3-2 — defer 2 import-gap repros to the std-lib milestone (2026-08-05)

`field_store_drop` and `test_stub_0` remain classified **FAIL** but are now tracked as
**std-lib-deferred** — NOT compiler defects. Both fail via `error[3048]` because user programs
cannot import compiler-internal modules; no std lib exists yet. **Will pass when zig1 gains a real
std lib.** (Both already documented in QUICK_REF.md "3 frontend-gap repros" / known-issues.)

| Repro | Class | Cause | Will pass |
|-------|-------|-------|-----------|
| `field_store_drop` | FAIL (std-lib-deferred) | `const pal = @import("pal")` → `error[3048]: could not resolve imported file 'pal'` — pre-existing import-resolver gap; a user program cannot import compiler-internal modules | when zig1 gains a real std lib |
| `test_stub_0` | FAIL (std-lib-deferred) | imports nonexistent `"std"` → `error[3048]` | when zig1 gains a real std lib |

**Deferral changes no counts.** Accounting stays **OK=189 / FAIL=4 / green-guards=4 / ICE=0 /
CRASH=0 over 197 repros** (189 + 4 + 4 = 197; raw classifier FAIL stays **8**). The 4 real FAILs:
2 std-lib-deferred import-gap (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`catch_block_value_producing` (`error[2000]`) + `self_embed_optional_cycle` (F-8 residual, gcc
incomplete-type). No other repro flipped.

---

## P3-3 — anon_errset_comparison OK (semantically verified) + adjacent defects (2026-08-05)

Per the P3-3 operator ruling (**Option A**, docs-only closeout): the bare-`!`
`err == error.Bad` comparison is **semantically correct**. An anonymous error literal stores the
raw **name_id** as its C error code (`lower.zig:1191-1206`, `semantic_analyzer.zig:1182`), and
name_id is a **unique-per-name, program-stable interner code** — `string_interner.zig:88-122`
dedups by exact content (`mem_eql` at `:101`), one interner per program (`main.zig:146`), so same
name always yields the same name_id and distinct names can never collide within one program.
Measured **RED==GREEN==1** on zig1 AND the zig0 oracle (matches oracle); all pure-anonymous probes
(`==`/`!=`, cross-fn, distinct-name) match the oracle (`.superpowers/sdd/P3-anonerr-report.md`).

`anon_errset_comparison` upgraded from `**OK**` to **OK (semantically verified)** — it was already
OK since Plan 1 P1-1; this records the semantic justification. **Counts unchanged: OK=189 /
FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 197 repros** (189+4+4=197; raw classifier FAIL
stays 8). No other repro flipped.

**2 adjacent defects found by P3-3 — tracked as follow-ups, NOT fixed (out of scope):**

1. **Switch-on-error exhaustiveness → P3-5.** Switch-case collection in `lower.zig:2919-2934`
   handles only `int_literal`/`enum_literal` case nodes; an `error_literal` case falls to
   `continue` → zero SwitchCase entries → `switch (err) { default: ... }` always takes `default`.
   Affects named AND anonymous error sets; the oracle emits proper `case ERROR_Bad:`. No corpus
   repro or MD5 gate exercises it today. Clean upstream fix (mirror the enum_literal branch).
2. **Error-code representation unification → I3-5 / P3-6.** zig1 accepts inferred→named error-set
   coercions that real Zig also accepts (subset→superset is legal; zig0/z98 is stricter), but then
   MISCOMPARES: anonymous-set errors carry the raw name_id, named-set errors carry the ordinal.
   Only reachable through programs the zig0 oracle rejects, so it is not a corpus classification
   issue. Investigate (I3-5), then implement per ruling (P3-6).

---

## P3-4 + P3-7 — catch_block_value_producing FAIL → OK (2026-08-05)

`catch_block_value_producing` is now **OK** — the last of the 5 frontend-gap repros. Two tasks
flipped it:

- **P3-4 (commit a50e2910, value-producing blocks):** the catch block's trailing bare `99` (no `;`)
  no longer errors `error[2000]: expected ';' but found '}'` — the trailing `;` is now optional
  before `}` in `parserParseExprStmt` (parser.zig:1256-1260) — and `lowerExprOrBlock`
  (lower.zig:3223-3238) now returns the last child's temp, so the catch fallback materializes the
  real `99` instead of an uninitialized local (was garbage `-366458289`).
- **P3-7 (this commit, inline error-set types in type positions):** `helper.zig:1`
  `pub fn try_compute() error{Bad}!i32` — an INLINE error-set declaration in a type position — is
  now fully supported:
  - **Parser (parser.zig:902-930):** the `kw_error` branch of `parserParseType` now checks for a
    trailing postfix `!` after `parserParseErrorSetDecl` and, when present, parses the payload type
    and builds an `error_union_type` node (mirroring the base+`!` path at :914-921). Before: the
    `!` fell out of the type parser → `error[2000]: expected '{' but found token`.
  - **Type-resolver (type_resolver.zig:738-755):** `resolveTypeExprFull` now has an
    `error_set_decl` case — it appends the member name_ids to the registry `xn_items` table and
    registers an anonymous `error_set_type` via `typeRegistryGetOrCreateErrorSet` (content-deduped
    through the registry `es_cache`, mirroring `symbol_registrator.zig:195-210`/`:357-372` named-set
    population). Before: `error{Bad}` (no `!`) fell through to `TYPE_UNDEFINED` (:901-903) and the
    fn return type resolved void → ICE `error[3043]: internal: invalid temp index 0`.
  - **C89 emission (c89_emit.zig):** the anonymous (`name_id==0`) `error_set_type` is now included
    in the synthetic-type emission whitelists (`computeSharedSet`, `emitSharedHeader` sub-passes
    2a/2b, `emitSpecialTypes` sub-passes 2a/2b), so its `typedef int <cname>;` + per-member
    `#define <cname>_<member> <ordinal>` macros are emitted. Before: the whitelist excluded
    `error_set_type`, so the error-code temp's type name was undefined → gcc error.

**Measured (this build):** dump rc=0, 2 `.c` emitted (main + helper), gcc-clean, links, runs
printing **`99`** rc=0. `error{Bad}!i32` parses; bare `error{Bad}` (no `!`) no longer ICEs (dumps
clean, gcc-clean, prints `0`). 4 MD5 gates byte-identical (mud `4644ad13…`, gol `d0d3051d…`,
lisp `f84c8748…`, json `3492a935…`).

**Post-P3-7 accounting: OK=190 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 197 repros**
(190 + 3 + 4 = 197). Raw classifier FAIL **8 → 7** (green-guards remain a sub-bucket of the raw
count). `catch_block_value_producing` moved FAIL→OK. The remaining 3 real FAILs:
2 std-lib-deferred import-gap (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4 green-guards unchanged:
`eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
No other repro flipped.

---

## P3-5 — switch-on-error exhaustiveness FIXED (2026-08-05) — +2 repros (197 → 199)

`switch (err)` over a caught error value (named OR anonymous error set) now emits real
`case <value>:` entries instead of an empty `switch (err) { default: ... }`.

- **Root cause (P3-3 investigation finding #3):** switch-case collection in `lower.zig:2919-2934`
  (and its statement-site twin `lower.zig:3644-3658`) handled only `int_literal` and `enum_literal`
  case nodes; an `error_literal` case node fell to `continue` → zero SwitchCase entries → the
  emitted C `switch (err) { default: ... }` always took `default`.
- **Fix (lower.zig):** added an `error_literal` branch to both switch-case collection sites,
  mirroring the `enum_literal` branch — value resolves via `enum_value_table` (ordinal) when an
  entry is present, else falls back to the raw `node.payload` name_id (anonymous-set case,
  matching the error_literal lowering at `lower.zig:1191-1206`).
- **Companion fix (semantic_analyzer.zig, `semanticAnalyzerResolveSwitchExpr`):** when the switch
  cond type is an `error_set_type` (or `error_union_type`), resolve `error_literal` case nodes
  against the cond error set (pushExpectedType + resolveExpr) so `enum_value_table` gets the
  ordinal — mirroring how `enum_literal` case nodes are resolved for tagged-union switches. Without
  this, a NAMED-set case value would fall back to the raw name_id and never match the produced
  ordinal-coded error.

| Repro | RED (pre-fix) | GREEN (post-fix) | Notes |
|-------|---------------|------------------|-------|
| `switch_on_error_named` | prints `0` (default taken; emitted `switch (err) { default: }`, 0 case entries) | prints `1` (emitted `case 0:`/`case 1:`) | `const E = error{ Bad, Other }`; `E!i32` returns `error.Bad`; catch switch |
| `switch_on_error_anon` | prints `0` (default taken) | prints `1` (emitted `case 23:`/`case 28:` = raw name_ids) | bare `!i32` returns `error.Bad`; catch switch |

Both classify **OK** per the QUICK_REF gate (dump rc=0, 1 `.c`, gcc-clean) in BOTH states — the
defect is runtime-wrong, not a compile failure — so these are new OK repros with a runtime-gap-now-
fixed annotation, NOT FAIL→OK moves. The zig0 oracle emits `case ERROR_Bad:` / `case ERROR_Other:`
and prints `1`; zig1 now matches that runtime behavior.

**Post-P3-5 accounting: OK=192 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 199 repros**
(192 + 3 + 4 = 199; corpus total grows 197 → 199 by 2 new OK repros). Raw classifier FAIL stays
**7** (green-guards remain a sub-bucket of the raw count). The 3 real FAILs unchanged:
2 std-lib-deferred import-gap (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). The 4 green-guards unchanged:
`eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
4 MD5 gates byte-identical (mud `4644ad13…`, gol `d0d3051d…`, lisp `f84c8748…`, json
`3492a935…`). No other repro flipped.

---

## P3-6 — error-code representation unification: per-name registry + `ERROR_<name>` prologue (2026-08-05) — +1 repro (199 → 200)

Operator ruling 2026-08-05: **Option B (zig0-style)**, per `.superpowers/sdd/I3-5-errorcodes-report.md`.
All error codes are now dense per-program **per-name** registry codes (name_id → small int,
1-based, first-use order) instead of per-set ordinals / raw name_id. Fixes the cross-set `e1 == e2`
miscompare for real-Zig-legal subset→superset coercions (both I3-5 probes now print `1`).

- **Registry:** `error_code_registry: U32ToU32Map` (name_id → code) on `CompilerContext`
  (main.zig, next to `enum_value_table`); `hash_mod.u32ToU32MapGetOrAddDense` (look up; miss ⇒
  `count+1`, store). Sema/lower/emitter all route through it.
- **Producers repointed** (ordinal / raw name_id → registry code):
  - sema `semanticAnalyzerResolveExpr` error_literal-under-expected-set (membership check kept).
  - sema `var x = error.Bad` set-scan inference (kept).
  - sema switch-case companion (P3-5) stores the registry code via the error_literal path.
  - lower `error_literal` fallback → `getOrAdd(name_id)` (bare-`!` anon path; same code as named).
  - lower `E.Bad` field-access (type-site + value-site) → `enum_const` with registry code.
  - lower switch-case error_literal fallbacks → `getOrAdd(name_id)`.
  - c89_emit `emitErrorSetType` member `#define`s revalued to registry codes.
- **Prologue macros:** program-global `#define ERROR_<name> <code>` emitted once into
  `zig_special_types.h` (multi-module shared header — every module .h includes it) and inline in
  the single-stream path; skipped when the registry is empty (keeps mud/gol byte-identical).
  Assignment order = sema/lower traversal order (deterministic), finalized by registering all
  error-set members in type order before emission.

| Repro | RED (pre-P3-6) | GREEN (post-P3-6) | Notes |
|-------|----------------|-------------------|-------|
| `errset_cross_set_compare` (NEW) | prints `00` | prints `11` | anon→named + named→named subset→superset `err == error.Bad`; classifies **OK** |

**Post-P3-6 accounting: OK=193 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 200 repros**
(193 + 3 + 4 = 200; corpus total grows 199 → 200 by 1 new OK repro). Raw classifier FAIL stays
**7**; the 3 real FAILs and 4 green-guards unchanged. 4 MD5 gates: **mud + gol byte-identical**
(mud `4644ad13…`, gol `d0d3051d…`); **lisp + json RE-BASELINED** per F-5 AMENDMENT B precedent
("runtime behavior is the gate, not byte-identity"): lisp `dd56cd23…`, json `900cb401…` — both
compile, link, and run correctly (lisp `(+ 1 2)` → `3`, `(foo-bar-baz)` → `Eval error:
UnboundSymbol`; json parses `test.json` identically). No other repro flipped. `@enumToInt(err)`
values change to registry codes (accepted; re-verified at runtime — `error_literal_return` still
prints `1`, all ~30 error repros unchanged).

---

## Task P0 — 3 defensive repros for comptime arithmetic folding gaps (2026-08-06) — +3 repros (200 → 203)

Three defensive repros proving the three comptime-arithmetic-folding pipeline gaps
(plan `.superpowers/plans/2026-08-06-comptime-arithmetic-folding-plan.md`, AMENDMENT P0-A/P0-B):
Gap 1 = `phase_ComptimeEvaluation` (main.zig:339-352) visits only `builtin_call` nodes; Gap 2 =
lowerer binary/unary handlers (`lower.zig:1218-1306`, `:1426-1439`) emit `BIN_*`/`UN_*` LIR
unconditionally while `builtin_call` (`:2456`) checks `comptime_values`; Gap 3 = type_resolver
array-size handler (type_resolver.zig:869-911) misses `mul`/`div`/`mod_op`. Classified with
`/tmp/z1/zig1` per the QUICK_REF corpus classifier.

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `comptime_binop_not_folded` | emission gap | **OK (gap RESOLVED by F1+F2+F4)** — dump rc=0, 1 `.c`, gcc-clean, links, runs printing `40 20 300 3 0 -30 10 30 20 120 7 -31`; `__module_init`-scoped `grep -c '[\*\/\%]'` = **0** (all 12 consts emit `int_const`: 40/20/300/3/0/-30/10/30/20/120/7/-31 — see NOTES.md) | Gap 1: bare binary/unary nodes never reached `comptimeEvalEvaluate` — FIXED by F1 (bitwise/shift comptime ops) + F2 (var_decl binop/unary inits folded in phase_ComptimeEvaluation) + F4 (lowerer guard consumes the fold) |
| `comptime_lower_ignores_fold` | emission gap | **OK (gap RESOLVED by F4+F5)** — identical measured state to repro 1 (same source; isolates Gap 2); `__module_init`-scoped `grep -c '[\*\/\%]'` = **0** | Gap 2: lowerer binary/unary handlers never consulted `comptime_values` — FIXED by F4 (comptime_values guards on 10 binary op handlers, INT_LIT→I32 remap) + F5 (negate/bit_not guards) |
| `comptime_array_size_gap` | semantic gap | **OK (runtime gap RESOLVED by F6)** — dump rc=0, 1 `.c`; the arrays now resolve `u8[4000]`/`u8[40]`/`u8[2]` (emitted `typedef unsigned char …[4000];`/`[40];`/`[2];`), gcc-clean (rc=0) — no longer a silent type-drop (pre-fix the consts degraded to uninitialized `int` globals; counted OK+runtime-gap per ruling P0-E) | Gap 3: type_resolver array-size handler missed `mul`/`div`/`mod_op` → `arr_len`=0 → `TYPE_UNDEFINED` — FIXED by F6 (mul/div/mod arms, type_resolver.zig:888-896) |

**Post-P0 accounting: OK=195 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 203 repros**
(195 + 4 + 4 = 203; corpus total grows 200 → 203 by 3 new repros). OK 193→195 (+2 = repros 1+2,
emission-gap annotations); FAIL 3→4 (+1 = `comptime_array_size_gap`). Raw classifier FAIL **7 → 8**
(green-guards remain a sub-bucket of the raw count). **UPDATED by "Fix wave 1" (operator rulings
P0-D/P0-E) below: `comptime_array_size_gap` reclassified OK+runtime-gap (FAIL 4→3) and
`fn_varargs_unsupported` added as FAIL (3→4) → final OK=196 / FAIL=4 / green-guards=4 @204 (raw
FAIL=8).** No other repro flipped.

**Source-note (deviation from the plan's verbatim draft source, see
`.superpowers/sdd/task-P0-report.md`):** the plan's draft main.zig for repros 1+2 does not compile
on the current compiler — (1) the parser requires `;` after `@cInclude(...)`; (2) varargs `...`
in `extern fn` params is not parseable (`error[2000]`); (3) `const A`/`const B` referenced ONLY
from other const initializers never receive C storage-global decls (`zG_..._A` undeclared in
`__module_init` → gcc error). Corrections applied: `;` after `@cInclude`, fixed-arity `printf`,
literal operands inlined. The tested gap is unchanged (12 bare binary/unary module-scope const
ops that must fold to `int_const`).

**Discrepancy note (repro 3, evidence over prediction — RESOLVED by ruling P0-E):** the
brief/ruling predicted `error: ISO C forbids zero-size array` for `comptime_array_size_gap`; the
measured pre-fix state is instead a **silent semantic miscompile** (arrays dropped, consts →
uninitialized `int` globals, gcc-clean). It was initially counted **FAIL** per AMENDMENT P0-B
(real gap, `int`-drop is wrong output), NOT because gcc rejects it — flagged for operator
re-adjudication under the classifier convention (gcc rc==0 ⇒ OK, per the
`comptime_neg_int`/`load_global_array_copy` runtime-gap precedent). **Operator ruling P0-E
(2026-08-06): classify it OK with runtime-gap annotation.** See "Fix wave 1" below.

---

## Fix wave 1 — operator rulings P0-D/P0-E (2026-08-06) — +1 repro (203 → 204)

- **P0-E (reclassify):** `comptime_array_size_gap` **FAIL → OK with runtime-gap annotation**. Under
  the QUICK_REF gcc-exit classifier the emission is gcc-clean (rc=0), so it is **OK**, not FAIL.
  The gap is a **silent semantic miscompile**: array types resolve `TYPE_UNDEFINED`
  (type_resolver.zig:869-911 misses `mul`/`div`/`mod_op` → `arr_len`=0), so
  `CELLS`/`HALF`/`REM` degrade to uninitialized `int` globals (no `u8[N]`, no `[0]`, gcc-clean).
  Counted OK following the `comptime_neg_int`/`load_global_array_copy` runtime-gap precedent; the
  miscompile is tracked as a runtime gap until F3 fixes it (re-verified 2026-08-06: dump rc=0, 1
  `.c`, gcc rc=0, emitted `int zG_..._CELLS;` / `int zG_..._HALF;` / `int zG_..._REM;`).
- **P0-D (new tracking repro):** the plan's original `extern fn printf(fmt: [*]const u8, ...) i32;`
  does not compile — parser.zig has NO varargs (`...`) support → `error[2000]: expected identifier
  but found token`. Recorded as a standalone tracking repro:

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `fn_varargs_unsupported` | parse gap | **FAIL** — dump rc=2, `error[2000]: expected identifier but found token` at the `...`, 0 `.c` emitted (frontend parse gap) | parser.zig has no varargs support; out of comptime-arithmetic scope — tracked as a known gap |

**Post-P0-fix-wave-1 accounting: OK=196 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 204
repros** (196 + 4 + 4 = 204; corpus total grows 200 → 204 by 3 comptime-arithmetic repros + 1
varargs tracking repro). OK 193→196 (repros 1+2 with emission-gap annotations + repro 3
reclassified OK+runtime-gap per P0-E); FAIL 3→4 (+1 = `fn_varargs_unsupported`, P0-D). Raw
classifier FAIL stays **8** (green-guards remain a sub-bucket of the raw count). The 4 real FAILs:
2 std-lib-deferred (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type) + `fn_varargs_unsupported`
(parser varargs gap, `error[2000]`). The 4 green-guards unchanged: `eu_assign_incompat_payload`,
`field_access_optional`, `var_declared_void`, `euvoid_val_catch`. No other repro flipped.

## Task F7 — `comptime_u64_fold_overflow` (u64 const fold >2^32 masking) (2026-08-06) — +1 repro (204 → 205)

Operator ruling I1-A (serious bug): a u64-annotated const whose folded value exceeds 2^32
(`const X: u64 = 3000000000 * 2;` = 6000000000) gets typed I32 by the F4/F5 guard (bare binop
resolves TYPE_INT_LIT → remapped I32) and the `int_const` emitter masks the value to 32 bits →
wrong value (1705032704 / 0). Reproduced + FIXED in `main.zig` (commit `fix(F7): …`):

- **Root cause (2 defects, both in `main.zig` phase_SemanticAnalysis):**
  1. The declared type is stored on the var_decl node (`resolved_types[var_decl]`, set at
     main.zig:397), but is then **clobbered** to the init type (INT_LIT) by the unconditional
     `resolvedTypeTableSet(decls[di], init_type)` at main.zig:428-430 → the storage global
     (main.zig:639 reads `resolved_types[var_decl]`) is emitted `int` → truncates at the store.
  2. The F4/F5 fold guard types the temp from `resolved_types[binop]` (INT_LIT → I32); the
     declared u64 type is never threaded onto the init node for module-scope decls (fn-scope
     var_decls already get this at sema:1705-1708).
- **Fix (Option B, "B-lite"):** (a) gate the `resolved_types[var_decl] = init_type` write on
  `existing == null` so a known declared type is never clobbered (storage globals now type
  correctly); (b) mirror the fn-scope behavior — after resolving the module-scope init, set
  `resolved_types[child_1] = declared type` when the decl is annotated. The F4/F5 guard then
  reads the declared type (u64) with **no lower.zig change**. Verified: `1:1705032704
  3000000000 1:0` (was `0:1705032704 3000000000 0:0`).

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `comptime_u64_fold_overflow` | runtime-gap | **OK with runtime-gap annotation (pre-fix) → OK post-fix** — dump rc=0, 1 `.c`, gcc-clean, runs printing `0:1705032704 3000000000 0:0` (X=6000000000 and Z=4294967296 masked to 32 bits; Y=3000000000 control correct); post-fix prints `1:1705032704 3000000000 1:0`. Note: on -m32 `%lu` is 32-bit and `%llu` reads adjacent varargs slots pre-fix, so the repro prints each u64 as two i32 halves (`hi = @intCast(u64,X)>>32`, `lo = @intCast(u64,X) & @intCast(u64,4294967295)`) — see NOTES.md | F4/F5 guard types folded temps/storage globals from the binop's INT_LIT instead of the declared u64 |

**Post-F7 accounting: OK=197 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 205 repros**
(197 + 4 + 4 = 205; corpus grows 204 → 205 by `comptime_u64_fold_overflow`, counted OK).
Raw classifier FAIL stays **8** (4 green-guards + `field_store_drop`, `test_stub_0`
(std-lib-deferred), `self_embed_optional_cycle`, `fn_varargs_unsupported`). No other repro
flipped; 4 MD5 gates byte-identical; test_analyzer_bin PASS; build_test.sh 5/4 (baseline-identical).

## Task F8 — `comptime_const_chain` (ident_expr const-chain folding) (2026-08-06) — +1 repro (205 → 206)

Operator ruling I1-B ("include now"): `comptimeEvalEvaluate` must resolve `ident_expr` operands by
following const chains, so `const B: i32 = A + 5;` (where `const A: i32 = 30;`) folds to 35 and
`const C: i32 = B * 2;` folds to 70. Implemented in `comptime_eval.zig` as a depth-guarded
`ident_expr` branch (mirrors the array-size const-chain path `evalConstU32Full`,
type_resolver.zig:579-598: `symbolRegistryQualifiedLookup` across all module tables → const check
`(flags & 0x01) == 0` → recurse into `decl.child_1`), with a depth-16 cap so const cycles
(`const A = B + 1; const B = A + 1;`) cannot infinitely recurse.

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `comptime_const_chain` | **FAIL** (gcc error, NOT merely a fold gap) | **OK post-fix** — dump rc=0, 1 `.c`, gcc-clean, runs printing `3570`; emitted `__module_init` stores `zT_0 = 35;` / `zT_1 = 70;` (int_const, no runtime `+`/`*`) | Pre-F8 the lowerer emits `load_global` for `A` in `A + 5`, but `A` (a non-storage const, literal init) gets **no C storage-global decl** → `zG_..._A` undeclared → **gcc FAIL**. F8 folds the ident away so the load is eliminated. Also guards: const-chain through two hops (`B * 2` from `A + 5`) |

**Post-F8 accounting: OK=198 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 206 repros**
(198 + 4 + 4 = 206; corpus grows 205 → 206 by `comptime_const_chain`, counted OK; pre-F8 it
classified **FAIL**, so this is a genuine FAIL→OK flip). Raw classifier FAIL stays **8** (4
green-guards + `field_store_drop`, `test_stub_0` (std-lib-deferred), `self_embed_optional_cycle`,
`fn_varargs_unsupported`). No other repro flipped. **MD5 gate: gol RE-BASELINED** — the emitted C
for `examples/z98/game_of_life` changes because `@intCast(i32, WIDTH)` / `@intCast(i32, HEIGHT)`
(WIDTH/HEIGHT are `const usize`) now fold at comptime (previously a runtime `(int)` load+cast);
runtime output is byte-identical (verified by run diff), so per the F-5 AMENDMENT B precedent
("runtime behavior is the gate, not byte-identity") the gol baseline is updated from
`d0d3051d…` to `e2f4c625…`. mud/lisp/json gates unchanged and byte-identical.

---

## F9 — gate sweep + comptime gap annotations cleared (2026-08-06)

Final task of the comptime arithmetic folding plan. All 5 comptime-arithmetic repros are now fully
OK with their emission/runtime-gap annotations **cleared** — the gaps were resolved by F1-F8.
The full gate battery was re-run at HEAD with a fresh /tmp bootstrap (`/tmp/f9b/zig1`, zig0 rc=0,
gcc rc=0, 0 errors); evidence in `.superpowers/sdd/task-F9-report.md`.

**Fix commits (comptime arithmetic folding, all 2026-08-06):**

| Commit | Task | Change |
|--------|------|--------|
| `7dc119a6` | F1 | comptime_eval.zig: add `bit_and`/`bit_or`/`bit_xor`/`shl`/`shr` to `comptimeEvalBinOp` (with shift-amount >=64 → null guard) |
| `dacf8cf6` | F2 | comptime_eval.zig: add `bit_not` and route the 12 binary/unary ops to comptime binop evaluation (`comptimeEvalEvaluate` binop arm) |
| `94853c65` | F3 | main.zig `phase_ComptimeEvaluation`: fold `const var_decl` binop/unary **inits** (not just `builtin_call`) into `comptime_values` |
| `ec71f9ad` | F4 | lower.zig: `comptime_values` guards on the 10 binary op handlers (add/sub/mul/div/mod/bit_and/bit_or/bit_xor/shl/shr) with INT_LIT→I32 remap — emit `int_const` when folded |
| `5ed90251` | F5 | lower.zig: `comptime_values` guards on `negate` + `bit_not` unary handlers (same INT_LIT→I32 remap) |
| `6dd614e7` | F6 | type_resolver.zig array-size handler: add `mul`/`div`/`mod_op` arms to `evalConstU32Full` size eval (closes the `comptime_array_size_gap` silent type-drop) |
| `827e0221` | F7 | main.zig `phase_SemanticAnalysis`: (a) gate the `resolved_types[var_decl] = init_type` write on `existing == null` so declared types aren't clobbered; (b) thread the declared type onto the init node for annotated module-scope consts — folded u64 consts >2^32 keep their declared width (fixes `comptime_u64_fold_overflow`) |
| `bf5d3636` | F8 | comptime_eval.zig: `ident_expr` const-chain branch in `comptimeEvalEvaluateDepth` (depth-16 guarded), mirroring the array-size `evalConstU32Full` chain — folds `const B: i32 = A + 5` from `const A` (fixes `comptime_const_chain` gcc FAIL) |

**Gate-sweep results (measured, /tmp/f9b/zig1):**

- **Repros 1+2** (`comptime_binop_not_folded`, `comptime_lower_ignores_fold`): dump rc=0, gcc rc=0,
  run rc=0, prints `40 20 300 3 0 -30 10 30 20 120 7 -31`; `__module_init`-scoped
  `grep -c '[\*\/\%]'` = **0** (all 12 consts emit `int_const` — emission gap closed).
- **Repro 3** (`comptime_array_size_gap`): dump rc=0, gcc rc=0; emitted `typedef unsigned char
  …[4000];` / `…[40];` / `…[2];` — arrays resolve `u8[4000]`/`u8[40]`/`u8[2]` (runtime gap closed).
- **Repro u64** (`comptime_u64_fold_overflow`): dump rc=0, gcc rc=0, run prints
  `1:1705032704 3000000000 1:0` (X=6000000000, Z=4294967296 correct via hi:lo halves).
- **Repro** `comptime_const_chain`: dump rc=0, gcc rc=0, run prints `3570`; `__module_init` stores
  `zT_0 = 35;` / `zT_1 = 70;` (int_const, no runtime `+`/`*`).
- **Varargs** (`fn_varargs_unsupported`): stays **FAIL** — dump rc=2, `error[2000]: expected
  identifier but found token` at `...`, 0 `.c` emitted (out of comptime scope).
- **Full corpus**: **206 repros, OK=198 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0**
  (198 + 4 + 4 = 206; raw classifier FAIL = 8 — the 4 green-guards are a sub-bucket).
  FAIL count unchanged vs the F8 baseline; no repro flipped; the 4 real FAILs are the 2
  std-lib-deferred import gaps (`field_store_drop`, `test_stub_0` — `error[3048]`),
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type), and `fn_varargs_unsupported`
  (varargs parse gap).
- **4 MD5 gates byte-identical** to the current baselines: mud `4644ad1349c55af80fa1a18fe0e17989`,
  gol `e2f4c62515b4ab5e5c5b1202f7c2e12e`, lisp `dd56cd23984d2533eebd244ffe593791`,
  json `900cb401779aab11bcf22ce35100323c`.
- **test_analyzer_bin PASS** (43/43 tests ok, run rc=0).

This is the final accounting for the plan: **206 repros, OK=198 / FAIL=4 / green-guards=4** —
the comptime arithmetic folding feature is complete and gated.

---

## Task F1 — `@intCast` range-check (Option B + scope b) (2026-08-06) — +1 repro (206 → 207)

Per I1 (`/workspace/znineeight/.superpowers/sdd/I-intcast-range-report.md`) + operator ruling
(binding): the lowerer's explicit `@intCast` handler always set `is_checked=0`, so zig1 lowered
`@intCast(i32, i64_expr)` to a raw C `(int)` cast — silently wrapping on overflow (lisp `(fact 13)`
printed garbage `1932053504` instead of panicking). Fix site = **Option B** (c89_emit wraps via the
existing `int_cast.is_checked` field + source-aware per-pair `__bootstrap_<DST>_from_<SRC>` naming);
scope = **(b) full oracle rule** (check iff narrowing OR same-width reinterpret).

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `intcast_range_check` | runtime-gap: dump rc=0, gcc clean, prints `-2147483648` (wrapped), rc=0 — **NO panic**; emitted `zT_6 = (int)i;` | **OK post-fix** — dump rc=0, 1 `.c`, gcc-clean; emitted `zT_6 = __bootstrap_i32_from_i64(i);`; run PANICS with `panic: integer cast overflow in @intCast`, nonzero exit (rc=134) — the intended fix, matching the zig0 oracle | guards: the in-range path must still pass (i32-from-i64 of a small value prints correctly); comptime-folded `@intCast` literals skip the runtime cast; pure widening stays a raw cast |

**Implementation:** lower.zig computes src type via `getTempType` and sets `is_checked=1` when
`src_bits > dst_bits` OR (`src_bits == dst_bits` AND signedness differs); c89_emit's `.int_cast`
checked arm builds `__bootstrap_<DST>_from_<SRC>` from `c.target` + `getTempTypeByIndex`; the 19
oracle helpers were added to `sf/src/include/zig_runtime.c` (definitions) + `sf/src/include/
zig_runtime.h` (C89 `static` definitions, per-TU self-sufficient — the oracle's own header pattern
is `ZIG_INLINE ZIG_UNUSED`), message standardized to `"integer cast overflow in @intCast"`.
`std_checked_cast_*` (upper-bound-only, false-panics on negatives) is NOT used.

**Post-F1 accounting: OK=199 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 207 repros**
(199 + 4 + 4 = 207; corpus grows 206 → 207 by `intcast_range_check`, counted OK — no FAIL
increase). Raw classifier FAIL stays **8**. No other repro flipped.

**MD5 gate — ALL 4 RE-BASELINED (scope b):** mud, gol, lisp, json each contain explicit runtime
`@intCast` sites that are now checked. New values: mud `0064a08149b07aa591033210ffce68f5`,
gol `51d6d078bdecad022318bded23182f72`, lisp `e54be381967cab4a3f0886e106166771`,
json `6528f26f396092976b46938482a4f0d4`. Runtime-verified identical except lisp `(fact 13)` now
PANICS (the intended fix); per the F-5 AMENDMENT B precedent ("runtime behavior is the gate, not
byte-identity"). Per-gate helper counts: mud `i32_from_usize` x4 + `usize_from_i32` x1; gol
`i32_from_usize` x2 + `usize_from_i32` x2; lisp `i32_from_i64`, `i32_from_u32`, `i32_from_usize`,
`u32_from_i32`, `u8_from_i32`, `usize_from_i32`, `c_char_from_u8`; json `usize_from_i32` x1.
(json's legacy-runtime link — `src/runtime/zig_runtime.c` — lacks the new helpers, so the header
`static` definitions are what make the multi-module json gate link; mud/gol/lisp additionally link
the extern defs in `sf/src/include/zig_runtime.c`.)

## Task F2 — `ice_literal_overflow` (u64-safe int_literal marker) (2026-08-06) — +1 repro (207 → 208)

The `int_literal` lowering marker (`ILR:i … v<value>`) called
`itoa_mod.itoa(@intCast(u32, val), …)` with `val` the u64 literal value. Since
F1's `@intCast` range-check, that cast lowers to the checked
`__bootstrap_u32_from_u64`, so any program that runtime-lowers a literal >= 2^32
aborted the compiler itself (`PANIC: integer overflow in @intCast`), dump rc=134.
The lowering pipeline is correct — only the marker was broken. Fixed by adding
`pal.markerWriteInt64` (itoa64, `[24]u8` buffer) and using it for the value marker.

| Repro | RED (pre-fix) | Classification (measured) | Guards |
|-------|---------------|---------------------------|--------|
| `ice_literal_overflow` | **ICE** (dump rc=134, SIGABRT) | **OK post-fix** — dump rc=0, 1 `.c`, gcc-clean, runs printing `1:705032704 1:0` (correct hi/lo halves of X=5000000000 and Y=4294967296) | guards: any literal >= 2^32 that reaches runtime lowering must not crash the compiler; the `--markers` ILR trace renders the full u64 value (`ILR:i39v5000000000`) |

**Note on repro form:** the brief's exact const-only source (`pub const X: u64 =
5000000000;` + `print_u64(X)`) does NOT reproduce the ICE on the current tree —
F8's ident_expr const-chain fold resolves `X` at comptime, so the literal never
reaches the `int_literal` runtime-lowering marker. The repro keeps the brief's
consts (the program still contains literals >= 2^32) AND adds a runtime-lowered
literal (`var sink: u64 = 5000000000;`) that exercises the marker path. Pre-fix
the repro dumps rc=134; post-fix rc=0. See `ice_literal_overflow/NOTES.md`.

**Post-F2 accounting: OK=200 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over
208 repros** (200 + 4 + 4 = 208; corpus grows 207 → 208 by `ice_literal_overflow`,
counted OK — the pre-fix ICE becomes a clean post-fix OK, so no FAIL increase).
Raw classifier FAIL stays **8**. The 4 real FAILs unchanged:
`field_store_drop` + `test_stub_0` (std-lib-deferred, `error[3048]`),
`self_embed_optional_cycle` (F-8 residual), `fn_varargs_unsupported` (varargs
parse gap). **4 MD5 gates byte-identical** (markers → stderr only; emitted C
unchanged): mud `0064a08149b07aa591033210ffce68f5`, gol
`51d6d078bdecad022318bded23182f72`, lisp `e54be381967cab4a3f0886e106166771`,
json `6528f26f396092976b46938482a4f0d4`. test_analyzer_bin PASS.

---

## Task F5 — varargs end-to-end (`@cVaStart`/`@cVaArg`/`@cVaEnd` + `...` emission + extern prototypes) (2026-08-06) — +1 repro (208 → 209)

4-item compiler-gaps plan Task F5 (`.superpowers/sdd/task-F5-brief.md`). Full
varargs support: Z98 variadic fn bodies read their `...` args via `va_list` +
`@cVaStart`/`@cVaArg`/`@cVaEnd`; `...` is emitted in C fn prototypes; variadic
externs get C prototypes (Option B); `stdarg.h` is emitted gated on actual
`va_*` usage.

| Repro | RED (pre-fix) | Classification (measured, /tmp/zigf5b/zig1) | Guards |
|-------|---------------|---------------------------|--------|
| `fn_varargs_unsupported` | parse gap → F3 OK but no prototype emission | **OK post-F5** — dump rc=0; emitted header carries the Option B extern prototype `int printf(unsigned char*, ...);` (name-passthrough); no `stdarg.h` (no `va_*` use); gcc-clean, links + runs rc=0 | variadic extern must get a C prototype; no `@cInclude`'d header may conflict with it |
| `fn_varargs_body` (NEW) | n/a (new repro) | **OK** — dump rc=0; emitted `#include <stdarg.h>`, `int zF_..._sum(unsigned int count, ...) {`, `va_start(zL_vl, zL_count);`, `zT_11 = va_arg(zL_vl, int);`, `va_end(zL_vl);`, `int printf(unsigned char*, ...);`; gcc-clean; runs printing `sum=60` (the KEY proof `sum(3, 10, 20, 30)` = 60 via `@cVaArg`), rc=0 | a Z98 variadic body must read args; no `@cInclude("<stdio.h>")` with a variadic printf (type conflict `unsigned char*` vs `const char*`) |

**Implementation summary:**
- lower.zig: `@cVaStart`/`@cVaArg`/`@cVaEnd` name_ids in `lowererInit`;
  builtin dispatch inserted after `@ptrToInt`, before the `ec.len>=2` cast
  block; `lowerFn` reads `FnPayload.flags_packed` (bit0) → `func_ptr.is_variadic`
  (the `child_0==0` anytype-marker branch is **kept as a defensive OR**, NOT
  removed — see deviations below).
- c89_emit.zig: 3 emitting `.va_start`/`.va_arg`/`.va_end` arms; `stdarg.h`
  gated on any `va_*` LirInst in the TU at 3 sites (emitModuleHeader,
  emitModuleHeaderFile, emitModuleFile); `emitFunctionForwardDecl`
  name-passthrough for externs; the two extern-prototype guards
  (`:1962`/`:2108`-era) now `is_extern==0 OR is_variadic!=0`.

**Deviations from the brief's literal text (both REQUIRED to keep the 4 MD5
gates byte-identical — see Task F5 report):**
1. **`lower.zig:4680` child_0==0 branch is kept as a defensive no-op-instead-of
   removal.** The brief premised "no gate has a variadic fn"; in fact **mud and
   gol both define `print(fmt, *const c_char, args: anytype)`** (anytype →
   `child_0==0` param) whose C signature relies on the marker branch emitting
   `...` (`void zF_..._print(char*, ...);` is in both baselines). Making it a
   pure no-op deletes `...` from those signatures → mud/gol MD5 drift + gcc
   break. Kept as an OR with the flags_packed read (true `...` still works).
2. **`stdarg.h` gating is on actual `va_*` LIR insts, not on `is_variadic`.**
   The brief's premise "no gate has a variadic fn" is also wrong for mud/gol
   (their anytype-print has `is_variadic=1` but never uses `va_*`); gating on
   `is_variadic` would inject `#include <stdarg.h>` into mud/gol → MD5 drift.
   Gating on `va_*` insts keeps mud/gol/lisp/json byte-identical AND still
   emits `stdarg.h` for real varargs bodies.

> **F5b RESOLUTION (Task F5b, AMENDMENT 5, 2026-08-06, commit `ef529f42`):**
> deviation 1 is now MOOT. F5b migrated mud/gol `print(fmt, args: anytype)` to a
> true trailing `...` (`print(fmt, ...)`) and **deactivated** the `child_0==0`
> anytype-marker branch (its `else { is_variadic = 1 }` was removed from
> `lowerFn`) — `is_variadic` now comes solely from the F3 flag-bit path
> (`FnPayload.flags_packed` bit0, set by parser flag 0x01 via
> type_resolver.zig:1126-1127). mud/gol re-baselined to `50beb1bf…` /
> `0d8f0092…` (runtime byte-identical, AMENDMENT B precedent); lisp/json
> unchanged. Deviation 2 (stdarg.h gating on actual `va_*` insts) remains in
> force. A variadic fn with ZERO fixed params (`fn f(...)`) is now rejected
> `error[3012]` (final-review fix, 2026-08-06).

**Post-F5 accounting: OK=202 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over
209 repros** (202 + 4 + 3 = 209; corpus grows 208 → 209 by `fn_varargs_body`;
`fn_varargs_unsupported` FAIL→OK). Raw classifier FAIL stays **7** (4
green-guards sub-bucket). The 3 real FAILs: `field_store_drop` + `test_stub_0`
(std-lib-deferred, `error[3048]`) + `self_embed_optional_cycle` (F-8 residual).
**4 MD5 gates byte-identical**: mud `e306b1874e51e06a23b708bcd79fec6d`, gol
`51d6d078bdecad022318bded23182f72`, lisp `55044a1f64011bc644cddbcf73b5de93`,
json `b5f56ebd51d2f0fcd379a1e083594462`. test_analyzer_bin PASS.

---

## Task F7 — gate sweep + docs + final review prep (2026-08-06) — 4-item plan CLOSEOUT

Final task of the 4-item compiler-gaps plan (brief `.superpowers/sdd/task-F7-brief.md`). Full
corpus + MD5 gate sweep at HEAD with a fresh /tmp bootstrap (`/tmp/f7build/zig1`, zig0 rc=0, gcc
rc=0, 0 errors); evidence in `.superpowers/sdd/task-F7-report.md`. **Docs-only — no sf/src
changes.**

**Final accounting (measured): 209 repros, OK=202 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
(202 + 4 + 3 = 209; raw classifier FAIL = 7). Identical to the v20 totals — **no repro flipped**
during the final sweep. The plan's Step-1 prediction ("210 repros, OK=200/FAIL=3/gg=4") was
**STALE**: it double-counted `fn_varargs_unsupported`, which was already in the 208 baseline
(209 = 208 baseline + `fn_varargs_body`). The corrected accounting is recorded in the Totals
section at the top of this file.

**4-item fixes — all complete (fix refs):**

| # | Item | Fix | Key commit(s) | Gate evidence |
|---|------|-----|---------------|---------------|
| 1 | `@intCast` narrowing + reinterpret range-check | c89_emit emits `__bootstrap_<DST>_from_<SRC>` (checked) — see Task F1 section | `14f31511` | `intcast_range_check` OK; run PANICS (`integer cast overflow in @intCast`) rc=134, matching oracle |
| 2 | ICE on literals ≥ 2^32 | u64-safe `int_literal` marker via `pal.markerWriteInt64` — see Task F2 section | `5d280a6d` | `ice_literal_overflow` OK; prints `1:705032704 1:0` rc=0 |
| 3 | Full varargs (`@cVaStart`/`@cVaArg`/`@cVaEnd` + `va_list` + `...` emission + extern variadic prototypes) — see Task F5 section | `4448d187` (parser bit0 flag), `b8deb732` (va_list TYPE_VA_LIST=21 + LIR), `c420a277` (emission), `ef529f42` (F5b) | `fn_varargs_unsupported` FAIL→OK (runs `printf`); `fn_varargs_body` OK — **`sum=60`** rc=0 |
| 4 | Lisp closures capture current env | `eval.zig:124` `env_to_value(env.*,…)` → `curr_env.*` — see `examples/z98/lisp_interpreter_curr/NOTES.md` | `0cb7891c` | `((make-adder 5) 3)`→8, `((add 10) 1)`→11, `((make-func 42))`→42 (were `UnboundSymbol`) |

**MD5 gates (byte-identical to the current baselines — no re-baseline needed):**
mud `50beb1bf5edc4cbb638f84aa027ffade`, gol `0d8f0092c22c04375482a198691a3957`,
lisp `605b597e8b7cff60de0ce84a0593e743`, json `b5f56ebd51d2f0fcd379a1e083594462`.

**Runtime spot-checks (this sweep):** `fn_varargs_body` → `sum=60` rc=0; `intcast_range_check` →
rc=134 `panic: integer cast overflow in @intCast` (the intended fix); `ice_literal_overflow` →
`1:705032704 1:0` rc=0; lisp closures `8`/`11`/`42`; `((twice square) 3)` → SEGFAULT (rc=139);
`(fact 13)` → rc=134 (F1 range-check, intended).

**Known lisp limitations (documented in lisp NOTES.md — NOT compiler defects, operator-accepted):**
`((twice square) 3)` / `((compose square square) 3)` SEGFAULT (env-capture cycle in lisp source,
exposed by the F6 fix — was `UnboundSymbol`); `(countdown 3000)` OOM (~3000 threshold); post-OOM
REPL dead (no `sand_reset` on the error path); `(fact 13)` PANICS (correct — F1 range check).

No other repro flipped; `fn_varargs_unsupported` stays OK; 4 MD5 gates byte-identical;
`test_analyzer_bin` PASS (from prior F-tasks). This is the **final accounting for the plan**.

---

## I-task: rogue_mud build attempt — labeled_stmt frontend gap (2026-08-07) — +1 repro (209 → 210)

Investigation task: attempt to build `examples/z98/rogue_mud/` with the current zig1
(`/tmp/zigaps/zig1`, fresh HEAD bootstrap 2026-08-07, zig0 rc=0, gcc rc=0, 0 errors). The
pre-analysis predicted SUCCESS (all patterns well-tested + the catch-block-expression fix P3-4/P3-7);
the actual dump FAILS at type resolution.

| Repro | RED (measured) | Classification | Guards |
|-------|----------------|----------------|--------|
| `labeled_stmt_unhandled` | dump rc=2, `error[3020]: internal error: unhandled node kind in type resolution`, 0 `.c` emitted | **FAIL** (real frontend gap; rc=2 + `error[3020]` is outside the ICE regex — not an ICE, not a green-guard) → **OK post-F1 (2026-08-07)** — dump rc=0, 1 `.c`, gcc-clean, links, runs rc=0 and TERMINATES (the labeled `break :game_loop` now matches the loop via `current_label` propagation; pre-fix it was a no-op and `while(true)` HUNG) | `semanticAnalyzerResolveStmtIter` (semantic_analyzer.zig:1599-1778) has no `labeled_stmt` (AstKind 82) case → generic `else` (:1773) forwards to `resolveExpr` → unhandled-else (:1424-1429) emits error[3020]. Correct behavior: unwrap the label and push the wrapped child onto the stmt work stack — now implemented (parser.zig + semantic_analyzer.zig + lower.zig; see Task F1 section below) |

**Dump diagnostics (rogue_mud):** 2× `error[3020]`, one per labeled statement in the program —
`main.zig:92` `game_loop: while (true)`, `lib/scenario.zig:59` `bsp_loop: while (stack.len > 0)`.
Both are the SAME distinct failure (kind 82). The reported locations (`main.zig:32:2`,
`scenario.zig:159:8`) are BOGUS — the 3020 diagnostic passes `node_idx` as both span ends
(semantic_analyzer.zig:1428), so the reported file:line never matches the labeled statement.
Note: other latent rogue_mud gaps may hide behind this blocker (unverifiable without a fix); the
labeled_stmt gap is the only DISTINCT failure actually observed.

**Oracle verification:** `./sf/build/zig0 -o out.c repro` accepts the labeled loop (rc=0, emits C)
— labeled statements are valid Z98, so this is a genuine compiler gap, not a correct rejection.
zig1 dump for the repro: rc=2, `error[3020]`, 0 `.c` (markers `ST:N<node> ST:K82`).

**Post-repro accounting: OK=202 / FAIL=4 / green-guards=4 / ICE=0 / CRASH=0 over 210 repros**
(202 + 4 + 4 = 210; corpus grows 209 → 210 by `labeled_stmt_unhandled`, counted FAIL). Raw
classifier FAIL **7 → 8** (green-guards remain a sub-bucket of the raw count). The 4 real FAILs:
2 std-lib-deferred (`field_store_drop`, `test_stub_0`, both `error[3048]`) +
`self_embed_optional_cycle` (F-8 residual, gcc incomplete-type) + `labeled_stmt_unhandled`
(error[3020], sema labeled_stmt gap). The 4 green-guards unchanged:
`eu_assign_incompat_payload`, `field_access_optional`, `var_declared_void`, `euvoid_val_catch`.
No existing repro flipped. Investigation complete — no compiler fixes made.

---

## Task F1 — labeled statement support in parser, sema, lowerer (2026-08-07) — FAIL→OK

The `labeled_stmt_unhandled` repro (added 2026-08-07 by the rogue_mud I-task) is now **OK**:
`game_loop: while (true) { break :game_loop; }` dumps, compiles, links, and **runs rc=0 and
TERMINATES** (pre-fix the labeled `break :game_loop` matched no loop and was a no-op, so the
`while(true)` HUNG at runtime). 5 edits in 3 files (plan `labeled statement support implementation
plan` `37e1892a`, AMENDMENT 1 `50723411`):

1. **Parser (parser.zig:1285 + :1299):** `parserParseLabeledStmt` + `parserParseLabeledBlockExpr`
   now store `label_tok.value.string_id` in the `labeled_stmt` node payload (was hardcoded `0`),
   so `break :label` / `continue :label` can match it.
2. **Sema stmt dispatcher (semantic_analyzer.zig:1767):** `labeled_stmt` case added to
   `semanticAnalyzerResolveStmtIter` before `defer_stmt` — transparent unwrap: pushes
   `node.child_0` onto the stmt work queue (mirrors the defer_stmt unwrapper); one case covers
   while/for/block/if/switch inner kinds.
3. **Sema expr redirect (semantic_analyzer.zig:1341):** `labeled_stmt` added to the
   var_decl/defer/errdefer branch → delegates back to `semanticAnalyzerResolveStmtIter`
   (defensive; prevents the `error[3020]` unhandled-else crash if a labeled_stmt ever reaches
   resolveExpr).
4. **Lowerer unwrap (lower.zig:3516):** `labeled_stmt` case in `lowerStmt` recurses into
   `node.child_0`, saving/setting/restoring `self.current_label = node.payload` around the
   recurse.
5. **Edit 4b — label propagation (AMENDMENT 1, required):** `LirLowerer` gains `current_label:
   u32` (init 0); all 3 loop-push sites (while :3627, for-range :3726, for-slice :3780) now use
   `.label_id = self.current_label` instead of hardcoded `0`. The original 4-edit version was
   verified unsatisfiable (labeled break matched no `LoopInfo` → runtime no-op → hang); the
   operator ruling amended the plan to add edit 4b, which the F1 implementer prototyped + verified,
   then reverted pending ruling. Re-applied here.

**Gate evidence (measured, /tmp/zlbl/zig1):**

- Repro `labeled_stmt_unhandled`: dump rc=0, 1 `.c` emitted, gcc rc=0, link rc=0, **run rc=0 and
  TERMINATES** (the hang was the bug).
- Nested-labels probe `outer: while (true) { inner: while (true) { i += 1; if (i < 3) { continue
  :inner; } break :outer; } }` + `if (i != 3) @panic("FAIL")`: dump rc=0, gcc rc=0, link rc=0,
  run rc=0 (assertion passes — `continue :inner` re-loops, `break :outer` exits the outer loop).
- 4 MD5 gates **byte-identical**: mud `50beb1bf5edc4cbb638f84aa027ffade`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462`.
- test_analyzer_bin **PASS** (`Analyzer tests passed`); build_test.sh 5/4 (baseline-identical).
- Corpus: 210 repros, **OK=203 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0** (203+3+4=210; raw
  classifier FAIL **8 → 7**). Only flip: `labeled_stmt_unhandled` FAIL→OK. The 3 remaining FAILs:
  2 std-lib-deferred (`field_store_drop`, `test_stub_0`, `error[3048]`) +
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). 4 green-guards unchanged.

**Documented scope limit (accepted, not fixed):** `break :label` out of a labeled NON-LOOP block
(`lbl: { break :lbl; }`) remains unsupported — the break/continue handlers (`lower.zig:4005-4044`)
search only `loop_stack`, and a labeled block never pushes a `LoopInfo`. Loop labels
(`label: while` / `label: for`) are fully supported; out of this repro's scope (loop case only).

**Accounting: OK=203 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 210 repros** — see the
Totals section at the top.

---

## Task F1 — duplicate-typed struct fields emit correctly (dup field topo-sort) (2026-08-07) — +2 repros (210 → 212)

The `dup_optptr_field_emit` + `dup_val_field_emit` repros (added 2026-08-07 by the rogue_mud
I-task, per `.superpowers/sdd/I-rogue-dupfld-report.md`) are now **OK**. Both previously failed
gcc with `unknown type name 'zT_...'`: the `tstTopologicalSort` Kahn algorithm dropped the struct
from the `sorted` array, so its forward-decl and body were never emitted while the lowerer still
referenced the type by name.

- **Root cause:** `tstEdgesCount` (`sf/src/c89_emit.zig:799-839`) counted **one edge per field
  occurrence**, so a struct with two same-typed edge-forming fields (`a: Point, b: Point`;
  `left: ?*Node, right: ?*Node`) got `indegree = 2`. The Kahn dequeue loop (`:960-968`)
  decremented **once per dependent type** (`tstIsDep` boolean, `:961`), leaving indegree 1 → the
  struct was never dequeued → dropped from `sorted` → no fwd-decl/body → gcc `unknown type name`.
- **Fix (Option B, operator ruling):** `tstEdgesCount` now counts each distinct dependent type
  **once** — deduped same-typed field edges in the struct/tagged_union/union branches, including
  dedupe of `tag_type` vs fields in the tagged_union branch. New helper `tstSeenInRange`
  (c89_emit.zig:799-805) scans the field range for an already-counted type id. Mirrored in
  `tstEdgesFill` (dead code, 0 callers — zero runtime effect) for consistency. Indegree now equals
  "number of distinct dep types" == the count of `tstIsDep`-true decrements, so count and dequeue
  can never drift; Kahn drains fully, which also eliminates the uninitialized-`sorted`-tail hazard
  (`sandAlloc` does not zero) for this pattern.
- **Files:** `sf/src/c89_emit.zig` (commit `fix: duplicate-typed struct fields emit correctly
  (dup field topo-sort)`).

**Gate evidence (measured, /tmp/zf1/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**

- `dup_val_field_emit`: dump rc=0, 1 `.c`, gcc-clean, link rc=0, run rc=0;
  `zig_special_types.h` now carries the `zT_9808F547_Line` fwd-decl + body (`zT_EAA8EF31_Point a;`
  / `b;`).
- `dup_optptr_field_emit`: dump rc=0, 1 `.c`, gcc-clean, link rc=0, run rc=0;
  `zT_3468032D_Node` fwd-decl + body now emitted.
- 4 MD5 gates **byte-identical**: mud `50beb1bf5edc4cbb638f84aa027ffade`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462` (no gate program has duplicate edge-forming field types).
- Full corpus sweep (216 dirs, /tmp/zf1/zig1): **OK=206 / FAIL=10 (raw) / ICE=0 / CRASH=0**. Of the
  raw FAIL=10: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
  `test_stub_0`, `self_embed_optional_cycle`) + 3 I-task repros for the other gaps
  (`undef_arr_struct_literal`, `xmod_pub_const_global`, `switch_mixed_case_argtype` — stay FAIL
  until F2/F3/F4).
- **F1 accounting: 210 → 212 repros, OK=205 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (205 + 3 + 4 = 212; raw classifier FAIL stays **7**). Only flip:
  `dup_optptr_field_emit` + `dup_val_field_emit` FAIL→OK. The 3 remaining FAILs: 2
  std-lib-deferred (`field_store_drop`, `test_stub_0`, `error[3048]`) +
  `self_embed_optional_cycle` (F-8 residual, gcc incomplete-type). 4 green-guards unchanged. No
  existing repro flipped. See the Totals section at the top.

---

## Task F2 — undefined struct-array field init emits valid C (undef_arr_struct_literal) (2026-08-07) — +1 (212 → 213)

The `undef_arr_struct_literal` repro (added 2026-08-07 by the rogue_mud I-task, per
`.superpowers/sdd/I-rogue-undefarr-report.md`) is now **OK**. It previously failed gcc with
`incompatible types when assigning to type 'zT_..._Client' from type 'int'`: the emitted C
expanded the `undefined` initializer of the `[5]Client` field into a zero-fill loop
`clients[_j] = 0;` — ill-typed for struct elements.

- **Root cause:** `emitFieldAssign` (`sf/src/c89_emit.zig:276-287`) hardcodes
  `base.fld[_j] = 0;` for ALL array-valued fields, never checking the element type or the `src`
  temp — only valid for scalar elements. The zig0 oracle emits NOTHING for `undefined` array
  fields (struct and primitive elements, verified).
- **Fix (Option A, operator ruling):** in the LOWERER (upstream, matches the oracle exactly),
  `sf/src/lower.zig` now skips the `assign_field` for a struct-literal field entirely when the
  field value is `undefined_literal` AND the field's declared type is `array_type`. A pre-scan at
  `lower.zig:2988-3027` sets `is_undef_arr_field` (struct + tagged-union kinds); the tagged-union
  payload branch (`:3063-3068`) and the struct branch (`:3072-3081`) both skip the
  `emitInst(assign_field)`. Skipping the field value's `lowerExpr` also drops the dead
  `undefined_const` temp (`zT_4 = 0;`). Emitter untouched.
- **Gate consequence (operator-approved re-baseline, F-5 AMENDMENT B precedent):** **mud
  RE-BASELINED** — `examples/z98/mud_server/main.zig:159` `.buffer = undefined` (`[256]u8`
  primitive array) drops its dead zero-fill (was `/tmp/mud_gate.c:800-802`). Runtime verified
  IDENTICAL: new mud prints "MUD server listening on port 4000" and exits rc=124 (timeout),
  matching the pristine build. New mud MD5 `906fa59c8676bb1054d3fcc13704fce5` (was
  `50beb1bf...`). gol/lisp/json byte-identical (no struct-literal `undefined` array fields).
- **Files:** `sf/src/lower.zig` (commit `fix: undefined struct-array field init emits valid C
  (undef_arr_struct_literal)`).

**Gate evidence (measured, /tmp/zf2/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**

- `undef_arr_struct_literal`: dump rc=0, 1 `.c`, gcc-clean, link rc=0, run rc=0. Emitted C is
  just `zT_1.listen_socket = zT_3;` — no `clients[_j] = 0` zero-fill, no dead `undefined_const`
  temp.
- 4 MD5 gates: mud `906fa59c8676bb1054d3fcc13704fce5` (RE-BASELINED, runtime-verified
  identical — "MUD server listening on port 4000", rc=124), gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462` — the latter three byte-identical.
- Full corpus sweep (216 dirs, /tmp/zf2/zig1): **OK=207 / FAIL=9 (raw) / ICE=0 / CRASH=0**. Of
  the raw FAIL=9: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
  `test_stub_0`, `self_embed_optional_cycle`) + 2 I-task repros for the other gaps
  (`xmod_pub_const_global`, `switch_mixed_case_argtype` — stay FAIL until F3/F4).
- **F2 accounting: 212 → 213 repros, OK=206 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (206 + 3 + 4 = 213; raw classifier FAIL stays **7**). Only flip:
  `undef_arr_struct_literal` FAIL→OK. The 3 remaining FAILs: 2 std-lib-deferred
  (`field_store_drop`, `test_stub_0`, `error[3048]`) + `self_embed_optional_cycle` (F-8
  residual, gcc incomplete-type). 4 green-guards unchanged. No existing repro flipped. See the
  Totals section at the top.

---

## Task F3 — cross-module pub const resolves (xmod_pub_const_global) (2026-08-07) — +1 (213 → 214)

The `xmod_pub_const_global` repro (added 2026-08-07 by the rogue_mud I-task, per
`.superpowers/sdd/I-rogue-xmodconst-report.md`) is now **OK**. It previously failed gcc with
`'zG_..._COLOR_WHITE' undeclared`: the cross-module `pub const` literal-init
(`pub const COLOR_WHITE: u8 = 7`) registers as `SymbolKind.global` but gets NO F-7 storage slot
(main.zig:616-660 skips literal-init consts, bit0=mutable only), so there is no definition in the
owner `.c` and no extern in the module header, and the consumer's `load_global` read referenced an
undeclared `zG_` name.

- **Root cause:** lower.zig:2005-2011 (the cross-module `SymbolKind.global` module-field-access
  branch) unconditionally lowered every module-qualified global reference to `load_global`,
  never consulting the const bit or the decl init.
- **Fix (Option C, operator ruling):** `sf/src/lower.zig` — the cross-module
  `SymbolKind.global` branch now, when `(ts.flags & 0x01) == 0` (const) and the target's
  `decl_node.child_1` init is an int/float/char literal, emits the corresponding
  `int_const`/`float_const` typed at the DECLARED type (`gbl_tid` from
  `resolvedTypeTableGet(resolved_types, ts.decl_node)`, i.e. `u8` not `TYPE_U32` — avoids the F-7
  u64-width regression class), mirroring the same-module literal fold at lower.zig:1681-1710. The
  `load_global` fallback is retained for non-literal consts (already storage-classified via
  main.zig:627). No bare `zG_` definition emitted (zero-init trap avoided).
- **Gate consequence:** none — **4 MD5 gates byte-identical** (mud `906fa59c…`, gol `0d8f0092…`,
  lisp `605b597e…`, json `b5f56ebd…`; no gate program has a cross-module scalar `pub const`).
- **Files:** `sf/src/lower.zig` (commit `fix: cross-module pub const resolves (xmod_pub_const_global)`).

**Gate evidence (measured, /tmp/zf3/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**

- `xmod_pub_const_global`: dump rc=0, 2 `.c`, per-file gcc-clean, link rc=0, run rc=0. Emitted C
  folds both refs: `zT_3 = 7;` (`fg`), `zT_5 = 7;` (`cell.fg`), `zT_4 = 0;` (`bg`), typed
  `unsigned char`; colors.c stays `/* EOF */`.
- 4 MD5 gates: mud `906fa59c8676bb1054d3fcc13704fce5`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462` — all four byte-identical, no re-baseline.
- Full corpus sweep (216 dirs, /tmp/zf3/zig1): **OK=208 / FAIL=8 (raw) / ICE=0 / CRASH=0**. Of
  the raw FAIL=8: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
  `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
  `test_stub_0`, `self_embed_optional_cycle`) + 1 I-task repro (`switch_mixed_case_argtype` —
  stays FAIL until F4).
- **F3 accounting: 213 → 214 repros, OK=207 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (207 + 3 + 4 = 214; raw classifier FAIL stays **7**). Only flip:
  `xmod_pub_const_global` FAIL→OK. The 3 remaining FAILs: 2 std-lib-deferred
  (`field_store_drop`, `test_stub_0`, `error[3048]`) + `self_embed_optional_cycle` (F-8
  residual, gcc incomplete-type). 4 green-guards unchanged. No existing repro flipped. See the
  Totals section at the top.

---

## Task F4 — switch mixed-case call-arg typing (switch_mixed_case_argtype) (2026-08-07) — +1 (214 → 215)

The `switch_mixed_case_argtype` repro (added 2026-08-07 by the rogue_mud I-task, per
`.superpowers/sdd/I-rogue-switcharg-report.md`) is now **OK**. It previously failed gcc with
`error: incompatible type for argument 1/3 of 'zF_..._saveDungeon'`: the `&arena` arg temp was
`unsigned int` and the string-literal temp `char*` instead of `Sand*` / `Slice_u8`.

- **Root cause (I4, confirmed):** NOT `call_arg_types` corruption — a **sema mid-switch abort**.
  The MIX else-branch at `semantic_analyzer.zig:1167` did `return type_mod.TYPE_VOID;` when two
  prong bodies had non-coercible types (assignment `dx = 0` → i32 vs empty block `{}` → void),
  aborting `semanticAnalyzerResolveSwitchExpr` and skipping all prongs *after* the conflict. The
  call prong (`'v','V'`) was therefore never sema'd, so the fixed-param loop at
  `semantic_analyzer.zig:775` never populated `call_arg_types`, and the lowerer fallback
  (`lower.zig:2388`) typed the arg slots as raw lowered types (`unsigned int` for `&arena`,
  `char*` for the string literal).
- **Fix (Option A, operator ruling):** `semantic_analyzer.zig:1167` — replaced `return
  type_mod.TYPE_VOID;` with `continue;` (skip this prong's contribution to the switch's `unified`
  type but keep resolving the remaining prongs, so the call prong IS sema'd and `call_arg_types`
  is populated normally). Kept the `resolvedTypeTableSet(..., TYPE_VOID)` on the same line
  (stmt-switch resolved type is unused). Lowerer untouched (the 4 call-arg paths were NOT the bug).
- **Gate evidence (measured, /tmp/zf4/zig1 — fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors):**
  - `switch_mixed_case_argtype`: dump rc=0, 2 `.c` emitted, per-file gcc-clean, link rc=0, run
    rc=0. Emitted arg temps now correctly typed: `zT_3E40CD83_Sand* zT_24;`,
    `zT_8F083A69_Slice_zT_0B42B2F8_u zT_26;`, string literal built into a `Slice`.
  - 4 MD5 gates **byte-identical**: mud `906fa59c8676bb1054d3fcc13704fce5`, gol
    `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
    `b5f56ebd51d2f0fcd379a1e083594462` (I4 measured the same; gol/lisp MIX aborts are
    pre-existing and emit no coercion-needing skipped call).
  - Full corpus sweep (216 dirs, /tmp/zf4/zig1): **OK=209 / FAIL=7 (raw) / ICE=0 / CRASH=0**. Of
    the raw FAIL=7: 4 green-guards (`eu_assign_incompat_payload`, `field_access_optional`,
    `var_declared_void`, `euvoid_val_catch`) + 3 real baseline FAILs (`field_store_drop`,
    `test_stub_0`, `self_embed_optional_cycle`). Only flip: `switch_mixed_case_argtype` FAIL→OK.
  - test_analyzer_bin **PASS** (`Analyzer tests passed`, run rc=0).
- **F4 accounting: 214 → 215 repros, OK=208 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0**
  (208 + 3 + 4 = 215; raw classifier FAIL stays **7**). Only flip:
  `switch_mixed_case_argtype` FAIL→OK. The 3 remaining FAILs: 2 std-lib-deferred
  (`field_store_drop`, `test_stub_0`, `error[3048]`) + `self_embed_optional_cycle` (F-8
  residual, gcc incomplete-type). 4 green-guards unchanged. No existing repro flipped. See the
  Totals section at the top.
- **Files:** `sf/src/semantic_analyzer.zig` (commit `fix: switch mixed-case call-arg typing
  (switch_mixed_case_argtype)`).
- **Known adjacent bug (out of scope, documented follow-up):** char-literal switch `case` labels
  are still dropped at `lower.zig:3858-3860` (stmt switch) / `:3121-3123` (expr switch; refs superseded — actual sites lower.zig:3183 expr / :3920 stmt), so this
  repro's emitted `switch (c)` has no `case` labels and its body is **unreachable at runtime**
  (always takes `default`). The F4 runtime gate passes only because the repro prints nothing and
  `c != -1` is false. This affects `rogue_mud`'s input switch too (`examples/z98/rogue_mud/
  main.zig:236-256`); a follow-up `switch_char_case_labels` repro + F-task is recommended. NOT
  fixed here.

## Task F5 — gate sweep + tech docs, rogue_mud emission-defects plan closeout (2026-08-07)

Docs-only + verification task (no compiler code changed — the 4 F-fixes F1 a5ac4598, F2
ba89a6e0, F3 317f3a82, F4 b1b3f7e9 are all on the branch). Compiler under test: `/tmp/zf5/zig1`
(fresh HEAD bootstrap, zig0 rc=0, gcc rc=0, 0 errors).

- **Full corpus sweep (216 dirs, QUICK_REF classifier): `OK=209 / FAIL=3 / ICE=0 / CRASH=0 /
  GREEN=4 / TOTAL=216`.** Reconciliation vs the 215-repro manifest total: 216 dirs = 215 manifest
  repros + `opt_slice_null_return` (OK-by-gate, type-incorrect, tracked separately — its OK is
  the 209th, so effective OK=208). Raw classifier FAIL = 7 = 4 green-guards (sub-bucket) + 3 real
  FAILs (`field_store_drop`, `self_embed_optional_cycle`, `test_stub_0`). The 5 gap repros all
  OK: `dup_optptr_field_emit`, `dup_val_field_emit`, `undef_arr_struct_literal`,
  `xmod_pub_const_global`, `switch_mixed_case_argtype` — each runtime-verified (dump rc=0, gcc
  rc=0, run rc=0). No repro flipped vs F4; no regressions.
- **4 MD5 gates verified byte-identical** (no re-baseline this task; the mud re-baseline was
  recorded in F2): mud `906fa59c8676bb1054d3fcc13704fce5`, gol
  `0d8f0092c22c04375482a198691a3957`, lisp `605b597e8b7cff60de0ce84a0593e743`, json
  `b5f56ebd51d2f0fcd379a1e083594462`.
- **5 gap rows cleared → OK** in this manifest; the 3 remaining FAILs stay enumerated (2
  std-lib-deferred `error[3048]` + `self_embed_optional_cycle` gcc incomplete-type).
- **`opt_slice_null_return` latent guard** — OK-by-gate (gcc rc=0), but type-incorrect (emits an
  `undefined_const` for a slice return); tracked separately, NOT a gate failure.
- **Out-of-scope follow-up (unchanged from F4):** char_literal switch `case` labels dropped at
  `lower.zig:3858-3860` (stmt switch) / `:3121-3123` (expr switch; refs superseded — actual sites lower.zig:3183 expr / :3920 stmt) — `rogue_mud`'s input switch
  (`examples/z98/rogue_mud/main.zig:236-256`) would be runtime-dead. A `switch_char_case_labels`
  repro + F-task is recommended.
- **Tech docs updated (AGENTS §1.1.1, `[updated: 2026-08-07]`):**
  - `08_c89_emission.md` — F1: `tstEdgesCount`/`tstEdgesFill` dedupe same-typed field edges
    (distinct dep type counted once) via new `tstSeenInRange` (c89_emit.zig:799); fixed stale
    line refs (`tstTopologicalSort` :959, `tstEdgesCount` :807, `tstEdgesFill` :857, `tstIsDep`
    :922, sub-pass 2a/2b :1256/:1297, fwd-decls :1233-1255, Q1 refs).
  - `07_lir_lowering.md` — F2: lowerer skips `assign_field` for `undefined` array-typed fields
    (oracle parity); F3: cross-module `pub const` literal fold at the ref site.
  - `05_semantic_analysis.md` — F4: switch MIX branch `continue` (resolves remaining prongs
    instead of aborting; `call_arg_types` populated for later prongs); fixed stale :1018-1129
    function range → :1046-1179 and the abort-behavior doc.
  - `02_symbol_registration.md` — F3: `pub const` literal-init has no storage slot (bit0=mutable);
    cross-module refs fold literals at the ref site.
  - `03_type_resolution.md` — NOT updated (F1/F3 touch c89_emit/lower, not the type-resolution
    path; verified by `git show --stat`).
- **Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `sf/docs/tech_docs/`
  (08, 07, 05, 02, INDEX.md), `examples/z98/rogue_mud/NOTES.md`. Commit
  `docs: gate sweep + tech docs for rogue_mud emission defects plan`.

---

## char_literal switch-case repro battery (Battery A, 2026-08-07) — 12 repros, ALL OK (F1-fixed, runtime-gap cleared)

Repros from the repro battery plan (`95b3c828` spec, `f0077d50` plan; commits `0dc4f594`,
`1e592430`, `c2864086`). They probe the **char_literal switch `case`-label drop**: both
switch-case-collection loops in `lower.zig` handle `int_literal`/`enum_literal`/`error_literal`
case nodes then `else { continue; }`, so a `char_literal` (kind 13) case node is silently dropped
from the case table — the emitted C `switch (c)` has NO `case` labels, only `default:`, and every
input takes the `else` body.

- **Defect sites (both, FIXED by F1 `e0a4d6d6`):**
  - `sf/src/lower.zig:3170-3184` — **expr-switch** case collection, `else { continue; }` at
    `:3183`. **F1** adds an `AstKind.char_literal` branch reading `store.int_values` (like
    `int_literal` does) — actual expr-site fix at lower.zig:3202.
  - `sf/src/lower.zig:3907-3921` — **stmt-switch** case collection, `else { continue; }` at
    `:3920`. **F1** adds the same `char_literal` branch — actual stmt-site fix at lower.zig:3941.
- **Fix (F1, commit `e0a4d6d6`, 2026-08-07):** both switch-case-collection loops gained an
  `AstKind.char_literal` branch (mirroring `int_literal`: value from `store.int_values`), so char
  cases emit real `case 'a':` labels. All 12 repros flip to their expected post-fix output
  (verified by run below).

**Classification under the corpus gate (POST-FIX):** every repro dumps rc=0, is gcc-clean
(per-file `gcc -c` rc=0), links, and runs rc=0 — gcc-exit classifier reports **OK**. **F1 makes
them fully OK at runtime too** — the char cases are no longer dead; each repro prints its expected
post-fix output. **No longer runtime-gap-tracked** (pre-fix they compiled clean but miscompiled at
runtime; the F1 fix resolved the runtime gap).

**Measured POST-FIX (sf/build/out_release/zig1, F4 gate sweep 2026-08-07):** all 12 dump rc=0,
gcc rc=0, run rc=0, output matches the expected post-fix column:

| Repro | defect site | pre-fix run output | **post-fix run output** |
|-------|-------------|--------------------|--------------------------|
| `switch_char_single` | stmt `:3920` (→ fixed :3941) | `000` | **`120`** |
| `switch_char_multi` | stmt `:3920` (→ fixed :3941) | `0000` | **`1120`** |
| `switch_char_nodefault` | stmt `:3920` (→ fixed :3941) | `99` | **`19`** |
| `switch_char_mixed_kinds` | stmt `:3920` (→ fixed :3941) | `020` | **`120`** (INT case 98 + char case both fire now) |
| `switch_char_expr` | expr `:3183` (→ fixed :3202) | `000` | **`120`** |
| `switch_char_while` | stmt `:3920` (→ fixed :3941) | `0` | **`1`** |
| `switch_char_labeled` | stmt `:3920` (→ fixed :3941) | `0` | **`1`** |
| `switch_char_nested` | stmt `:3920` (→ fixed :3941) | `999` | **`109`** |
| `switch_char_xmod` | stmt `:3920` (→ fixed :3941) (cross-module) | `000` | **`120`** |
| `switch_char_xmod_expr` | expr `:3183` (→ fixed :3202) (cross-module) | `000` | **`120`** |
| `switch_char_xmod_while` | stmt `:3920` (→ fixed :3941) (cross-module, in loop) | `0` | **`1`** |
| `switch_char_xmod_nodefault` | stmt `:3920` (→ fixed :3941) (cross-module, no else) | `99` | **`19`** |

Each dir's `NOTES.md` documents the defect, oracle (zig0) verification, measured pre-fix output,
and expected post-fix output (F3 7a732cb3 updated the classifications to "FIXED post-F1").
`switch_char_mixed_kinds` is the key discriminator — its INT case prong (`98`) fired while the char
prong (`'a'`) was dropped, proving the bug was char-specific, not a general switch miscompile; now
both prongs fire.

**Accounting:** 12 repros, all **fully OK** (F1-fixed). FAIL=3 and green-guards=4 **UNCHANGED**.

---

## opt_slice null-payload repro battery (Battery B, 2026-08-07) — 3 repros, ALL OK / FIXED by F2 (Option B)

Repros from the same repro battery plan (commit `965a830b`). They probe the **opt_slice
null-payload temp typing**: `catch return null` (and `return null`) in a function returning an
OPTIONAL SLICE (`?[]T`) emitted the null payload as a scalar `int` temp assigned `NULL`
(`int zT_3; zT_3 = NULL; zT_4.has_value = 0;`) even though the optional struct's payload field is
really a slice `typedef struct { zT_..._Slice... value; int has_value; } Opt;`. For an optional
POINTER (`?*T`) the payload IS a pointer and `int`/`NULL` is acceptable; for an optional slice the
temp type was wrong.

- **Defect (pre-fix):** the null-construction path picked a scalar `int` temp for the payload
  regardless of the payload's real type (the optional's payload type was not threaded onto the null
  temp). Latent, not a gate failure: the emitted C compiled (gcc rc=0, `-Wint-conversion` warning
  only) and the payload is never READ when `has_value=0`.
- **Fix (F2, commit `5c515a7d`, 2026-08-07, Option B):** the `null_literal` branch in
  `lowerExprImpl` (lower.zig:1183-1214) now consults the coercion table: when the coercion routes
  to `wrap_optional_null` / `wrap_optional` / `wrap_error_success` AND the target chain contains an
  optional layer, it emits `set_optional_null` directly on a temp typed as that optional layer —
  the dead `int zT_N; zT_N = NULL;` store (typed `null_type` → `int`, gcc `-Wint-conversion`) is
  gone. No payload temp is emitted at all; `materializeInto` short-circuits on `src_ty == expected`
  (lower.zig:911) or wraps the `?T` temp into outer EU layers (lower.zig:945). Emitted C is now
  `Opt_... zT; zT.has_value = 0;`. Warning count on the payload temp: 2/2/3 → **0/0/0**; `grep
  '= NULL;'` on emitted C: **0 hits**. All 3 still print `1` (verified by run, F4 sweep).

**Measured POST-FIX (sf/build/out_release/zig1, F4 gate sweep 2026-08-07):** all 3 repros dump
rc=0, gcc-clean (**0 `-Wint-conversion`**, 0 `= NULL;`), link, run rc=0 printing `1`:

| Repro | path | post-fix emitted-C symptom |
|-------|------|--------------------|
| `opt_slice_null` (B1) | same-module `?[]Point` | `Opt_... zT; zT.has_value = 0;` (no `int zT_3;` payload temp, no `= NULL;`) |
| `opt_slice_null_xmod` (B2) | cross-module `?[]Path` (lib.zig) | same post-fix shape in `lib_*.c` |
| `opt_slice_null_multi` (B3) | 3 null sites (2× `catch return null` + final `return null`) | `Opt_... zT; zT.has_value = 0;` at each site (no `int zT_6; = NULL;`) |

`opt_slice_null_return` (from the rogue_mud F5 I-task, 2026-08-07) is a DIFFERENT latent issue
(it emits an `undefined_const` for a slice return, not the null-payload `int` temp — unaffected by
F2's null_literal change) and remains **OK-by-gate, tracked separately** (see the F5 section).
Each dir's `NOTES.md` documents the pre-fix gap and the post-fix analysis.

**Accounting:** 3 repros, all **OK / FIXED by F2**. FAIL=3 and green-guards=4 **UNCHANGED**.

---

## F1/F2 fix records — char_literal switch + opt_slice null (2026-08-07)

The 15 battery repros above (12 Battery A + 3 Battery B) gate the two post-plan fixes; both are
now landed and the battery annotations are cleared:

| Fix | Commit | What changed | Battery impact |
|-----|--------|--------------|----------------|
| F1 — char_literal switch `case` labels | `e0a4d6d6` | Both switch-case-collection loops (`lower.zig` expr-switch site ~:3202, stmt-switch site ~:3941) gained an `AstKind.char_literal` branch (value from `store.int_values`, mirroring `int_literal`) — char cases now emit real `case 'a':` labels instead of being dropped (`else { continue; }`). | 12 Battery A repros **runtime-gap cleared** — all print expected post-fix output (`120`, `1120`, `19`, `1`, `109`, …). Fully OK. |
| F2 — opt_slice null-payload temp | `5c515a7d` | `null_literal` branch (lower.zig:1183-1214, Option B) consults the coercion table; null_src coercions with an optional layer emit `set_optional_null` directly on an `Opt_`-typed temp — the dead `int zT_N; zT_N = NULL;` payload temp (gcc `-Wint-conversion`) is gone. | 3 Battery B repros **latent cleared** — 0 `-Wint-conversion` warnings (was 2/2/3), 0 `= NULL;` sites, all still print `1`. Fully OK. |

**Gate sweep (F4, 2026-08-07, `sf/build/out_release/zig1` at HEAD):** full corpus 231 dirs
classify **OK=224 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4** (224 OK dirs = 223 effective
manifest OK + `opt_slice_null_return` tracked separately; raw classifier FAIL = 7 = 4 green-guards
sub-bucket + 3 real FAILs). FAIL=3 and green-guards=4 UNCHANGED. 4 MD5 gates: gol byte-identical;
mud/lisp/json re-baselined by F2 (full hashes in QUICK_REF). test_analyzer_bin PASS.

---

## F2 — D2 deferred to std-lib + `extern_runtime_symbol_xmod` repro (2026-08-08, docs + repro only)

Per the I2 report (`.superpowers/sdd/I-orphan-module-report.md`) and the operator ruling,
the D2 "json_parser orphan module" investigation found **NO compiler defect**: `arena.zig`
is never `@import`ed (orphan file), all modules emit, and the link failure is
`undefined reference to arena_alloc_default` — an extern (declared
`sf/src/include/zig_runtime.h:21-22`) defined ONLY in the legacy
`src/runtime/zig_runtime.c:31/:154-156`, **absent from `sf/src/include/zig_runtime.c`**.
Class **(b) runtime-library gap**; a documented runtime API
(`docs/reference/runtime_api.md:38-48`). **Deferred to the std-zig1 library — NOT fixed
here** (no `sf/src/*.zig` changes, no runtime-file changes).

**json_parser + json_parser_workaround — officially documented as std-lib-deferred** (their
NOTES.md gained a "Deferred to std-lib" section): both call `arena_alloc_default`; the
standard sf-runtime recipe fails on 5 undefined refs; linking the legacy
`src/runtime/zig_runtime.c` object makes json_parser link+run. `json_parser_workaround`
remains ADDITIONALLY blocked by the I3 6× zT_xx forward-decl COMPILE gap (unaffected by
any runtime fix). These are **example-level link gaps, not corpus repros** — they do not
change the corpus counts.

**New repro `extern_runtime_symbol_xmod` (class-(b) extern-link spec for the std-lib plan):**

| Repro | RED (measured) | Classification (measured, sf/build/out_release/zig1) | Guards |
|-------|----------------|---------------------------|--------|
| `extern_runtime_symbol_xmod` | pre-F3: standard-recipe link rc=1: `undefined reference to 'arena_alloc_default'` (lib_*.c) | **F3: FULLY OK (green regression guard)** — migrated off the `arena_alloc_default` extern to the `std_arena.zig` module (lib.zig imports a local std_arena copy, wraps `std.alloc` in `pub fn alloc`); dump rc=0, all modules emit (lib + main + std_arena), per-file gcc -c rc=0, **standard sf-runtime link rc=0 (no legacy object)**, run rc=0 (prints `0`; the 16-byte alloc succeeds → non-null ptr → `@ptrToInt(p)==0` false). The F2 OK-by-gate/latent std-lib-deferred classification is CLEARED (see the F3 section) | `mod_silent_drop_xmod` stays as the general emission guard; this repro now guards cross-module `std.arena` use (module emission + alloc + multi-module link + run) |

**zig0 oracle verification:** dump rc=0, emits lib.c/main.c (same module set). Honest
nuance vs the brief's "SAME link failure": zig0 re-emits the extern as `extern unsigned
char* arena_alloc_default(unsigned int n);` (from the `[*]u8` return), which CONFLICTS
with `zig_runtime.h:21` `void*` → the oracle's standard-recipe output fails at **compile**
(conflicting types), whereas zig1 (header-decl-only, no re-emitted extern) fails at
**link**. Both confirm the same runtime gap. zig0 also emits
`__bootstrap_i32_from_bool(...)` for `@intCast(i32, bool)` — a checked-cast helper in NO
runtime (legacy zig0 emission; zig1 post-F1 emits a raw `(int)` cast for the widening).

**Source corrections vs the brief's verbatim blocks (both documented in the repro
NOTES.md):** (1) the in-body `extern fn __bootstrap_print_int` was moved to module scope —
BOTH zig1 (`error[3020]`) and the zig0 oracle (syntax error) reject in-function `extern fn`
decls (pre-existing Z98 subset limitation, not a zig1 defect; corpus pattern is top-level);
(2) the `@ptrToInt(p) == @intCast(usize, 0)` line **works post-F1** as predicted
(`@ptrToInt` → `usize` for single-arg calls, commit `51bfdb3c`) — no error.

**Accounting:** **UNCHANGED — OK=223 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 230
manifest repros** (raw classifier FAIL stays 7). `extern_runtime_symbol_xmod` is tracked
separately as OK-by-gate/latent (mirrors the `opt_slice_null_return` precedent), NOT added
to FAIL; the two examples are example-level link gaps, not corpus repros. No repro
flipped; no compiler changes; 4 MD5 gates untouched (compiler unchanged). test_analyzer_bin
PASS. Full evidence: `.superpowers/sdd/task-F2-rogue-report.md`.

## F3 — `std_arena.zig` + json_parser migration (2026-08-08) — D2 arena gap CLOSED

The D2/F2 `arena_alloc_default` deferral is resolved with a **Zig-side arena module** (not a
runtime C symbol). New `sf/src/std_arena.zig` — a pure Z98 bump allocator
(`pub const Arena = struct { data: [*]u8, capacity: usize, used: usize };` +
`pub fn create(initial_capacity: usize) Arena`, `pub fn alloc(self: *Arena, size: usize)
?[*]u8`, `pub fn reset(self: *Arena) void`) over a static 1 MB `g_storage` + `g_used`
counter. `json_parser` + `json_parser_workaround` (`arena.zig`/`file.zig`/`json.zig`)
replaced `extern fn arena_alloc_default` with `const std = @import("std_arena.zig");` +
`std.create/alloc` (local copies of the module in each example dir so the import resolves);
`extern_runtime_symbol_xmod` migrated the same way.

**Verified (sf/build/out_release/zig1, multi-module recipe, STANDARD sf runtime, NO legacy
object):** json_parser — dump rc=0 (main/json/file/std_arena emit), per-file gcc `-c` rc=0,
link rc=0, run rc=0 (parses test.json). json_parser_workaround — dump rc=0, gcc `-c` rc=0
(both the F3 cross-module-enum fix AND the std_arena migration), link rc=0, run rc=0 (prints
`{}`; the hand-rolled tagged-union print path is a known example-source quirk). Both
previously failed standard-recipe link with **5× `undefined reference to arena_alloc_default`**
(4 json + 1 file). **`extern_runtime_symbol_xmod` flipped to FULLY OK (green regression
guard)** — dump rc=0, all modules emit (lib + main + std_arena), gcc rc=0, **standard-recipe
link rc=0**, run rc=0 (prints `0`); its F2 OK-by-gate/latent std-lib-deferred classification
is CLEARED. Corpus counts UNCHANGED (examples + the tracked-separately repro are not
manifest repros): effective **OK=223 / FAIL=3 / green-guards=4** over 230; the 3 FAILs
(`field_store_drop`, `test_stub_0`, `self_embed_optional_cycle`) and 4 green-guards
unchanged. **4 MD5 gates: mud `6c0a83f1…`, gol `0d8f0092…`, lisp `a12f2fce…` byte-identical;
json RE-BASELINED to `ff9b880c…`** (its source changed → emitted C changes; runtime output
byte-identical to pre-fix — old legacy-linked binary vs new standard-linked binary `diff`
empty — per the F-5 AMENDMENT B precedent). test_analyzer_bin PASS.

## F4 — D4 plat-stub gap deferred to std-lib (2026-08-08, docs only)

Per the I4 report (`.superpowers/sdd/I-platstub-gap-report.md`) and the operator ruling,
the D4 "platform-stub gap" investigation found **NO compiler defect**: 12 `plat_*` symbols
exist in `sf/src/include/net_runtime.c` (all socket-family), but the **5
console/platform-detect stubs** requested by `rogue_mud`
(`examples/z98/rogue_mud/ui.zig:11-15`) are **MISSING from ALL runtime files**
(`zig_runtime.c` / `zig_pal.c` / `net_runtime.c`): `plat_is_windows`,
`plat_console_gotoxy`, `plat_console_setcolor`, `plat_console_putchar`,
`plat_console_clear`. Class **(b) runtime-library gap**; `sf/build/zig0` fails
IDENTICALLY (same undefined-reference link rc=1) → NOT a compiler bug. **Deferred to the
std-zig1 library — NOT fixed here** (no compiler changes, no runtime-file changes).

`plat_stubs_missing_xmod` is the existing guard repro (dump rc=0, all modules emit, gcc
`-c` rc=0, link rc=1 on the missing stubs):

| Repro | RED (measured) | Classification (measured, sf/build/out_release/zig1) | Guards |
|-------|----------------|---------------------------|--------|
| `plat_stubs_missing_xmod` | link rc=1: `undefined reference to plat_is_windows` / `plat_console_putchar` (console_*.c) | **OK-by-gate / LATENT, std-lib-deferred** — dump rc=0, all modules emit, per-file gcc -c rc=0, standard-recipe link rc=1 on the missing console/platform-detect stubs (all 5 rogue_mud-only) | guards the rogue_mud link gap; flips to PASS when the std-lib runtime adds the 5 stubs (a console/platform-detect layer, e.g. `console_runtime.c` mirroring `net_runtime.c`) |

**Accounting:** **UNCHANGED — OK=223 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0 over 230
manifest repros** (raw classifier FAIL stays 7). `plat_stubs_missing_xmod` is tracked
separately as OK-by-gate/latent (mirrors the `opt_slice_null_return` /
`extern_runtime_symbol_xmod` precedents), NOT added to FAIL. `rogue_mud` (20 modules) is
BROKEN at link ONLY on these 5 stubs (both single- and multi-module recipes: all modules
emit, gcc compile rc=0). No repro flipped; no compiler changes; 4 MD5 gates untouched.
Full evidence: `.superpowers/sdd/task-F4-rogue-report.md`.

## F5 — D4 plat-stub gap CLOSED via console builtins (2026-08-13) — `plat_stubs_missing_xmod` FULLY OK

F5 (std-zig1 lib plan, console builtins migration) closed the D4 platform-stub gap the F2
way — via the **compiler console builtins**, NOT runtime stubs:

- **`examples/z98/rogue_mud/ui.zig`**: the 5 `plat_*` console externs
  (`plat_is_windows`, `plat_console_gotoxy`, `plat_console_setcolor`,
  `plat_console_putchar`, `plat_console_clear`) replaced with the F2 builtins
  (`@isWindows()` / `@consoleClear()` / `@consoleGotoxy(x,y)` /
  `@consoleSetColor(fg,bg)` / `@putChar(ch)`). The `plat_send` socket extern stays
  (provided by `net_runtime.c`).
- **`examples/z98/rogue_mud/main.zig`**: the 4 `ui_mod.plat_is_windows()` call sites →
  comptime `@isWindows()` (folds to 0 on the POSIX host → `!@isWindows()` true).
- **`repro/mi_matrix/plat_stubs_missing_xmod/console.zig`**: migrated off the 2 externs to
  `@isWindows()` + `@putChar('X')`.

| Repro | RED (pre-F5) | GREEN (measured, sf/build/out_release/zig1) | Guards |
|-------|----------------|---------------------------|--------|
| `plat_stubs_missing_xmod` | link rc=1: `undefined reference to plat_is_windows` / `plat_console_putchar` (console_*.c) | **FULLY OK** — dump rc=0, all modules emit, gcc -c rc=0, **standard-recipe link rc=0**, run rc=0; the D4 OK-by-gate/latent std-lib-deferred classification is CLEARED | guards the rogue_mud console migration (module emission + builtin wiring + multi-module link + run) |

**rogue_mud (22 modules):** dump rc=0, gcc -c rc=0, **link rc=0** (BOTH single-module and
multi-module recipes — was rc=1 on the 5 stubs), **run rc=0** — boots, renders the dungeon
via ANSI escapes (`@consoleGotoxy`/`@consoleSetColor`/`@putChar` emit `\x1b[<y+1>;<x+1>H` +
`\x1b[<fg>;<bg>m` + char on POSIX), accepts WASD/Q input, exits cleanly on `q`. The 5
undefined `plat_*` refs are gone from the emitted C (0 matches across all 22 modules).

**Accounting:** UNCHANGED — effective **OK=223 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0
over 230 manifest repros** (raw classifier FAIL stays 7). `plat_stubs_missing_xmod` moves
from the separately-tracked OK-by-gate/latent bucket to **FULLY OK** (like
`extern_runtime_symbol_xmod` at F3). No repro flipped; **no compiler changes**; 4 MD5 gates
untouched. See `.superpowers/sdd/task-F5-rogue-report.md`.

---

## F1 — @ptrToInt resolves to usize for single-arg calls (2026-08-08) — `ptr_to_int_void_xmod`

**Commit `51bfdb3c`** (semantic_analyzer.zig, 03_type_resolution.md). Hoisted the
`ptrtoint_name_id` check above the `ec.len` dispatch in `semanticAnalyzerResolveExpr`
(semantic_analyzer.zig:1298-1301), mirroring lower.zig:2653-2657; dead nested
`@ptrToInt → TYPE_USIZE` branch (was under `ec.len >= 2`) removed. Single-arg
`@ptrToInt(x)` now resolves to `TYPE_USIZE` instead of `void`.

| Repro | RED (pre-fix) | GREEN (post-fix, measured) |
|-------|---------------|----------------------------|
| `ptr_to_int_void_xmod` | dump rc=2, `error[3000] cannot declare variable of type void`, 0 `.c` | dump rc=0; emitted `unsigned int current_pos; current_pos = (unsigned int)ptr;`; gcc -c rc=0; link rc=0; **run rc=0, prints `1`**. Classifies **OK**. |

**Gates:** lisp_interpreter (the headline consumer) unblocked from the sema frontend block —
dump rc=0 (was error[3000]) — but its emitted C now surfaces a **separate pre-existing
lowerer defect** in `builtins.zig`: gcc FAIL, 6 errors (5× `zT_N` undeclared in token_*.c +
1× `zG_..._global_symbol_list = zT_0` Opt_45-null-payload mismatch in parser_*.c). This is
NOT a new regression from F1 (builtins.zig has no `@ptrToInt`; the defect was previously
masked by the sema block); tracked as a follow-up (see below). **lisp MD5 RE-BASELINED**
`fad41183…` → `a12f2fcebc30f2d8c2a148facb9d1174` (addr/start/end consts now `unsigned int`;
runtime output byte-identical to pre-fix, both run rc=0, output md5 `1c1f0a417d5e943433755a8ce593542f`
— verified by stash-revert rebuild, F1 report §Gates). test_analyzer_bin PASS.

## F3 — cross-module plain-enum member access resolves (2026-08-08) — `zT_missing_fwd_xmod`

**Commit `021ffcfd`** (semantic_analyzer.zig, lower.zig, 08_c89_emission.md). `x ==
mod.Type.Member` cross-module plain-enum access resolved to `TYPE_VOID` in sema + lowering
→ emitted C omitted the enum-literal temp → gcc `'zT_XX' undeclared`. Fix: sema
(semantic_analyzer.zig:459) + lower (lower.zig:2207) generic base-type dispatch gained an
`enum_type` case mirroring the same-module ident_expr path (`:260-271` / `:1981-1999`).

| Repro | RED (pre-fix) | GREEN (post-fix, measured) |
|-------|---------------|----------------------------|
| `zT_missing_fwd_xmod` | dump rc=0; gcc `-c` main_A05BD8BB.c rc=1 (`'zT_2' undeclared` at `zT_3 = tag == zT_2;`) | dump rc=0; gcc -c rc=0; link rc=0; **run rc=0** (emits `zT_3 = zT_..._Tag_Null; zT_4 = tag == zT_3;`). Classifies **OK**. |

**json_parser_workaround — gcc-clean (was 6× zT_xx COMPILE FAIL):** all 6 missing temps
resolved (`zT_11 = zT_6BE94440_JsonValueTag_Null;` … `zT_97 = zT_6BE94440_JsonValueTag_Object;`),
0 compile errors (only the pre-existing strtod `-Wincompatible-pointer-types` warning).
Link/run STILL blocked by the std-lib-deferred `arena_alloc_default` extern (F2). **4 MD5
gates byte-identical** (lisp already at post-F1 `a12f2fce…`). test_analyzer_bin PASS.

## F5 — arena resize for self-compile (2026-08-08) — PARTIAL

**Commit `462ddee4`** (allocator.zig:74-79, main.zig:848, 00_shared_infra.md). perm 1 MB→4 MB,
mod 1.5 MB→8 MB, scratch 1.5 MB→2 MB; `DEV_MAX_MEM` 8 MB→16 MB (== `RELEASE_MAX_MEM`).
Resize landed (plan-mandated 4/8/2, 16 MB budget). **Self-compile import-phase gate NOT
met:** `zig1 --dump-c89 --output-dir /tmp/z5 sf/src/main.zig` → `dump rc=3`,
`OOM: used=1899216 new=3472080 total=2097152` — the **scratch** arena (2 MB) OOMs during
import lexing of a 5k-line module (the lexer token array, 24 B/Token, doubling 32K→64K,
never freed within a module, needs ≥3.5 MB). **Documented as future investigation (operator
ruling m0442), NOT a corpus regression** — the resize fixes phase-1 module/perm OOMs and no
repro regressed. Scratch-arena optimization listed as a follow-up (see below). **4 MD5 gates
byte-identical** (arena size does not change codegen). test_analyzer_bin PASS.

## F6 — cross-module tagged-union member access no longer SEGVs (2026-08-08) — `tagged_union_cmp_xmod`

**Commit `efbf4807`** (lower.zig:2174-2206, 08_c89_emission.md). Option (a) ONLY per operator
ruling m0406: the generic base-type field-access branch previously called
`typeRegistryGetStructFields` for `tagged_union_type` (WRONG → SEGV at lower.zig:2180). Added
a dedicated `tagged_union_type` case mirroring the same-module member path (lower.zig:1966-1979):
look up the member in `tu_items[ty.payload_idx]`, on match return
`emitTaggedUnionInit(...)` — a TU-typed `int_const` emitting `.tag = <ordinal>;`. Option (b)
(reject-in-sema) NOT implemented.

| Repro | RED (pre-fix) | GREEN (post-fix, measured) |
|-------|---------------|----------------------------|
| `tagged_union_cmp_xmod` | dump rc=1, 0 `.c`; stderr `AddressSanitizer:DEADLYSIGNAL` → `SEGV on unknown address 0x00000000`, frame 0 = `typeRegistryGetStructFields` ← `lowerExprImpl` ← `phase_LIRLowering` | dump rc=0 (SEGV **gone**, CRASH→0); isolated `var x = lib_mod.Shape.Circle;` gcc-clean, link rc=0, **run rc=0**. The `==` form still emits gcc-invalid C (`error: invalid operands to binary ==` — the known separate latent union-`==` emission issue; NOT fixed, see follow-ups). Classifies gcc-FAIL → sweep FAIL 7→8, ICE 1→0. |

**F3 repros no-regression:** `zT_missing_fwd_xmod` run rc=0; json_parser_workaround gcc-clean.
**4 MD5 gates byte-identical. test_analyzer_bin PASS.**

## F7 gate sweep + full example matrix reconciliation (2026-08-08)

**Corpus sweep (all 237 dirs, gcc-exit classifier, `sf/build/out_release/zig1`):**
`OK=229 / FAIL=8 / ICE=0 / CRASH=0`. FAIL=8 = the 4 green-guards (`eu_assign_incompat_payload`,
`euvoid_val_catch`, `field_access_optional`, `var_declared_void`) + 2 std-lib-deferred
(`field_store_drop`, `test_stub_0`) + `self_embed_optional_cycle` (C89 fundamental) +
`tagged_union_cmp_xmod` (latent union-`==` emission). **No manifest OK repro regressed; the
only count moves vs the F3 sweep (OK=229/FAIL=7/ICE=1) are tagged_union_cmp_xmod ICE→FAIL
(F6 SEGV fix).** Convention reconciliation vs the plan's 230/231 figures is documented in
the Totals block above.

**Full 21-example matrix (MEM4 recipe, multi-module `--dump-c89 --output-dir`; measured):**

| # | Example | dump | gcc | link | run | Post-fix status vs MEM4 |
|---|---------|------|-----|------|-----|--------------------------|
| 1 | hello | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 2 | fibonacci | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 3 | prime | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 4 | heapsort | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 5 | quicksort | 0 | 0 | 0 | 0 | unchanged WARN OK (10w) |
| 6 | mandelbrot | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 7 | game_of_life | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 8 | lzw | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 9 | func_ptr_return | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 10 | sort_strings | 0 | 0 | 0 | 0 | unchanged WARN OK (8w) |
| 11 | days_in_month | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 12 | tco_factorial | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 13 | tco_defer | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 14 | tco_return_try | 0 | 0 | 0 | 0 | unchanged FULL OK |
| 15 | json_parser | 0 | 0 (1w) | **0 (was 1)** | **0** | **LINK FAIL CLEARED (F3, std_arena migration)** — standard-recipe link rc=0 (no legacy object), run rc=0 parses test.json; was 5× `arena_alloc_default` undefined ref |
| 16 | json_parser_workaround | 0 | 0 (1w) | **0 (was 1)** | **0** | **LINK FAIL CLEARED (F3, std_arena migration)** — standard-recipe link rc=0, run rc=0 (prints `{}`); both the F3 cross-module-enum compile fix AND the arena link gap resolved |
| 17 | lisp_interpreter | **0 (was error[3000] DUMP FAIL → now dumps, F1)** | **1** | — | — | **frontend block CLEARED (F1)**; GCC FAIL 6 errors = 5× `zT_N` undeclared + 1 Opt_45 null-payload (pre-existing builtins.zig lowerer defect, follow-up) |
| 18 | lisp_interpreter_adv | 0 | 0 | 0 | 0 | unchanged WARN OK (1w) |
| 19 | lisp_interpreter_curr | 0 | 0 | 0 | 0 | unchanged WARN OK (1w; MEM4 recorded 9w — gcc-version/toolchain diff, benign) |
| 20 | mud_server | 0 | 0 | 0 | 124 | unchanged CANNOT RUN — server, "MUD server listening on port 4000" (timeout) |
| 21 | rogue_mud | 0 (20 modules) | 0 (5w) | **1** | — | **LINK FAIL at this sweep** — 5 `plat_*` stubs (std-lib-deferred, F4); **[F5 2026-08-13 CLEARED: the 5 stubs → console builtins, link rc=0 + run rc=0 — see the F5 section]** |

**End-to-end working binaries: 16/21** (12 FULL OK + 4 WARN OK), same as MEM4 — but two
compiler-defect classes were CLEARED (json_parser_workaround's 6× zT_xx compile gap via F3;
lisp_interpreter's @ptrToInt frontend block via F1, exposing a separate pre-existing lowerer
defect). No NEW regression vs MEM4. **[F3 2026-08-08: `json_parser` + `json_parser_workaround`
now link+run rc=0 → end-to-end working binaries 18/21** (the 3 non-working: lisp_interpreter
gcc FAIL, mud_server server-timeout, rogue_mud plat_* link FAIL). See the F3 section.]**
**[F5 2026-08-13: rogue_mud console migration closes the D4 gap → link rc=0 + run rc=0 →
working set 19/21 end-to-end** (lisp_interpreter gcc FAIL + mud_server server-timeout are the
only non-run). See the F5 section.] **[F6 2026-08-13: networking builtins + std_net migration;
mud_server re-verified boots on the standard runtime (no net_runtime.c); the working set is
unchanged. See the F6 section / QUICK_REF MD5 table.]**

**[F4 2026-08-08 — std.io migration (see task-F4-stdlib-report.md):]** all 21 examples
migrated off `__bootstrap_*` (zero refs in example sources); all 21 dump rc=0; the working set
is **unchanged at 18/21 end-to-end** (same set as F3 — no example regressed). The 6
example-facing `__bootstrap_*` I/O wrappers were removed from `zig_runtime.c`/`.h`; the 19
`@intCast` cast helpers now panic via `std_panic` directly (m0564). The F1/F2 feature-guard
repros **`io_builtin_test` + `console_builtin_test` were migrated to `std.io`** (local
`std.zig`/`std_io.zig`/`std_arena.zig` copies in each dir; the F2 console builtins' emitted
`__bootstrap_write` calls were repointed to `std_print_len` in c89_emit.zig — the console
builtins' stdout-write helper) — both still compile+link+run. Corpus at F4: **239 dirs measured,
OK=232 / FAIL=3 / green-guards=4 / ICE=0 / CRASH=0** (the 3 FAILs + 4 green-guards are exactly
the documented set — no new corpus FAIL).

## F4 repro migration — corpus repros off `__bootstrap_*` → std.io (2026-08-13)

F4 removed the 6 example-facing `__bootstrap_*` I/O wrappers (`__bootstrap_print`,
`__bootstrap_print_int`, `__bootstrap_print_char`, `__bootstrap_panic`, `__bootstrap_write`,
`__bootstrap_sleep_ms`) from `zig_runtime.c`/`.h`. Corpus repros still declaring
`extern fn __bootstrap_print*` therefore no longer LINK (`undefined reference to
__bootstrap_print*`). **47 repro .zig files migrated** (44 `main.zig` + 2 `main_green.zig`
+ 1 `io.zig`; `field_store_drop` left unmigrated — compile-only FAIL, `error[3048]` on
`@import("pal")`, std-lib-deferred) off the extern to `std.io`
(`std.io.print` / `std.io.printInt` / `std.io.write`), each with **byte-identical local
`std.zig` + `std_io.zig` copies** (the F3 std_arena per-example-copy precedent, D1). The local
`std.zig` is the reduced `io`-only root package (omits the `arena`/`debug` re-exports — see the
D2 tracking entry below). Verified with the QUICK_REF single-file recipe
(`zig1 --dump-c89` + `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include
/tmp/x.c zig_runtime.c zig_pal.c`):

| Repro | Result |
|-------|--------|
| `intcast_range_check` | dump rc=0, gcc rc=0 (LINKS), run rc=134 — PANICS `integer cast overflow in @intCast` (F1 pass criterion, link restored) |
| `enum_literal_assign` | dump rc=0, gcc rc=0, run rc=0, prints `1` (expected_out.txt) |
| `error_literal_return` | dump rc=0, gcc rc=0, run rc=0, prints `1` (expected_out.txt) |
| `switch_char_expr` | dump rc=0, gcc rc=0, run rc=0, prints `120` (char switch post-F1-fix, migration is a pure I/O swap) |
| `opt_extern_ptr_file` | dump rc=0, gcc rc=0, run rc=0, prints `1` — pre-existing optional-wrap emission RED (has_value hardcoded 1), unchanged by migration; the `printInt` path itself works |
| `import_extern_c` | dump rc=0, gcc rc=0, run rc=0, prints `hello` (io.zig migrated `extern "c" fn __bootstrap_print` → `std.io.print`) |

**`field_store_drop` disposition:** NOT migrated — it is a compile-only FAIL
(`error[3048]: could not resolve imported file 'pal'` from its `@import("pal")`, std-lib-
deferred). The `__bootstrap_print_int` extern is unreachable behind the frontend gate; leaving
it does not break the gate (verified: still error[3048], 0 `.c` emitted).

## D2 tracking — std_arena module-instance ≥1 emission bug (FILE the entry, out of F4 scope)

**Pre-existing compiler bug (verified in the F4 stdlib review):** importing `std_arena.zig` as
**module instance ≥ 1** emits invalid C — the `_N` instance suffix is applied to the struct
typedef + locals (`zT_F22A6288_Arena_1`) but NOT to the function-signature type refs
(`zT_F22A6288_Arena` return) → `error: return type is an incomplete type` / `conflicting types`
in the emitted `std_arena_*.c`. Trigger: `rogue_mud` (multi-module build) pulling the canonical
`std.zig` root package (which re-exports `arena`); json_parser builds std_arena at instance 0
and is unaffected. **Out of F4 scope** (compiler change; F4 is a repro/example migration).
Workaround today: local `std.zig` root packages omit the `arena` re-export where std_arena
would land at instance ≥ 1 (mud_server, and the 48 migrated corpus repros). **Documented
follow-up** — a future compiler task must fix the instance-suffix application for
function-signature type refs (or defer std_arena to instance 0). See the F4 stdlib report
concern 2 / DEVIATION D2 (`.superpowers/sdd/task-F4-stdlib-report.md`).

## printInt INT_MIN overflow tracking (Minor, out of F4 scope)

**Pre-existing minor defect (verified in the F4 stdlib review):** `std_io.zig`'s `printInt`
uses `v = @intCast(u32, 0 - n)` for negatives. This is correct for all i32 values EXCEPT
`INT_MIN` (`0 - INT_MIN` overflows i32 → panic rc=134). The suggested `0 - @intCast(u32, n)`
was rejected in testing: this compiler's `@intCast(u32, negative)` panics, breaking the working
`-5` case (`comptime_neg_int`). **No example or repro prints INT_MIN.** File as a documented
follow-up: fix requires i64-widened negation (`@intCast(u32, 0 - @intCast(i64, n))`) or a
division-based magnitude loop — deferred, not an F4 defect.


## Follow-ups (multi-module fixes plan) — NOT fixed here

1. **Union `==` emission** — `tagged_union_cmp_xmod` and same-module union `==` emit
   `lhs == rhs` as `binary ==` on the C struct union (`error: invalid operands to binary ==`).
   Needs either a union-equality emission path (compare `.tag` + payload) or the reject-in-sema
   diagnostic (F6 Option b, ruled out of scope by m0406). The repro's run gate cannot pass
   until then.
2. **TU payload-read lowering** — same-module TU VALUE payload access `s.Circle` now lowers to
   the tag value (`.tag = 0;`), not the payload read (`s.data.Circle`). Semantically-incorrect-
   but-crash-free after F6; a payload-read emission path is a follow-up.
3. **lisp_interpreter builtins.zig `zT_N`** — post-F1, lisp_interpreter dumps but gcc FAILs on
   5× `zT_N` undeclared (union/optional `==` comparison temp-drop class; P3-5 adjacent) + 1×
   Opt_45 null-payload global assign. Pre-existing lowerer defect, previously masked by the
   @ptrToInt sema block. F1 report concern-2. **RESOLVED (F3 closeout, 2026-08-13):** the
   lisp_defects plan's Defects A-E fixes (bare-union literals F1, module-scope null globals F2,
   nested field-store write-back F4, struct-with-union layout F5, bare-union C emission F6)
   cleared lisp_interpreter's compile AND runtime failures — it now dumps/gccs/links/runs rc=0
   and evaluates `nil`/`true`/`+`/`(quote 5)`/`cons` correctly. See the F3 closeout section.
4. **Scratch-arena optimization** — self-compile import-phase scratch OOM (F5; token array
   doubling 32K→64K in the 2 MB scratch). Candidate options (all require operator ruling,
   plan mandates 4/8/2): scratch 2→4 MB; reset scratch per-file after the parser consumes the
   token array; or move the token array to the module arena.
5. **Cross-module enum-literal switch-case dropping** — observed in F6's isolated-form switch
   test; separate pre-existing switch-path gap.
6. **json_parser / json_parser_workaround / extern_runtime_symbol_xmod** — **RESOLVED (F3,
   std_arena migration, 2026-08-08)**: the `arena_alloc_default` deferral was closed with the
   `std_arena.zig` module, not a runtime symbol — all three now link+run rc=0 on the standard
   sf runtime (see the F3 section). **`rogue_mud` / `plat_stubs_missing_xmod` — RESOLVED (F5,
   console builtins, 2026-08-13)**: the 5 `plat_*` stubs were replaced with the F2 console
   builtins (`@isWindows` + `@consoleClear`/`@consoleGotoxy`/`@consoleSetColor`/`@putChar`),
   not runtime symbols — both now link+run rc=0 on the standard sf runtime (see the F5
   section). No std-lib-deferred runtime gaps remain.

---

## F7 — std-lib plan CLOSEOUT: 21-example matrix + gate sweep + fix records (2026-08-13)

Closes the std-lib builtins plan (F1-F6, commits `cc63eb02`..`25fb7ce1`). Measured with
`/tmp/fx_subfolder/zig1` (fresh F6-source build; `sf/build/out_release/` wedged — all builds
in `/tmp`). **Full 21-example matrix (multi-module `--dump-c89 --output-dir`, standard sf
runtime `zig_runtime.c` + `zig_pal.c`, NO `net_runtime.c`):**

| # | Example | dump | gcc | link | run | Status |
|---|---------|------|-----|------|-----|--------|
| 1 | hello | 0 | 0 | 0 | 0 | FULL OK — "Hello, world!" |
| 2 | fibonacci | 0 | 0 | 0 | 0 | FULL OK — `55` |
| 3 | prime | 0 | 0 | 0 | 0 | FULL OK — `2357` |
| 4 | heapsort | 0 | 0 | 0 | 0 | FULL OK — sorted output |
| 5 | quicksort | 0 | 0 | 0 | 0 | FULL OK — asc/desc sorted |
| 6 | mandelbrot | 0 | 0 | 0 | 0 | FULL OK |
| 7 | game_of_life | 0 | 0 | 0 | 0 (40s) | FULL OK — 100 gens glider, rc=0 |
| 8 | lzw | 0 | 0 | 0 | 0 | FULL OK |
| 9 | func_ptr_return | 0 | 0 | 0 | 0 | FULL OK — `10 + 5 = 15` |
| 10 | sort_strings | 0 | 0 | 0 | 0 | FULL OK |
| 11 | days_in_month | 0 | 0 | 0 | 0 | FULL OK |
| 12 | tco_factorial | 0 | 0 | 0 | 0 | FULL OK — `fact(10)=3628800`, deep ok |
| 13 | tco_defer | 0 | 0 | 0 | 0 | FULL OK — defer fires once |
| 14 | tco_return_try | 0 | 0 | 0 | 0 | FULL OK — `count(100000)=100000` |
| 15 | json_parser | 0 | 0 | 0 | 0 | FULL OK — parses test.json (CLEARED F3) |
| 16 | json_parser_workaround | 0 | 0 | 0 | 0 | FULL OK — prints `{}` (CLEARED F3); **[2026-08-13 F3 closeout: full tree output rc=0 — SEGFAULT resolved]** |
| 17 | lisp_interpreter | 0 | 1 | 1 | — | **gcc FAIL** — pre-existing builtins.zig `zT_N` lowerer defect (5× `zT_N` undeclared + 1 Opt_45 null-payload); follow-up #3 **[2026-08-13 F3 closeout: CLEARED — dump/gcc/link/run rc=0, functionally correct]** |
| 18 | lisp_interpreter_adv | 0 | 0 | 0 | 0 | FULL OK — REPL (EOF rc=0) |
| 19 | lisp_interpreter_curr | 0 | 0 | 0 | 0 | FULL OK — `(+ 1 2)` → `3` |
| 20 | mud_server | 0 | 0 | 0 | 124 | **CANNOT RUN** — server, boots "MUD server listening on port 4000" (timeout-gated; NOT an MD5 gate) |
| 21 | rogue_mud | 0 (24 mods) | 0 | 0 | 0 | FULL OK — boots, WASD/Q, exits rc=0 on `q` (CLEARED F5) |

**End-to-end: 20/21 working** — 19 run rc=0 + mud_server boots (server, timeout-gated). The
sole gcc-FAIL is `lisp_interpreter` (pre-existing builtins.zig `zT_N` lowerer defect, NOT a
std-lib regression; previously masked by the @ptrToInt sema block — see the multi-module-fixes
plan F1 section). json_parser / json_parser_workaround (F3) and rogue_mud (F5) rows are
**deferred→fixed** and now run on the standard runtime with NO legacy object and NO
`net_runtime.c`. game_of_life needs ~10s (100 gens × 100ms sleep) — the prior 8s timeout
showed rc=124; a 40s timeout gives rc=0. **[2026-08-13 F3 closeout: this is now 21/21 — see
the F3 closeout section below.]**

### Fix records (std-lib plan F1-F6)

| Task | Commits | What landed |
|------|---------|-------------|
| F1 core I/O builtins | `cc63eb02` | `@putChar`/`@stdoutWrite`/`@stderrWrite`/`@getChar`/`@exit`/`@sleepMs` in sema/lower/emit; `repro/mi_matrix/io_builtin_test` OK |
| F2 console builtins | `b91bf296` | `@isWindows` (comptime) + `@consoleClear`/`@consoleGotoxy`/`@consoleSetColor`; `repro/mi_matrix/console_builtin_test` OK |
| F3 std.arena | `3b1e06bf` | `std_arena.zig` bump allocator; json_parser + json_parser_workaround + extern_runtime_symbol_xmod link+run — D2 gap CLOSED |
| F4 std.io migration | `737e1966`,`f3077477`,`ad0c71e7`,`05124d9c`,`54a7f2c9`,`b2d03bd3` | std.zig/std_io.zig; all 21 examples + 47 repros off `__bootstrap_*`; wrappers removed; cast helpers → `std_panic` |
| F5 rogue_mud console | `1be697e8` | rogue_mud + plat_stubs_missing_xmod on the console builtins — D4 gap CLOSED |
| F6 networking builtins | `50da2447`,`25fb7ce1` | 11 `@socket*` builtins port net_runtime.c into the emitter; std_net.zig; mud_server + rogue_mud migrate off `net_runtime.c`; F6-review null-coalesce fix |

### Gates (all PASS)

- **Corpus sweep (240 dirs): OK=233 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4** (233+3+4=240).
  FAIL=3 exactly the documented set: `field_store_drop` + `test_stub_0` (std-lib-deferred,
  `error[3048]`) + `self_embed_optional_cycle` (C89 fundamental). No new FAIL. The 3 std-lib
  repro dirs (`io_builtin_test`, `console_builtin_test`, `net_builtin_test`) all OK.
- **4 MD5 gates:** gol `b246a2fecc0b5ff4402912c49970cdae`, lisp `141994cc81ab4bbb89722b7d30af419d`,
  json `f50ce1e6800d9e1365c019e46ac61292` — **byte-identical** through F6. mud
  `fd0fdaa42a419b0e72cfdb3226a54c4a` (F6 std_net migration + F6-review null-coalesce
  re-baseline; mud NOT an MD5 gate per the operator).
- **test_analyzer_bin: PASS** — `bash sf/scripts/build_test.sh` → `5 passed, 4 failed`
  (unchanged documented baseline; the 4 fails are the pre-existing set, zero
  `sf/src/tests/*` changes in the plan range).
- QUICK_REF.md corpus baseline + MD5 table (mud `fd0fdaa4…`) + gcc recipe notes updated.
  Tech docs 00/05/07/08 line-refs verified; 05 + 07 gained the F6 socket builtins
  (was F1/F2-only).

### Deferred-gap clearance summary

All std-lib-deferred runtime gaps from the std-lib plan are CLOSED — no example or repro
needs a legacy runtime object or `net_runtime.c` anymore. The only remaining FAIL items are
the two `error[3048]` import-gap repros (`field_store_drop`, `test_stub_0` — a user program
cannot import compiler-internal modules; pass when zig1 gains a real std lib) and
`self_embed_optional_cycle` (C89 fundamental).

---

## F3 — lisp_interpreter lowerer-defects plan CLOSEOUT: 21-example matrix 21/21 + gate sweep (2026-08-13)

Closes the lisp_defects plan (Defects A-E, F1-F6, commits `535010d4`..`31de6800`). Measured
with `/tmp/fx_subfolder/zig1` (fresh F6-source build, HEAD `31de6800`; `sf/build/out_release/`
wedged — all builds in `/tmp`). **Full 21-example matrix (multi-module `--dump-c89
--output-dir`, standard sf runtime `zig_runtime.c` + `zig_pal.c`, NO `net_runtime.c`; runs
timeout-gated, cwd = example dir for json_parser*):**

| # | Example | dump | gcc | link | run | Status |
|---|---------|------|-----|------|-----|--------|
| 1 | hello | 0 | 0 | 0 | 0 | FULL OK — "Hello, world!" |
| 2 | fibonacci | 0 | 0 | 0 | 0 | FULL OK — `55` |
| 3 | prime | 0 | 0 | 0 | 0 | FULL OK — `2357` |
| 4 | heapsort | 0 | 0 | 0 | 0 | FULL OK — sorted output |
| 5 | quicksort | 0 | 0 | 0 | 0 | FULL OK — asc/desc sorted |
| 6 | mandelbrot | 0 | 0 | 0 | 0 | FULL OK |
| 7 | game_of_life | 0 | 0 | 0 | 0 | FULL OK — 100 gens glider rc=0, stdout md5 `fcbf7e7c…` (documented) |
| 8 | lzw | 0 | 0 | 0 | 0 | FULL OK |
| 9 | func_ptr_return | 0 | 0 | 0 | 0 | FULL OK — `10 + 5 = 15` |
| 10 | sort_strings | 0 | 0 | 0 | 0 | FULL OK |
| 11 | days_in_month | 0 | 0 | 0 | 0 | FULL OK |
| 12 | tco_factorial | 0 | 0 | 0 | 0 | FULL OK — `fact(10)=3628800`, deep ok |
| 13 | tco_defer | 0 | 0 | 0 | 0 | FULL OK — defer fires once |
| 14 | tco_return_try | 0 | 0 | 0 | 0 | FULL OK — `count(100000)=100000` |
| 15 | json_parser | 0 | 0 | 0 | 0 | FULL OK — parses test.json |
| 16 | json_parser_workaround | 0 | 0 | 0 | 0 | **FULL OK — no SEGFAULT**; parses test.json, prints full tree (F4-exposed SEGFAULT resolved by Defect D+E) |
| 17 | lisp_interpreter | 0 | 0 | 0 | 0 | **FULL OK — CLEARED**; dump/gcc/link/run rc=0 AND functionally correct (see below) |
| 18 | lisp_interpreter_adv | 0 | 0 | 0 | 0 | FULL OK — REPL (EOF rc=0) |
| 19 | lisp_interpreter_curr | 0 | 0 | 0 | 0 | FULL OK — `(+ 1 2)` → `3` |
| 20 | mud_server | 0 | 0 | 0 | 124 | server — boots "MUD server listening on port 4000"; client interaction verified (welcome + look + north responses) |
| 21 | rogue_mud | 0 | 0 | 0 | 0 | FULL OK — boots, exits rc=0 on `q` |

**End-to-end: 21/21 working.** `lisp_interpreter` is now dump/gcc/link/run rc=0 AND
**functionally correct** — REPL session: `(+ 1 2)` → `3`, `(quote 5)` → `5`,
`(cons 1 2)` → `(1 . 2)`, `nil` → `nil`, `true` → `true`, `(define x 10)` → `10`,
`(* x 2)` → `20`. No silent eval failure, no SEGFAULT. The pre-existing builtins.zig `zT_N`
lowerer defect (follow-up #3) is **RESOLVED** — the Defects A-E fixes (bare-union literals F1
`535010d4`, module-scope null globals F2 `5a3b2adc`, nested field-store write-back F4
`73e21c81`, struct-with-union layout F5 `8a9df9a2`, bare-union C emission F6 `31de6800`)
collectively cleared its compile AND runtime failures.

### Defects fixed by this plan (all 5, +F1/F2/F4 repros green)

| Defect | Fix task | Commit | Repro | Output |
|--------|----------|--------|-------|--------|
| A — bare-union literal in struct literal → 5× `zT_N` | F1 | `535010d4` | `union_literal_nested_xmod` | `42` |
| B — module-scope `?T = null` global typed `int` | F2 | `5a3b2adc` | `global_null_init_xmod` | `1` |
| C — nested field-access store drops write-back | F4 | `73e21c81` | `nested_field_store_xmod` / `nested_field_store_xmod2` | `4243` / `78` |
| D — `@sizeOf`/`@alignOf` struct-with-union layout ordering | F5 | `8a9df9a2` | `sizeof_struct_union_xmod` | `24` (oracle `24`) |
| E — bare union emitted as stacked C struct (arena overflow → SEGFAULT) | F6 | `31de6800` | `union_emission_layout_xmod` | `7816` |

All 6 repro dirs classify **OK** under the gcc-exit gate (dump/gcc/link/run rc=0, outputs
above verified by run). 4 MD5 gates **byte-identical** to the F2 post-Defect-A-D re-baseline
(gol `ff47d18d…`, lisp `c1cb748b…`, json `376fd681…`, mud `fd0fdaa4…`) — no re-baseline needed.
test_analyzer_bin PASS.

### Gates (all PASS)

- **Corpus sweep (246 dirs): OK=239 / FAIL=3 / ICE=0 / CRASH=0 / green-guards=4** (239+3+4=246).
  FAIL=3 exactly the documented set: `field_store_drop` + `test_stub_0` (std-lib-deferred,
  `error[3048]`) + `self_embed_optional_cycle` (C89 fundamental). Green-guards=4 unchanged
  (`eu_assign_incompat_payload`, `euvoid_val_catch`, `field_access_optional`,
  `var_declared_void`). **No new FAIL, no new ICE/CRASH, no green-guard moved.**
- **4 MD5 gates:** gol `ff47d18dc8ef00e9b8f92f5e0a14c34a`, lisp
  `c1cb748b423eef191b9c9ce7023ae2a0`, json `376fd6812ef751913bdad00de676ceb6` —
  **byte-identical**; mud `fd0fdaa42a419b0e72cfdb3226a54c4a` (mud NOT an MD5 gate per the
  operator; F6 std_net migration + null-coalesce re-baseline retained).
- **test_analyzer_bin: PASS** — `bash sf/scripts/build_test.sh` → `5 passed, 4 failed`
  (unchanged documented baseline; zero `sf/src/tests/*` changes in the plan range).
- QUICK_REF.md corpus baseline (246 dirs, 21/21) + MD5 table (post-F2 re-baseline values)
  updated to match. Tech docs 05/07/08 line-refs verified against current source.

