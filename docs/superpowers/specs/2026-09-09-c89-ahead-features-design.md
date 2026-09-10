# C89-Ahead Features + Divergence & Runtime Safety — Design Spec

**Date:** 2026-09-09 · **Amended:** 2026-09-10 · **Branch:** zig1_improvements · **Type:** language features + failure-semantics correctness

> **Amendment note (2026-09-10).** This spec was extended in place (operator ruling) to fold in a new,
> larger concern discovered while auditing the Z98 spec: constructs typed `noreturn` that do **not**
> diverge, and a family of **silent failure modes** that can corrupt memory without a diagnostic. The
> original C89-ahead feature set is re-scoped: `static` and `do…while` are **dropped** (real Zig has
> neither; the Zig idioms are documented instead), `type-alias` stays, and `volatile` stays as a
> feasibility-gated item. The failure-semantics work is the bulk of the amended plan. §3 is new; §4
> supersedes the original §3.

## 1. Purpose

Two goals:

1. **Failure-semantics correctness.** Make divergence actually diverge, add a Zig-style runtime safety
   mode (checked by default), and turn the worst silent-corruption modes into either checked operations
   or explicitly documented guarantees. Today `unreachable`, `@panic`, and every `orelse unreachable`
   lower to a no-op that falls through into the value path — so `std.arena.alloc(...) orelse
   unreachable` on exhaustion writes through a null/0 pointer. A real trap primitive (`pal_abort`)
   already exists in the runtime but is not wired to anything.
2. **C89-ahead features, Zig-aligned.** Where C89 still leads Z98, add the feature only where it maps to
   sane semantics: `type-alias` (`const T = <type>`) and `volatile` (Zig pointer-pointee qualifier).
   `static` and `do…while` are dropped in favour of documenting Zig's idioms.

## 2. Binding operator decisions

Original decisions (still in force):

- **`volatile` is NOT silently cut.** It gets an explicit feasibility task with an operator Go/No-Go;
  on No-Go the documented extern-`"c"`-wrapper quirk is the deliverable.
- **RED-first, feature-by-feature:** each item lands as a RED fixture (cleanly rejected/missing today) →
  implementation → GREEN byte-exact deterministic fixture → corpus classification.
- **Corpus is the primary accuracy oracle:** zero-asymmetric except the item's own new fixture dir(s);
  golden 9/9 + matrix 21/21 run byte-identity; 4-MD5 recorded-not-rebaselined per item and re-baselined
  only at the closeout STOP.
- **Bootstrap-staging constraint:** new compiler code must be written in constructs the current
  committed seed already understands; `sf/src` may adopt new syntax only after a new fixed point exists.
- **Flag-set rule:** every gcc `-c` = `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
  -Wno-implicit-function-declaration -I <inc>`; separate `-Wall -Wextra -O3 -fsyntax-only` verification
  gate. Self-emission link set = `zig_runtime.c` + `zig_pal.c` + `c_exit.c`.
- **Working conventions:** SDD mandatory; compression forbidden during build sessions; memories via
  `mnemoria --path .opencode/memory`; edits via `edit`/`fastedit` only; pre-existing dirty/untracked set
  never staged.

New decisions (2026-09-10):

- **Trap mechanism:** add a PAL primitive `pal_trap()` (x86 `int 3`; non-x86 fallback `pal_abort()`).
  `unreachable` and `@panic` lower to it **unconditionally** (not gated by the safety mode). `@panic`
  evaluates and prints its argument first, then traps, and is retyped `noreturn`.
- **Safety mode:** a Zig-style minimum/maximum split — `-fsafe` (**default**) enables runtime checks;
  `-ffast` disables them (today's behaviour). **All six checks** (cast, div/mod, shift, null-unwrap,
  index OOB, integer overflow) are gated by `-fsafe`. The **compiler builds itself with `-ffast`**
  (seed scripts pass it) to protect the 16 MB budget and keep the self-emission fixed point stable.
- **`undefined`:** under `-fsafe`, poison with `0xAA` (Zig-Debug style) so reads are detectable; under
  `-ffast`, keep the current deterministic zeroing. Documented either way.
- **`static` and `do…while`:** **dropped** as features. Document the Zig idioms (container-level `var`
  for persistent state; `while (true) { body; if (!cond) break; }` for a post-test loop).
- **Arena errors:** `std.arena.alloc` returns an error union (`error{OutOfMemory}`) instead of
  `?[*]u8`; migrate the consumers and delete `orelse unreachable`.
- **Document organization:** this spec and its plan are extended in place (no separate FAILSAFE doc).

## 3. Failure semantics (new)

### 3.1 Divergence — `unreachable`, `@panic`, `pal_trap()`

Current (broken) behaviour, confirmed:

- `unreachable` types as `noreturn` (`semantic_analyzer.zig:1846`) but lowers to a `nop` plus
  `block_terminated=1` (`lower.zig:2075-2078`); the emitter's `.nop => {}` (`c89_emit.zig:5715`)
  emits nothing, so the terminator-less block **falls through** into the next block.
- `@panic(msg)` is a recognised builtin (`semantic_analyzer.zig:285`) but has **no lowering arm** —
  it falls to `return nextTemp(TYPE_VOID)` (`lower.zig:3843-3844`), the argument is never lowered (its
  side effects are dropped), and it is typed as the argument rather than `noreturn`.
- Every `orelse unreachable` / `catch unreachable` / `if … else unreachable` inherits this: the arms
  fall through and the following `unwrap_optional`/`unwrap_error_payload` runs on an invalid value.

Design:

- New PAL primitive **`pal_trap()`**: declared in `sf/src/pal.zig` (extern) and implemented in
  `sf/src/include/zig_pal.c`. On x86 it executes `int 3` (GCC `__asm__ volatile("int3")`, MSVC
  `__debugbreak`, OpenWatcom `int 3`); on other architectures it falls back to `pal_abort()`.
  Debugger-friendly; without a debugger it still terminates the process.
- `unreachable` lowers to an explicit trap terminator (a backend-neutral LIR operation) that emits
  `pal_trap();`. It is **unconditional** — the safety mode does not affect it.
- `@panic(msg)` lowers as: evaluate `msg` (preserving side effects) → print (reuse the `std_panic`
  runtime pattern: `"panic: "` + message to stderr) → `pal_trap();`. It types as `noreturn`.
- `std.debug.assert`/`panic` (`sf/src/std_debug.zig`) switch from `while (true) {}` to `pal_trap()`
  so they terminate (debugger-breakable) rather than hang.

### 3.2 Safety mode — `-fsafe` / `-ffast`

- `-fsafe` (default) enables runtime checks; `-ffast` disables them.
- All six checks fail by calling `pal_trap()` (same primitive as §3.1):
  1. **`@intCast` overflow** — complete the checked-helper coverage: the emitter currently sets
     "checked" for narrowing/equal-width-sign-change casts but only has helper pairs for 19 cases
     (`c89_emit.zig:5282-5322`); missing pairs (e.g. `i8_from_i16`, `u16_from_u32`) silently emit a
     plain C cast. Add the missing helpers (or a general checked path) so every narrowing `@intCast`
     traps on overflow.
  2. **Division/modulo by zero** — a guard before `/` and `%`.
  3. **Shift count ≥ width** — a guard before `<<`/`>>`.
  4. **Optional unwrap on null** — the `unwrap_optional` path (and `orelse`/capture paths) must trap
     when `has_value == 0` instead of reading a garbage payload.
  5. **Index out of bounds** — `base[i]` (array and slice) checks `i < len` before the access.
  6. **Integer overflow** for `+`, `-`, `*` (and unary negation) on integer types.
- **Backend-neutral expression:** each check is expressed in LIR (a check-with-trap operation), not as
  a C-only peephole, so future non-C89 backends can materialize equivalent guards.
- **Compiler self-build:** `scripts/seed/build_from_seed.sh` and `scripts/seed/archive_seed.sh` pass
  `-ffast` when emitting the compiler's own C, and the flag-set/closure gate records the `-ffast`
  fixed point. User programs default to `-fsafe`; a program built `-fsafe` therefore differs in
  emission from the same program built `-ffast` (documented).
- **Bootstrap-staging wrinkle:** the committed seed predates the flag and will not understand `-ffast`.
  Task A1 must design the staging (the seed emits today's unchecked behaviour on hop 1; hop 1 — which
  understands `-ffast` — emits the `-ffast` checked-off form on hop 2; closure hop2==hop3).

### 3.3 `undefined`

- `-fsafe`: initialize `undefined` storage with `0xAA` bytes (integrals; aggregates byte-filled) so an
  erroneous read is visible/high-entropy rather than a plausible zero.
- `-ffast`: keep the current deterministic zeroing.
- Documented in the manual as a Z98 guarantee, not a Zig guarantee.

### 3.4 Compile-time diagnostics (mode-independent)

These match Zig's compile errors and do not depend on `-fsafe`:

- **Uninitialized variable:** `var x: T;` without an initializer is an error; require an initializer or
  explicit `= undefined`.
- **Ignored error union:** a statement whose expression is an error union and whose result is unused is
  an error (must be `try`/`catch`/assigned).
- **Missing return:** falling off the end of a non-void function, or a bare `return;` in a non-void
  function, is an error (today both silently produce `return 0`).

### 3.5 Arena error handling

- `std.arena.alloc(self, size)` returns an error union (`error{OutOfMemory}`), not `?[*]u8`.
- Migrate `alloc_bytes` in the example parsers, the json parsers, and
  `repro/mi_matrix/extern_runtime_symbol_xmod/lib.zig` to `try`/`catch`. Delete every
  `std.arena.alloc(...) orelse unreachable`.
- `init`/`reset` are unchanged.

## 4. Features (supersedes original §3)

### 4.1 `static` — DROPPED (document the Zig idiom)

Real Zig has no `static` keyword. Persistent state is expressed by a **container-level `var`**
(program-lifetime storage); visibility is `pub`/non-`pub`/`export`, orthogonal to storage; a
function-local `var` is always automatic. C89's `static` conflates three unrelated things (file-scope
internal linkage, function-local static storage + init-once, static initialization) — the operator
ruling is to **not** add it. Deliverable: documentation + a fixture proving module-scope `var`
persistence works, plus a manual note recording the rationale.

### 4.2 `do…while` — DROPPED (document the Zig idiom)

Real Zig has no post-test loop. Document `while (true) { body; if (!cond) break; }` as the idiom
(noting the `continue` caveat: in the emulation `continue` skips the condition test, so a body using
`continue` must restructure). No language change.

### 4.3 Type-alias (kept)

Formalize `const T = u32;` (and aliases to composites: `const MyList = [16]u8;`,
`const MyStruct = SomeStruct;`) so the alias registers as a usable type name in annotations, params,
returns, and `@sizeOf(T)`, resolving to the aliased type. Census first: `const T = <type>` may already
half-work; the task completes whatever is missing (registration as a type, use in annotations, `pub`
alias export across modules). GREEN example: `const Handle = u32;` used as a param/field with
`@sizeOf(Handle)`.

### 4.4 `volatile` (kept — feasibility-gated)

- **Real-Zig semantics:** `volatile` is a **pointer-type qualifier** (`*volatile T`, `[*]volatile T`,
  `[*c]volatile T`) plus the `@volatileCast` builtin; there is no `var volatile` storage qualifier.
- **Z98 mapping cost:** a `volatile` flag on pointer types, a `volatile` keyword in pointer-type
  position, `@volatileCast`, and correct C89 placement (pointee-qualified `volatile T *`, **not**
  pointer-qualified `T * volatile`).
- **Ruling:** an operator Go/No-Go after the feasibility task. Go → implement (RED→GREEN fixture, e.g.
  an MMIO-style `*volatile u32` read/write against a normal array). No-Go → record the manual quirk note
  ("write an `extern "c"` wrapper whose body is the volatile C access") and close as annotated, never
  silently dropped.

## 5. Corpus / gates / measurement

- **RED fixtures first:** each item's fixture classifies RED at plan start; after the item lands it is
  GREEN byte-exact deterministic (RUNRC=0) and stays in the corpus.
- **`-fsafe` vs `-ffast` differential fixtures:** the same program built both ways, with a trap expected
  in `-fsafe` and the current behaviour in `-ffast`.
- **Corpus zero-asymmetric per item** (only its own dir(s) move); golden 9/9 + matrix 21/21 run
  byte-identity vs PRE; 4-MD5 recorded-not-rebaselined per item.
- **Self-compile N-hop closure** after each compiler-touching item; fixed point moves and is recorded;
  re-baselined operator-ruled at the closeout STOP.
- **Warning/compat:** emitted C stays warning-clean under `-Wall -Wextra -O3 -fsyntax-only`; compat audit
  greps POST ≤ PRE (no bare `long long`, no >31-char identifiers, no `%zu`, no empty macro args).
- **Emission default changes:** because `-fsafe` is the default, the four 4-MD5 gate programs' dumps and
  the compiler's own emission change → full re-baseline at the docs GATE.

## 6. Task list (implementation plan structure)

- **A1 (I, record-only):** baseline + feasibility census — trap mechanism, flag plumbing + seed staging,
  safety-check emission sites per check, diagnostics sites, arena migration census, type-alias
  classification, volatile research, and the RED state of every silent mode. STOP-present.
- **A2 (F):** `pal_trap()` + divergence fix (`unreachable`, `@panic`, `std.debug`).
- **A3 (F):** `-fsafe`/`-ffast` framework + `undefined` poison.
- **A4 (F):** cheap runtime checks (`@intCast`, div/mod, shift, null-unwrap).
- **A5 (F):** index out-of-bounds runtime check.
- **A6 (F):** integer-overflow runtime check.
- **A7 (F):** compile-time diagnostics (uninitialized var, ignored error union, missing return).
- **A8 (F):** arena error-union API + consumer migration.
- **A9 (F):** type-alias verify/finish.
- **A10 (I→F):** `volatile` feasibility → implement or document quirk.
- **A11 (F):** documentation (dropped-feature idioms, `undefined`/safety-mode docs, spec §7 update).
- **A12 (I):** full battery + N-hop + gate re-baseline STOP-present.
- **A13 (F):** docs GATE + EXPECTED_FAIL bump + seed rotation (after operator approval).

### 6.1 Per-feature investigation protocol (2026-09-10)

Every feature/implementation task (**A2–A11**) is split into a dedicated investigation phase **`A<n>I`**
(record-only) followed by its implementation phase **`A<n>F`**. Before any code is written, `A<n>I` must:
answer the task's feature-specific question set (full text in the plan, AMENDMENT 3), enumerate the
caveats the implementation must respect, append its findings to the report, and **STOP-present** to the
operator. `A<n>F` does not start until the operator approves the I result. If an answer changes a
feature's shape or contradicts this spec, that is itself a STOP-present. A1 remains the plan-wide
census; A12 remains the closeout I; A13 (docs GATE) is gated by A12 and needs no separate I.

Question-set topics per feature (full sets: plan AMENDMENT 3):

- **A2I** — trap C body per toolchain; LIR terminator shape + consumer changes; `@panic`→`noreturn`
  fallout; fall-through removal per parent construct; gate-program/self-emission movement; `std.debug`
  switch; A2-only fixed-point movement.
- **A3I** — flag parse/plumbing; two-hop bootstrap staging; `undefined` poison per type class;
  `-fsafe`-default corpus/size impact; A2 interaction.
- **A4I** — LIR check forms + anchors; `@intCast` helper gap; UB-free div/shift forms; null-unwrap path
  census; `-ffast` byte-identity.
- **A5I** — length source array vs slice; guard form/placement/index normalization; unchecked `[*]T`;
  constant-OOB; corpus/size.
- **A6I** — C89 + cross-toolchain overflow detection (no `__builtin_*` assumed); type coverage; budget;
  relation to shift overflow; wrapping corpus.
- **A7I** — diagnostic hook sites/data; codes/severity; corpus fallout + STOP-if-non-mechanical.
- **A8I** — supported error-set syntax; error-union ABI/`try`; caller census/migration; byte-identity.
- **A9I** — current type-alias behaviour; missing sites; `pub`/headers; fixtures.
- **A10I** — type-system threading; `@volatileCast`; C89 qualifier placement; fixture + Go/No-Go.
- **A11I** — docs staleness audit; implementation-vs-docs verification.

## 7. Out of scope (later plans / queue)

- `static` and `do…while` as language features (documented idioms instead).
- `@errorName`, `extern struct`/`opaque`/`vector`, generics/`anytype`/`@Type`/`@typeInfo`/`comptime`,
  `anyerror`, `@cImport` (remain §7 "Not Yet Supported" in the language spec).
- Other C89 features deliberately skipped: `goto`, `long double`/`f80`, preprocessor macros, method
  syntax, named `anytype`, threaded/`_Thread_local`.
- Fully reversing `-ffast` semantics to `-fsafe` for the compiler's own build (the compiler stays
  `-ffast`).

## 8. Risks

- **Bootstrap staging** of the `-fsafe`/`-ffast` flag across the committed seed (A1 designs it; the seed
  predates the flag).
- **Emission-size / performance** of `-fsafe` on 1998-class targets: mitigated by `-ffast` for the
  compiler build and by gating every check behind the flag.
- **Corpus churn**: enabling `-fsafe` by default can flip fixtures that previously relied on wrap/OOB;
  any flip is recorded and reviewed, not silently absorbed.
- **Over-broad checks** could reject currently-working programs (e.g. the compile-time diagnostics); RED
  fixtures and the corpus gate bound this.
- **`@intCast` helper completion** may enlarge the emitted runtime; measured against the size budget.
