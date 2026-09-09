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
