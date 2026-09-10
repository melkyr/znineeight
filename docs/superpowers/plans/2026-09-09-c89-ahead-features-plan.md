# C89-Ahead Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `static`, `do…while`, and type-alias as Z98 features (RED→GREEN, corpus-gated), and resolve `volatile` through an explicit feasibility task (operator-ruled Go/No-Go) — never silently cut.

**Architecture:** Each feature is a small compiler-frontend change (token → parse → AST → sema → lowering → C89 emission) following the INTWIDTH/PACK RED-first pattern. Compiler source edits converge a new fixed point via N-hop; the emitted-C correctness bar is runtime byte-identity + corpus zero-asymmetry.

**Tech Stack:** Z98 (`sf/src/*.zig`), LIR, C89 emitter, corpus fixtures in `repro/mi_matrix/`.

**Spec:** `docs/superpowers/specs/2026-09-09-c89-ahead-features-design.md`

## Global Constraints

- **Feature order:** `static` first, then `do…while`, then type-alias; `volatile` fourth and gated on its feasibility task (Task 5). Operator ruling: volatile is NOT cut — feasibility task lives inside this plan.
- **Reference per the seed model** (`release/seed/`); every compiler edit converges a new fixed point via N-hop (≤4 hops, hop1≠hop2 expected after self-affecting changes). Measurement compiler = the N-hop-converged binary, stated per report. Dump CWD = repo root, relative `sf/src/main.zig`.
- **Bootstrap-staging constraint:** new-feature compiler code written in constructs the current committed seed understands.
- **Flag-set rule:** every gcc `-c` = `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`; `-Wall -Wextra -O3 -fsyntax-only` separate verification gate. Self-emission link set = `zig_runtime.c` + `zig_pal.c` + `c_exit.c`.
- **RED-first per feature:** fixture classifies RED (clean reject / parse error) at plan start; GREEN byte-exact deterministic (RUNRC=0) after the feature lands; fixture stays in the corpus permanently.
- **Corpus primary oracle:** 420 dirs = 404 OK / 9 GREEN / 7 FAIL at HEAD (post-EMITCOMPACT). Each feature zero-asymmetric except its own fixture dir(s). Golden 9/9 + matrix 21/21 run byte-identity vs PRE.
- **4-MD5:** a feature changing a gate program's emission moves that md5 → **recorded-not-rebaselined per feature**; operator-ruled full re-baseline at the Task-6 STOP only.
- **Warning/compat:** emitted C warning-clean under `-Wall -Wextra -O3 -fsyntax-only`; compat audit POST ≤ PRE (no bare `long long`, ≤31-char identifiers, no `%zu`, no empty macro args).
- **Working conventions:** SDD mandatory; compression forbidden during build sessions; memories via `mnemoria --path .opencode/memory add` under agent `c89ahead-session`; edits via `edit`/`fastedit` only; no commit until review clean; pre-existing dirty set never staged.
- Report `.superpowers/sdd/task-C89AHEAD-report.md`; ledger `.superpowers/sdd/progress.md`; memory agent `c89ahead-session`.

---

### Task 1: Baseline + RED reproduction + volatile feasibility research (part 1) (I, record-only)

**Files:**
- Read: `sf/src/token.zig`, `sf/src/parser.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/type_registry.zig`, Zig langref volatile section
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (appended `## Task 1`)
- No source edits, no commit, nothing staged.

- [ ] **Step 1: Baseline.** Reconfirm HEAD, fixed point `ea149e05` (seed v6), 4-MD5 (gol `bbafa30f…`, lisp `c1767529…`, json `3ada7d8b…`, mud `ee42f9b7…`), EXPECTED_FAIL v76, corpus 420 dirs = 404/9/7. Record.
- [ ] **Step 2: RED reproduction.** Author scratch probes (NOT committed) for each feature confirming today's class:
  - `static var x` / module-scope `static` → parse `error[2000]` (keyword absent from `token.zig`).
  - `do { … } while (…)` → parse `error[2000]`.
  - type-alias `const T = u32;` → record actual behavior (may half-work today via the `const` type-expr path — classify precisely, incl. use in annotations / `@sizeOf(T)`).
  - `volatile` → record actual behavior.
  - Record deterministic stderr md5s per probe.
- [ ] **Step 3: Volatile feasibility research part 1.** From the Zig langref (pointer-qualifier `*volatile T` + `@volatileCast`, no `var volatile` storage qualifier), document the exact Z98 mapping surface: `volatile` keyword in pointer-type position, ptr-type `volatile` flag (which TypeKind payload/slab), `@volatileCast`, and the C89 emission placement rules for pointer-vs-pointee qualifiers. Enumerate the type-system sites a flag would thread through (`typeRegistryGetOrCreatePtr` and siblings, coercion, lowering, `getCTypeName`). Draft the Go/No-Go criteria for the Task-5 ruling.
- [ ] **Step 4: Census anchors.** For each feature, list the exact edit-map sites (token table, parse arms, AST flags, sema, lowering, emission) as the Task-2/3/4/5 briefs' starting map.
- [ ] **Step 5: Report + ledger.** Append the full census; one ledger line. No commit.

---

### Task 2: `static` (F)

**Files:**
- Modify: per Task-1 census — expected `sf/src/token.zig` (kw_static), `sf/src/parser.zig` (local `static var` decl arm + module-level `static` prefix), `sf/src/lower.zig` / `sf/src/semantic_analyzer.zig` (static-local semantics + file-scope internal-linkage handling), `sf/src/c89_emit.zig` (emit `static` storage class; suppress `pub`/header export for module static)
- Create (fixtures): `repro/mi_matrix/static_local_xmod/main.zig`, `repro/mi_matrix/static_filestatic_xmod/main.zig`
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (appended `## Task 2`)
- Commit: `feat: c89-ahead — static storage (function-local + file-scope) (C89AHEAD)`

**Interfaces:**
- Consumes: Task-1 static edit-map.
- Produces: `static var` local persists across calls; module-level `static` has internal linkage (no header export); clean rejects for meaningless `static`.

- [ ] **Step 1: RED fixtures first.** `static_local_xmod`: `fn next() i32 { static var n: i32 = 0; n += 1; return n; }` + main printing `1 2 3` — classifies RED today (parse `error[2000]`). `static_filestatic_xmod`: a module-scope `static var`/`static fn` + proof the symbol is absent from the emitted cross-module header — RED today. Verify RED deterministic 3×, record stderr md5s.
- [ ] **Step 2: Implement.** Token (`kw_static`), parse arms for `static var` in function bodies and `static` prefix at module scope, AST flags, sema (`static` only where meaningful; clean `error[3000]` otherwise), lowering (static local → a C function-scoped `static` variable, init-once; module static → internal-linkage emission, no header export). Keep plain locals byte-identical.
- [ ] **Step 3: GREEN gate.** Fixtures GREEN byte-exact deterministic 3× (RUNRC=0). Emitted-C grep: the counter shows a `static` C local (single declaration, no re-init). Golden 9/9 + matrix 21/21 run byte-identity vs PRE. Corpus `-s0` zero-asymmetric except the 2 new dirs. 4-MD5 recorded-not-rebaselined. Self-compile N-hop converges to a new fixed point (record chain).
- [ ] **Step 4: Commit** (message above; scope = census files + 2 fixture dirs).
- [ ] **Step 5: Report + ledger.**

---

### Task 3: `do…while` (F)

**Files:**
- Modify: per Task-1 census — expected `sf/src/token.zig` (kw_do), `sf/src/parser.zig` (`do { body } while (cond);` grammar arm), `sf/src/lower.zig` + `sf/src/c89_emit.zig` (post-test loop lowering/emission)
- Create (fixtures): `repro/mi_matrix/dowhile_countdown_xmod/main.zig`, `repro/mi_matrix/dowhile_once_xmod/main.zig`
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (appended `## Task 3`)
- Commit: `feat: c89-ahead — do…while post-test loop (C89AHEAD)`

- [ ] **Step 1: RED fixtures first.** `dowhile_countdown_xmod`: `var i: i32 = 5; do { print; i -= 1; } while (i > 0);` → RED today (parse `error[2000]`). `dowhile_once_xmod`: `do { print "ran"; } while (false);` body runs once — RED today. Verify RED deterministic 3×.
- [ ] **Step 2: Implement.** `kw_do` token; parse `do` statement; lower to a post-test loop (C `do{}while()` shape or the existing loop machinery per census); `break`/`continue` behave as `while`. Keep `while` byte-identical.
- [ ] **Step 3: GREEN gate** (as Task 2 Step 3): fixtures GREEN 3× (`5 4 3 2 1`; the `while(false)` body prints once); emitted C shows a `do { } while` shape; golden/matrix byte-identity; corpus zero-asymmetric; 4-MD5 recorded-not-rebaselined; N-hop convergence recorded.
- [ ] **Step 4: Commit** (message above).
- [ ] **Step 5: Report + ledger.**

---

### Task 4: type-alias (F)

**Files:**
- Modify: per Task-1 census — expected registration/type-resolution sites so `const T = <type-expr>` registers `T` as a usable type (annotations, params, returns, `@sizeOf(T)`), plus `pub` alias export if the census shows it missing
- Create (fixtures): `repro/mi_matrix/typealias_prim_xmod/main.zig` (`const Handle = u32;`), `repro/mi_matrix/typealias_agg_xmod/main.zig` (`const Buf = [16]u8;` / struct alias)
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (appended `## Task 4`)
- Commit: `feat: c89-ahead — type alias (const T = <type>) (C89AHEAD)`

- [ ] **Step 1: RED fixtures first.** Per the Task-1 exact-classification, author the fixtures so each is RED today (whatever gap the census found — alias not usable in annotations, `@sizeOf` fails, or `pub` alias not exported). Verify RED deterministic 3×.
- [ ] **Step 2: Implement** the census-identified gap so `const T = <existing-type>` (primitives + composites) registers and resolves everywhere a type name is legal; error messages show the alias name. Plain enum/struct `const` declarations stay byte-identical.
- [ ] **Step 3: GREEN gate** (as Task 2 Step 3): fixtures GREEN 3× (`@sizeOf(Handle)` prints 4 etc.); golden/matrix byte-identity; corpus zero-asymmetric; 4-MD5 recorded-not-rebaselined; N-hop convergence recorded.
- [ ] **Step 4: Commit** (message above).
- [ ] **Step 5: Report + ledger.**

---

### Task 5: `volatile` feasibility task (I → operator Go/No-Go → F on Go)

**Files:**
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (appended `## Task 5`)
- On Go: modify per the Task-1 edit-map (type-system volatile flag + `@volatileCast` + C89 qualifier emission) + fixture
- On No-Go: modify `docs/reference/z98_bootstrap_manual.md` (quirk note: extern `"c"` wrapper for volatile C access)
- Commit: Go → `feat: c89-ahead — volatile pointer qualifier (C89AHEAD)`; No-Go → `docs: c89-ahead — volatile documented extern-c-wrapper quirk (C89AHEAD)`

- [ ] **Step 1 (I): Complete the feasibility research** started in Task 1 (part 2): the exact Z98 type-system threading, the C89 emission placement rules (`volatile T*` pointee vs `T * volatile` pointer), coercion/`@ptrCast` interactions, and a concrete fixture design (`*volatile u32` read/write against a normal array). Assess: does C89 emission of a volatile-qualified pointer type survive the existing carrier/typedef machinery byte-cleanly?
- [ ] **Step 2 (I): Present Go/No-Go to the operator** with the evidence. The operator rules (this is the mandated B2 gate). Do NOT commit either way until the ruling.
- [ ] **Step 3 (F, on Go only): Implement** RED→GREEN per the ruling; run the full GREEN gate (as Task 2 Step 3); commit.
- [ ] **Step 4 (F, on No-Go only): Record the quirk note** in the manual (`docs/reference/z98_bootstrap_manual.md` constraints table: "if you need volatile, write an `extern "c"` wrapper whose body is the volatile C access") and commit the docs-only note. The feature is closed as annotated, not silently dropped.
- [ ] **Step 5: Report + ledger.**

---

### Task 6: Full battery + N-hop + gate re-baseline STOP-present (I, record-only)

**Files:**
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (appended `## Task 6`)
- No commit, nothing staged.

- [ ] **Step 1: Full external battery** on the N-hop-converged compiler (measurement compiler stated): golden 9/9 + matrix 21/21 run byte-identity; corpus `-s0` zero-asymmetric (all new feature dirs OK/GREEN); upgraded-examples goldens + net round-trips; mingw32 `-osw` cross (final step, 0 new warnings, POST ⊆ PRE); warning sets POST ⊆ PRE; compat audit POST ≤ PRE.
- [ ] **Step 2: N-hop determinism (gate A)** from the committed seed; record the chain (gn==gn+1 ≤4 hops).
- [ ] **Step 3: STOP-present the operator-ruled re-baseline:** any moved 4-MD5 rows → new values, fixed point → new value, Task-7 docs-GATE plan. Await operator approval.

---

### Task 7: Docs GATE + seed rotation (F, after operator approval)

**Files:**
- Modify: `docs/sf/QUICK_REF.md` (4 gate-table rows if re-baselined + newest-first bullet above the newest existing bullet), `repro/mi_matrix/EXPECTED_FAIL.md` (bump for the feature RED→GREEN flips), `release/seed/CHANGELOG.md`, `release/seed/zig1-seed.tgz` (rotated)
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (appended `## Task 7`)
- Commit: `docs: GATE — c89-ahead features + re-baseline + seed rotation (C89AHEAD)`

- [ ] **Step 1: Rotate the seed** via `bash scripts/seed/archive_seed.sh <fixed-point-binary> <fresh-gen-dir> release/seed/zig1-seed.tgz --update-changelog`; verify archive md5 == CHANGELOG row, internal binary == operator-approved fixed point, layout intact, 0 spill.
- [ ] **Step 2: Docs edits** — QUICK_REF gate-table rows (if re-baselined) + newest-first bullet (features landed, emission/RED→GREEN facts, fixed point, seed); EXPECTED_FAIL bump for the feature fixture flips (new GREEN sections, history verbatim).
- [ ] **Step 3: Commit** the docs-GATE set; pre-existing dirty set never staged.
- [ ] **Step 4: Report + ledger close**, then STOP-present the plan close for operator sign-off.

---

## Next-up items (NOT tasks of this plan — spec §6, kept so they aren't forgotten)

- Stdlib growth plan runs before this one in the forward queue; EMITCOMPACT before that.
- If volatile was ruled No-Go, a future plan may revisit full volatile support when the type system is further along.
- Other deferred C89 items (recorded): `goto`, `long double`, preprocessor macros, method syntax, named `anytype`.

---

## AMENDMENT 2 — Divergence & Runtime Safety; `static`/`do…while` dropped (2026-09-10)

> Operator-approved 2026-09-10. This amendment belongs to the same plan; execute A1–A13 in order.
> **Supersedes** original **Task 2 (`static`)** and **Task 3 (`do…while`)** — both **DROPPED** (documented
> Zig idioms instead). Original **Task 1** is replaced by **A1**; original **Task 4 (type-alias)** → **A9**;
> original **Task 5 (volatile)** → **A10**; original **Tasks 6/7** → **A12/A13**.
> Design: `docs/superpowers/specs/2026-09-09-c89-ahead-features-design.md` (amended 2026-09-10; §3 new).

### Amended Global Constraints

All original constraints remain in force. Additions / corrections:

- **Safety flag:** `-fsafe` (**default**) enables runtime checks; `-ffast` disables them. **All six**
  runtime checks (cast / div-mod / shift / null-unwrap / index-OOB / integer-overflow) are gated by
  `-fsafe`. `unreachable` and `@panic` trap **unconditionally** (not gated).
- **Compiler self-build = `-ffast`:** `scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh`
  pass `-ffast` when emitting the compiler's own C; the recorded fixed point is the `-ffast` binary.
  User programs default to `-fsafe`.
- **Trap primitive:** `pal_trap()` = x86 `int 3`, non-x86 fallback `pal_abort()`.
- **Baseline correction (original plan is stale):** original baseline (seed v6 `ea149e05`, 420 dirs) is
  superseded. A1 reconfirms and records: fixed point `4da59bb11270e3c85638bcbb120afc2d`; seed v9 archive
  `7c1421f6312b59c4c449dcf336e32694`; canonical corpus `bash scripts/corpus/list_corpus_dirs.sh` (463
  dirs). Dump CWD = repo root, relative entry `sf/src/main.zig`.
- Report `.superpowers/sdd/task-C89AHEAD-report.md`; ledger `.superpowers/sdd/progress.md`; memory agent
  `c89ahead-session`.

---

### Task A1: Baseline + feasibility census (I, record-only)

**Files:**
- Read: `sf/src/token.zig`, `sf/src/main.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`,
  `sf/src/semantic_analyzer.zig`, `sf/src/analyzer.zig`, `sf/src/type_registry.zig`, `sf/src/lir.zig`,
  `sf/src/pal.zig`, `sf/src/include/zig_pal.c`, `sf/src/include/zig_runtime.c/.h`, `sf/src/std_arena.zig`,
  `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh`
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (appended `## A1`)
- No source edits, no commit, nothing staged.

- [ ] **Step 1: Baseline.** Reconfirm HEAD, fixed point `4da59bb1…`, seed v9 archive `7c1421f6…`, EXPECTED_FAIL v76, canonical corpus `bash scripts/corpus/list_corpus_dirs.sh` (463). Record.
- [ ] **Step 2: Trap feasibility.** Confirm how to emit `int 3` from `zig_pal.c` for gcc (i386/`-m32`), MSVC6, and OpenWatcom under the flag-set rule; confirm the non-x86 `pal_abort()` fallback and that the emitted C stays C89-clean and warning-clean. Decide the exact `pal_trap()` C body.
- [ ] **Step 3: Flag plumbing + seed staging.** Locate CLI parsing (`main.zig`), the compiler config struct, and where lowering/emission would read the mode; design the two-hop staging with the committed seed that predates the flag (seed emits today's behaviour on hop 1; hop 1 understands `-ffast`; hop 2 checked-off). Specify the exact `build_from_seed.sh`/`archive_seed.sh` edits.
- [ ] **Step 4: Safety-check emission sites.** For each of the six checks, give the exact lowering/emitter anchors and the backend-neutral LIR representation. Include the `@intCast` helper-pair gap (`c89_emit.zig:5282-5322`) and where new helpers are emitted; the OOB length source for arrays vs slices; the overflow-detection form for `i32`/`u32`/arbitrary-width.
- [ ] **Step 5: Diagnostics sites.** Specify where the uninitialized-var, ignored-error-union, and missing-return checks hook (parser/sema/lowering), and the new diagnostic codes/severity, without breaking existing corpus programs.
- [ ] **Step 6: Arena migration census.** Enumerate every `std.arena.alloc` caller and every `orelse unreachable` in examples/std/fixtures; define the new error-union signature and the migration pattern.
- [ ] **Step 7: type-alias classification + volatile research part 1.** Classify what `const T = <type>` already does today; document the volatile mapping (pointer-type flag threading, `@volatileCast`, C89 pointee-vs-pointer placement).
- [ ] **Step 8: RED probes.** Author scratch probes (NOT committed) confirming the current behaviour of each silent mode and each dropped-feature idiom; record deterministic stderr md5s.
- [ ] **Step 9: Report + ledger; STOP-present.** Append the full census; one ledger line; STOP-present the baseline, staging design, and check/disposition list. No commit.

---

### Task A2: `pal_trap()` + divergence fix (F)

**Files:**
- Modify: `sf/src/pal.zig` (extern), `sf/src/include/zig_pal.c` (`pal_trap`), `sf/src/include/zig_runtime.c/.h` (panic helper), `sf/src/emit_support.zig` (canonical support bytes), `sf/src/lir.zig` (backend-neutral trap terminator), `sf/src/lower.zig` (`unreachable`, `@panic`), `sf/src/semantic_analyzer.zig` (`@panic` → `noreturn`), `sf/src/c89_emit.zig` (emit `pal_trap()`), `sf/src/std_debug.zig` (`assert`/`panic` → `pal_trap`)
- Create (fixtures): `repro/mi_matrix/trap_unreachable_xmod/main.zig`, `trap_orelse_unreachable_xmod/main.zig`, `trap_panic_xmod/main.zig`, `trap_arena_exhaustion_xmod/main.zig`
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (`## A2`)
- Commit: `fix: c89-ahead — real trap for unreachable/@panic (pal_trap) (C89AHEAD)`

**Interfaces:**
- Consumes: A1 trap feasibility + staging.
- Produces: `pal_trap()` runtime primitive; `unreachable`/`@panic`/`orelse unreachable` that terminate.

- [ ] **Step 1: RED fixtures.** `trap_unreachable_xmod` reaches an `unreachable` and must trap (rc≠0 / signal); today it falls through. `trap_panic_xmod` reaches `@panic("...")` and must print + trap (today no-op). `trap_orelse_unreachable_xmod` does an `orelse unreachable` on a null optional. `trap_arena_exhaustion_xmod` exhausts a tiny arena and must trap instead of writing address 0. Verify RED deterministic 3× with `timeout 120`; record.
- [ ] **Step 2: Implement.** Add the `pal_trap` extern + C body; add the LIR trap terminator; lower `unreachable` to it; lower `@panic` (evaluate+print arg) and retype it `noreturn`; update `std.debug.assert/panic`; emit `pal_trap()`.
- [ ] **Step 3: GREEN gate.** Fixtures trap deterministically, `-ffast` too (unconditional). Golden 9/9 + matrix 21/21 byte-identity vs PRE where no trap is expected; corpus `-s0` zero-asymmetric except the 4 new dirs; 4-MD5 recorded-not-rebaselined; self-compile N-hop converges (record chain + new fixed point).
- [ ] **Step 4: Commit** (scope = census files + support + fixtures). **Step 5: Report + ledger.**

---

### Task A3: `-fsafe`/`-ffast` framework + `undefined` poison (F)

**Files:**
- Modify: `sf/src/main.zig` (flag parse), config/CLI struct, `sf/src/lower.zig` + `sf/src/c89_emit.zig` (mode plumbing), `sf/src/c89_emit.zig` (`undefined` init), `scripts/seed/build_from_seed.sh`, `scripts/seed/archive_seed.sh` (`-ffast`)
- Create (fixtures): `repro/mi_matrix/safe_undefined_poison_xmod/main.zig`, plus a `-ffast` control
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (`## A3`)
- Commit: `feat: c89-ahead — -fsafe/-ffast mode + undefined poison (C89AHEAD)`

- [ ] **Step 1: RED fixture.** A program reading `undefined` prints `0` today; it must print a poison marker under `-fsafe`. Record today's behaviour.
- [ ] **Step 2: Implement.** Add `-fsafe` (default) / `-ffast` parsing + config; thread the mode into lowering/emission; implement `undefined` poison (`0xAA`) under `-fsafe`. Update the seed scripts to pass `-ffast`.
- [ ] **Step 3: GREEN gate.** Fixture GREEN both modes; compiler self-emission `-ffast` N-hop converges; golden/matrix/corpus/4-MD5 per convention.
- [ ] **Step 4: Commit.** **Step 5: Report + ledger.**

---

### Task A4: Cheap runtime checks (F) — `@intCast`, div/mod, shift, null-unwrap

**Files:**
- Modify: `sf/src/lower.zig`, `sf/src/c89_emit.zig` (checked cast helpers + guards), `sf/src/include/zig_runtime.c/.h` (new helper pairs as needed)
- Create (fixtures): `repro/mi_matrix/safe_cast_overflow_xmod`, `safe_div_zero_xmod`, `safe_shift_count_xmod`, `safe_null_unwrap_xmod`
- Report: `.superpowers/sdd/task-C89AHEAD-report.md` (`## A4`)
- Commit: `feat: c89-ahead — -fsafe cheap checks (cast/div/shift/null) (C89AHEAD)`

- [ ] **Step 1: RED fixtures** (each traps under `-fsafe`, current behaviour under `-ffast`).
- [ ] **Step 2: Implement** the four checks; keep `-ffast` byte-identical to PRE.
- [ ] **Step 3: GREEN gate** incl. `-ffast` control byte-identity; N-hop; record.
- [ ] **Step 4: Commit.** **Step 5: Report + ledger.**

---

### Task A5: Index out-of-bounds runtime check (F)

**Files:** Modify `sf/src/lower.zig` (index_access), `sf/src/c89_emit.zig` (emit the guard); fixture `repro/mi_matrix/safe_bounds_xmod`; report; commit `feat: c89-ahead — -fsafe bounds check (C89AHEAD)`.

- [ ] Steps: RED fixture (OOB read + OOB write) → implement guard for arrays and slices → GREEN under `-fsafe`, `-ffast` control byte-identical → N-hop → commit → report/ledger.

---

### Task A6: Integer-overflow runtime check (F) — `+`, `-`, `*`, unary neg

**Files:** Modify `sf/src/lower.zig` (binary/unary ops), `sf/src/c89_emit.zig` + `sf/src/include/zig_runtime.c/.h` (overflow helpers); fixture `repro/mi_matrix/safe_int_overflow_xmod`; report; commit `feat: c89-ahead — -fsafe integer-overflow check (C89AHEAD)`.

- [ ] Steps: RED fixture (signed + unsigned + arbitrary-width overflow) → implement detection → GREEN under `-fsafe`, `-ffast` control byte-identical → measure size/perf impact (report) → N-hop → commit → report/ledger.

---

### Task A7: Compile-time diagnostics (F) — uninitialized var, ignored error union, missing return

**Files:** Modify `sf/src/semantic_analyzer.zig` / `sf/src/lower.zig` / `sf/src/diagnostics.zig`; fixtures `repro/mi_matrix/diag_uninit_var_xmod`, `diag_ignored_error_xmod`, `diag_missing_return_xmod`; report; commit `feat: c89-ahead — failure diagnostics (uninit/ignored-error/missing-return) (C89AHEAD)`.

- [ ] Steps: RED fixtures (currently compile silently) → implement the three checks with clean diagnostics → GREEN (clean reject, 0 `.c`); full canonical sweep for regressions (fix any `sf/src`/example sites the new diagnostics flag — in-scope fallout; STOP-present if non-mechanical) → N-hop → commit → report/ledger.

---

### Task A8: Arena error-union API + consumer migration (F)

**Files:** Modify `sf/src/std_arena.zig` (`alloc` → error union), `examples/z98/json_parser*/**.zig`, `examples/z98/json_parser_upgraded/**.zig`, `repro/mi_matrix/extern_runtime_symbol_xmod/lib.zig`; fixture (arena OOM GREEN); report; commit `feat: c89-ahead — std.arena error-union alloc (C89AHEAD)`.

- [ ] Steps: RED (current `?` API + `orelse unreachable` sites) → change signature + migrate all callers to `try`/`catch` → GREEN fixtures + byte-identical migrated-consumer outputs → N-hop → commit → report/ledger.

---

### Task A9: Type-alias verify/finish (F)

**Files:** per A1 census; fixtures `repro/mi_matrix/typealias_prim_xmod`, `typealias_agg_xmod`; report; commit `feat: c89-ahead — type alias (const T = <type>) (C89AHEAD)`.

- [ ] Steps: RED fixtures per the A1 classification → implement the missing registration/resolution (+ `pub` export if missing) → GREEN → N-hop → commit → report/ledger.

---

### Task A10: `volatile` feasibility (I → operator Go/No-Go → F on Go)

**Files:** report `## A10`; on Go: type-system `volatile` flag + `@volatileCast` + C89 pointee-qualified emission + `repro/mi_matrix/volatile_mmio_xmod`; on No-Go: `docs/reference/z98_bootstrap_manual.md` quirk note. Commit `feat: c89-ahead — volatile pointer qualifier (C89AHEAD)` or `docs: c89-ahead — volatile documented quirk (C89AHEAD)`.

- [ ] Steps: complete the feasibility research from A1 → present Go/No-Go with evidence → on Go implement RED→GREEN + N-hop + commit; on No-Go commit the docs note. Report/ledger.

---

### Task A11: Documentation (F) — dropped-feature idioms, safety mode, spec

**Files:** Modify `docs/reference/Language_Spec_Z98.md` (§3/§4/§5/§7 — remove `static`/`do…while` from "Not Yet Supported", add the documented idioms; document `-fsafe`/`-ffast`, `undefined`, diagnostics, `pal_trap`), `docs/reference/Caveats_and_Workarounds.md` (silent-mode guarantees), `README.md` (flag/workflow if needed); report; commit `docs: c89-ahead — failure semantics + feature idioms (C89AHEAD)`.

- [ ] Steps: apply the doc edits; verify no stale claim remains (spec §7 no longer lists dropped features as designed-but-unimplemented); commit; report/ledger.

---

### Task A12: Full battery + N-hop + gate re-baseline STOP-present (I, record-only)

- [ ] **Step 1: Full external battery** on the N-hop-converged `-ffast` compiler; per-feature fixtures GREEN; `-fsafe` differentials trap; golden 9/9 + matrix 21/21; canonical corpus zero-asymmetric; upgraded examples + net; mingw32 `-osw`; warning/compat POST ≤ PRE.
- [ ] **Step 2: N-hop determinism** from the committed seed (≤4 hops); record chain + new fixed point.
- [ ] **Step 3: STOP-present** moved 4-MD5 rows, new fixed point, and the A13 docs-GATE plan (including the emission-default change and any EXPECTED_FAIL bumps). Await operator approval.

---

### Task A13: Docs GATE + seed rotation (F, after operator approval)

**Files:** `docs/sf/QUICK_REF.md`, `repro/mi_matrix/EXPECTED_FAIL.md`, `release/seed/CHANGELOG.md`, `release/seed/zig1-seed.tgz`; report; commit `docs: GATE — c89-ahead failure semantics + features + seed rotation (C89AHEAD)`.

- [ ] **Step 1:** Rotate via `bash scripts/seed/archive_seed.sh <fixed-point-binary> <fresh-gen-dir> release/seed/zig1-seed.tgz --update-changelog`; verify archive md5 == CHANGELOG row, internal binary == approved fixed point, layout intact, 0 spill.
- [ ] **Step 2:** QUICK_REF gate-table rows (re-baselined) + newest-first bullet; EXPECTED_FAIL bump for the feature/diagnostic flips; README if needed.
- [ ] **Step 3:** Commit; report/ledger close; STOP-present the plan close.

