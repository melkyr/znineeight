# C89-Ahead Features — Design Spec

**Date:** 2026-09-09 · **Branch:** zig1_improvements · **Type:** language features (covers areas where C89 still leads Z98; runs after Stdlib Growth in the forward queue)

## 1. Purpose

Add Z98 source-language features for the areas where the **C89 target feature set still leads Z98**: persistent function-local state, post-test loops, and type aliases. Each feature is a small, bounded compiler-frontend change (parse → AST → sema → lowering → emission) following the exact INTWIDTH/PACK pattern (RED fixture first, GREEN byte-exact, corpus-gated). One feature — `volatile` — is genuinely risky to map and is handled as an explicit **feasibility task** inside this plan, per operator ruling (NOT silently cut as a quirk).

## 2. Binding operator decisions

- **Feature order (operator B1): `static` first, then `do…while`, then type-alias.** `volatile` is fourth and gated on its own feasibility task (B2).
- **`volatile` is NOT cut.** It is deferred to a feasibility task inside THIS plan (operator ruling m0963: "it cuts the genuine corner… have the Feasibility task inside the c89 ahead plan"). The feasibility task researches real-Zig `volatile` semantics (`*volatile T` pointer qualifier + `@volatileCast` builtin — NOT a var/const storage qualifier), assesses Z98 type-system + C89 emission cost (the `volatile int*` vs `int *volatile` pointer-vs-pointee placement trap), and produces an operator-ruled decision: implement, or record the documented workaround (extern `"c"` wrapper performing the volatile C access) as a quirk note. The task's output decides; the feature is not pre-committed either way.
- **RED-first, feature-by-feature:** each feature lands as RED fixture (cleanly rejected/missing today) → implementation → GREEN byte-exact deterministic fixture → corpus classification. Small increments; review per feature.
- **Corpus is the primary accuracy oracle** (same convention as every plan): current 420 dirs = 404 OK / 9 GREEN / 7 FAIL (post-EMITCOMPACT). Each feature: corpus zero-asymmetric except its own new fixture dir(s). Golden 9/9 + matrix 21/21 run byte-identity. 4-MD5 dump gates: a feature that changes emission of a gate program moves its md5 → **recorded-not-rebaselined per feature**, operator-ruled full re-baseline at closeout only.
- **Closeout + seed rotation** at the final task: N-hop + behavioral identity (converged compiler re-runs the full external battery byte-identical) + docs GATE (QUICK_REF gate table + newest-first bullet + EXPECTED_FAIL bump per fixture movement + `archive_seed.sh` rotation).
- **Bootstrap-staging constraint (binding, seed model):** new-feature compiler code must be written in constructs the current committed seed already understands; `sf/src` may adopt new syntax only after a new fixed point exists. Every compiler edit converges a new fixed point via N-hop.
- **Flag-set rule binding:** every gcc `-c` = `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`; separate `-Wall -Wextra -O3 -fsyntax-only` verification gate, never the build command. Self-emission link set = `zig_runtime.c` + `zig_pal.c` + `c_exit.c`.
- **Working conventions:** SDD mandatory; compression forbidden during build sessions; memories via `mnemoria --path .opencode/memory` under agent `<plan>-session`; edits via `edit`/`fastedit` only; no commit until review clean; pre-existing dirty/untracked set never staged.

## 3. Feature specifications

### 3.1 `static` (first)

Z98 today rejects `static` (the keyword is absent from `token.zig`; the manual documents "No `static`"). Two C89-carrying uses:

- **Function-local `static var`** — a local whose storage persists across calls (C89 `static` local). Z98 lowering currently emits every local as a stack/hoisted temp with per-call lifetime; `static var x = init;` must emit as a function-scoped `static` C variable, initialized once. Grammar: `static var x: T = expr;` (and `static const`? — C89 has no static const distinction that matters here; support `static var` first, `static const` if the census shows it is free).
- **File-scope `static`** — a module-level symbol not exported across the module boundary (C89 `static` at file scope / internal linkage). Z98 module-level `pub var`/`pub fn` are exported; a `static var`/`static fn` at module scope is internal (no cross-module symbol, no header declaration).

Emission: `static` storage-class keyword in the C decl for the local; file-scope static suppresses the `pub` export path (`export`/header emission). Sema must reject `static` where it is meaningless (parameters, `const`-only contexts if unsupported) with a clean `error[3000]`.

RED fixture: `static` keyword today → parse `error[2000]` (expected). GREEN contract example: a counter `fn next() i32 { static var n: i32 = 0; n += 1; return n; }` printing `1 2 3` across calls; a file-scope-static symbol proven absent from the emitted cross-module header.

### 3.2 `do…while` (second)

Z98 has `while` but no post-test loop. Add `do { body } while (cond);` → lowers to C `do { } while (cond);` (a `do` keyword + grammar arm + lowering emitting a `do-while` C construct, or the existing `loop_header`/branch machinery if the emitter already has the shape). Constraints: mandatory braces on the body (C89 `do` requires a statement; Z98 convention), `cond` typed `bool`/int like `while`, `break`/`continue` behave as in `while`.

RED fixture: `do` keyword today → parse `error[2000]`. GREEN contract example: `var i: i32 = 5; do { std.io.printInt(i); i -= 1; } while (i > 0);` printing `5 4 3 2 1`; plus a zero-iteration-guaranteed-absent shape (`do { … } while (false)` body still runs once — the defining post-test property).

### 3.3 Type-alias (third)

Formalize `const T = u32;` (and aliases to composites: `const MyList = [16]u8;`, `const MyStruct = SomeStruct;`). Z98 already supports `const E = enum…` / `const S = struct…` declarations; a `const T = <existing-type-expr>` alias must register `T` as a usable type name in annotations, params, returns, and `@sizeOf(T)` — resolving to the aliased type with the alias name visible to error messages. Census first: check whether plain `const T = u32;` already parses/resolves today (it may half-work via `const` + type-expr path); the task completes whatever is missing (registration as a type, use in annotations, `pub` alias export across modules).

RED fixture: an alias that fails today (exact form per census). GREEN contract example: `const Handle = u32;` used as a param/field/`@sizeOf(Handle)` printing the aliased size.

### 3.4 `volatile` (fourth — feasibility-gated)

Research (census) deliverable, operator-ruled before any implementation commit:

1. **Real-Zig semantics** (from langref): `volatile` is a pointer-type qualifier (`*volatile T`, `[*]volatile T`, `[*c]volatile T`) plus the `@volatileCast` builtin; there is no `var volatile` storage qualifier. Volatile access = load/store through a volatile-qualified pointer.
2. **Z98 mapping cost:** adding a `volatile` flag to pointer types (TypeKind/ptr payload or a flag), a `volatile` keyword in pointer-type position, `@volatileCast`, and C89 emission that places `volatile` at the correct position for the target pointer kind (pointee-qualified `volatile T *` vs pointer-qualified `T * volatile`) — with the C89 31-char/type-name machinery respected.
3. **Risk:** type-system flag threading through `ptr_type` creation/coercion/lowering; the known C qualifier-placement trap; emission of the qualifier only where the C89 dialect allows it.
4. **Ruling:** present findings + a Go/No-Go to the operator. Go → implement (RED→GREEN fixture, e.g. an MMIO-style `*volatile u32` read/write against a normal array). No-Go → record the quirk note in the manual: "if you need volatile, write an `extern "c"` wrapper whose body is the volatile C access" (the `extern_c_z98.zig` + `@cInclude` machinery already supports this) and close the feature as annotated, NOT silently dropped.

## 4. Corpus / gates / measurement

- **RED fixtures first:** each feature's fixture classifies as RED (parse error / clean reject) at plan start; after the feature lands it is GREEN byte-exact deterministic (RUNRC=0), its dir moves into the corpus as a permanent regression pin.
- **Corpus zero-asymmetric per feature** (only its own dir(s) move); golden 9/9 + matrix 21/21 run byte-identity vs PRE captures; 4-MD5 recorded-not-rebaselined per feature.
- **Self-compile N-hop closure** after each compiler-touching feature; fixed point moves and is recorded; re-baselined operator-ruled at the closeout STOP.
- **Warning/compat:** emitted C stays warning-clean under the `-Wall -Wextra -O3 -fsyntax-only` gate; compat audit greps POST ≤ PRE (no bare `long long`, no >31-char identifiers, no `%zu`, no empty macro args, decl-lines non-increasing for the C89-ahead changes — a new feature may legitimately add decl lines only in its own programs).

## 5. Task list (implementation plan structure)

- Task 1 (I, record-only): baseline + per-feature RED reproduction + `volatile` feasibility research part 1 (Zig semantics + Z98 mapping cost + risk), corpus/gate baseline. No commit.
- Task 2 (F): `static` — function-local `static var` + file-scope `static`, RED→GREEN fixture.
- Task 3 (F): `do…while` — parse/lower/emit, RED→GREEN fixture.
- Task 4 (F): type-alias — `const T = <type>`, RED→GREEN fixture.
- Task 5 (I/F): `volatile` feasibility task — complete research, present Go/No-Go to the operator; on Go implement RED→GREEN; on No-Go record the quirk note. (Operator-ruled before commit.)
- Task 6 (I): full battery + N-hop + gate re-baseline STOP-present.
- Task 7 (F): docs GATE + EXPECTED_FAIL bump + seed rotation (after operator approval).

## 6. Out of scope (later plans / queue)

- `volatile` implementation ONLY if the Task-5 feasibility ruling goes Go (otherwise the documented extern-C-wrapper quirk note is the deliverable).
- Other C89 features deliberately skipped: `goto` (comptime/control-flow covers), `long double`/`f80`, preprocessor (`@cInclude` covers), method syntax, named `anytype`, threaded/`_Thread_local`.
- Stdlib growth (separate plan, runs before this one in the queue).
- EMITCOMPACT executes before Stdlib Growth in the forward queue.
