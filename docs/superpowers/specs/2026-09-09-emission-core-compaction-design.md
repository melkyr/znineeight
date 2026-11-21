# Emission-Core Compaction — Design Spec

**Date:** 2026-09-09 · **Branch:** zig1_improvements · **Type:** compiler internal (follow-up (b) to LIROPTPASS; emission-core compaction, semantics unchanged)

## 1. Purpose

Reduce zig1's C89 emission *at its structural core* — the lowering/emitter redundancy that LIROPTPASS could not reach because it is a **lowering-design artifact, not a LIR-pass limit**. Measured motivation (LIROPTPASS closeout census, self-emission `/tmp/t4e_run/g2/gen`, HEAD `14181290`, fixed point `048824c9`, 42 `.c` + 43 `.h` = 285,691 lines / 8,202,959 B):

| Class | Evidence | Count | Share of 285,691 lines |
|---|---|---|---|
| **Duplicate named-local stores** | consecutive identical `name = zT_N;` lines | **22,854** | ~8.0% |
| **Straight temp copies** | `zT_N = zT_M;` (arg-slot + other) | 14,194 | ~5.0% |
| all other statements | | ~248k | remainder |

Two independent redundancies, both emission-core and both structural (no semantic change):

1. **The duplicate named-local store** — each `const x = f()` / `x = expr` store is emitted as **2-3 identical consecutive `x = zT_N;` statements** (3×-dominant: 8,954 unique store lines appear exactly 3×; 2,604 appear 2×; 5,466 appear 1×; higher multiplicities exist up to ~45×). This is a **lowering consolidation gap** (bug-shaped): the lowerer maintains three representations of one store and the emitter renders all to identical C.
2. **The copy class** — `zT_N = zT_M;` straight copies, dominated by call-argument materialization into contiguous args-run slots, plus join-temp/loop/decl-init copies.

## 2. Binding operator decisions

- **Two parts, one plan.** Part 1 = duplicate named-local store (I then F, with **minimal repros**). Part 2 = copy census (I) defining an F series, one F per coalescible copy case.
- **Part-1 minimal repros stay in the corpus.** Task-2's fix is pinned by new minimal-repro fixtures committed to `repro/mi_matrix/` (corpus-bound). These repros are the permanent regression guard: they encode "**this is what a proper emission should look like**" — a named-local store emitted exactly once, no duplicate `x = zT_N;` lines. They must pass GREEN (byte-exact stdout) at HEAD-adjacent state and keep passing after the fix; their emitted-C must show no consecutive-duplicate named-store lines.
- **Compaction only; semantic optimization explicitly out.** This plan changes the *encoding* (fewer redundant stores/copies), never program semantics. No cross-BB/CFG/inlining/alias analysis.
- **Corpus is the primary accuracy oracle.** Every increment keeps the corpus **zero-asymmetric** (runtime class per directory unchanged); plus golden 9/9 + matrix 21/21 run byte-identity. "We are not losing accuracy" — the corpus sweep is the gate that proves it.
- **4-MD5 / runtime gates move by design.** Duplicate-store removal and copy coalescing change emitted C of gate programs. All four 4-MD5 dump-gates + golden/matrix runtime outputs are expected to move → **recorded-not-rebaselined per increment**, full re-baseline **only at the docs-GATE closeout** (operator-ruled).
- **Same closeout + seed rotation** as every plan since SEEDMIG: N-hop stabilization + behavioral identity (converged compiler re-runs the full external battery byte-identical) + Task-N docs GATE (QUICK_REF gate table + newest-first bullet + EXPECTED_FAIL check + `archive_seed.sh` rotation v5→v6).
- **Flag-set rule binding**: every gcc `-c` = `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`; `-Wall -Wextra -O3 -fsyntax-only` is a separate verification gate, never the build command. Reference rebuilt per the seed model; measurement compiler = the N-hop-converged binary, stated explicitly.

## 3. Part 1 — Duplicate named-local store

### 3.1 Verified mechanism (HEAD `14181290`)

A single named-local store goes through **three** LIR instructions that all render to the same C text:

| # | LIR inst | Source (lower.zig) | Renders to |
|---|---|---|---|
| 1 | `.store_local { name_id, value }` | decl path `:5500`; assign path `lowerAssignLValue :1119` | `name = value;` |
| 2 | `.assign { name_id=c_name, dst=dl_temp, src }` | decl path `:5504`; assign path `:1121` | `name = value;` (name_id != 0 overrides the temp dst, `c89_emit.zig:5682`) |
| 3 | `.assign { name_id=0, dst=reg, src }` | decl path `:5518` | `name = value;` (reg maps back to the name via the `fl_temps` reverse-lookup, `c89_emit.zig:5685`) |

The decl path (`const`/`var` with init) emits all three (`:5500` + `:5504` + `:5518`) = **3×**. The plain-assignment path (`lowerAssignLValue`) emits `:1119` + `:1121` (and `:5518`-equivalent when a backing `reg` exists) = **2×**. Additional store paths (value-block joins, capture binds, if/switch merge temps) produce the higher multiplicities.

**Consequence:** 2 of every 3 emitted `name = zT_N;` are dead stores (same name, same value, consecutive; last write wins, value identical). This is pure emission bloat: it inflates every function's C, every gcc instruction stream, and every compiled binary.

### 3.2 Investigation deliverable (I task)

For each of the three write-sites, determine which representation the **readers** actually consume:
- Do later uses of the name read the SSA temp (`dl_temp`, by temp-id → rendered via `fl_temps` back to the name) or read the name directly (via `.store_local`'s memory)?
- Produce the **minimal keep-set** per multiplicity: expected target = keep the single instruction that makes the value visible to all later readers, drop the rest. (Working hypothesis to be confirmed/refuted by the census: readers consume the backing temp through the `fl_temps`/`resolveTempName` interlock, so the `.assign` into the backing temp is the load-bearing write and `.store_local` + redundant `.assign`s are droppable — but the census must prove it from actual reader sites, not assume it.)
- Enumerate all multiplicities (2×, 3×, 4×…~45×) and all emitting sites so the F task covers every shape, not just the 3× decl path.
- Report the byte-size + line delta the fix is expected to yield on the self-emission and on representative examples.

### 3.3 Fix deliverable (F task) + minimal repros

- Collapse each redundant store to its minimal instruction set at the **single lowering source site(s)** the census identifies (fix the source, not a peephole in the emitter — keeps the emitter dumb).
- **Minimal repros (mandatory, corpus-bound):** author new `repro/mi_matrix/*_xmod` fixtures that (a) exercise each store multiplicity the fix touches (2×/3× and, where reachable, a higher-multiplicity value-block shape), (b) assert byte-exact runtime stdout (GREEN), and (c) whose **emitted C must contain no consecutive duplicate named-store lines** — the "proper emission" pin. Fixtures follow the corpus convention (header comment, `const std = @import("std")`, `pub fn main() void`, `std.io.printInt`/`std.io.writeByte`, GREEN contract in the header). These fixtures **stay in the corpus permanently** as regression guards.
- Gate: repros GREEN byte-exact; golden 9/9 + matrix 21/21 run byte-identity vs PRE captures; corpus zero-asymmetric (modulo the newly-added repro dirs moving from absent→OK); 4-MD5 recorded-not-rebaselined; N-hop converges to a new fixed point (recorded); commit message per convention.

## 4. Part 2 — Copy-class census → F series

### 4.1 The copy taxonomy (I task)

Classify every straight copy `assign dst src` / `store_local`-shaped site by case. Identified candidate cases (to be confirmed/completed by the census against the actual LIR):

1. **Arg-slot copies** — `assign dst=args_start+ai src=arg_val` filling the contiguous args-run (`lower.zig:3233, 3284, 3383, 3469, 3544`). Dominant share of the 14,194.
2. **Join-temp copies** — if/switch/orelse/catch merge results (`:3948, 3957, 3994, 4005, 4032, 4036, 4075, 4083`).
3. **Loop/iterator copies** — `:5118, 5171`.
4. **Tail-call self-call param copies** — `:5321`.
5. **decl_local init copies** — `:5474, 5480, 5504, 5518` (overlaps Part 1's multiplicity sites; census assigns each site to exactly one part).

Each copy is tagged **coalescible / not** by the agreed gate:

> Coalesce a copy `dst = src` (or rename src's producer result → dst) iff **all** of:
> (1) `hoisted_temps[src].type_id == hoisted_temps[dst].type_id` — identical `TypeId`, never "compatible"/"assignable";
> (2) both src and dst single-use (`rc==1` each);
> (3) src's producer is PURE and not addr-taken (`defReadsMemory`/`addr_taken` facts);
> (4) the pair is a scalar/pointer trivial move — no aggregate/optional/error-union/array copy, no `(T*)` cast-injection, no width-wrap (the existing `copyScalarKindOk` + type-identity guard).

Copies failing any gate stay materialized (they are the semantic/type boundary). The census reports per case: total count, coalescible count, non-coalescible count + reason, and the estimated byte delta.

### 4.2 F series (one F task per coalescible case)

Ordered by yield (arg-slot first). Each F task independently:
- Implements the coalescing for its case (rename producer-result → dst and tombstone the copy; the same backend-agnostic mechanics as LIROPTPASS copy-prop, extended only where the gate passes).
- Gate: corpus zero-asymmetric (primary); golden 9/9 + matrix 21/21 run byte-identity vs PRE; 4-MD5 recorded-not-rebaselined; N-hop convergence recorded; commit per convention.
- Type-identity rule is the correctness boundary: **no tricks** — if the census shows a case can't meet the type-identity gate, that case is recorded as "keep" and not forced.

## 5. Corpus / gates / measurement (whole plan)

- **Accuracy oracle = corpus**: current corpus state (HEAD `14181290`) = 419 dirs = 404 OK / 9 GREEN / 6 FAIL. Every increment: zero-asymmetric (only the newly-added Part-1 repro dirs move absent→OK). Runtime byte-identity additionally on golden 9 + matrix 21.
- **Emission gates move**: all four 4-MD5 dump-gates + golden/matrix runtime md5 move as emission shrinks → recorded-not-rebaselined each increment; **operator-ruled full re-baseline at the docs-GATE closeout**.
- **Part-1 repros are the "proper emission" pin**: emitted-C of the new fixtures must show exactly one store per logical named-local store (grep-able invariant: no consecutive duplicate `name = zT_N;` lines).
- **Metrics**: self-emission line + byte count (baseline 285,691 lines / 8,202,959 B) and gcc Row E (baseline 5.29 s / 167,752 kB) measured before (Task 1) and after (battery Task), delta reported. Duplicate-store removal ~8% line share and copy coalescing ~5% line share are the ceiling; measured reduction is the report.

## 6. Task list (implementation plan structure)

- Task 1 (I, record-only): baseline + Part-1 store-multiplicity census + Part-2 copy-taxonomy census (no commit).
- Task 2 (F): Part 1 — collapse duplicate named-local stores **+ author the minimal-repro corpus fixtures**.
- Task 3 (F): Part 2 — arg-slot copy coalescing.
- Task 4 (F): Part 2 — join-temp copy coalescing.
- Task 5 (F): Part 2 — remaining coalescible copy cases.
- Task 6 (I): full battery + N-hop + 4-MD5/gate re-baseline STOP-present (operator-ruled).
- Task 7 (F): docs GATE + seed rotation v5→v6 (after operator approval).

## 7. Out of scope (next upcoming plans — kept so we don't forget)

Recorded here as the forward queue, NOT tasks of this plan:

- **Stdlib growth** (usability lever #1): grow the 4-file / 389-line stdlib (string/io/math/debug modules); stdlib written in Z98 exercises + pins shipped features.
- **C89-ahead features worth covering**: `volatile` (HW/MMIO access), `static` function-local / file-scope, `do…while`, type-alias (`const T = u32`). (Skip `goto`/`long double`/preprocessor — comptime covers those; method syntax and named-`anytype` stay out.)
- Semantic optimization (cross-BB/CFG/inlining/loop transforms): deliberately deferred as too risky per operator ruling.
- LIROPTPASS record Minors carried forward for triage (lower.zig:1526 latent wide-enum-switch panic; two test EnumPayload constructors missing `.explicit_backing`; layout-B enum flag spurious; width-32+ admission-cap reliance).
