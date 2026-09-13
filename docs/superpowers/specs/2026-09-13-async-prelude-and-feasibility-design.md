# Z98 Async Coroutines + Win9x Calling-Convention Prelude — Design

**Date:** 2026-09-13
**Branch:** `zig1_improvements`
**Baseline:** HEAD `14129e68`; compiler fixed point `1467d932a876402f40a56316dfcad0e5`; seed v10 (`ca18fc9f…`); corpus 570 = 541 OK / 29 GREEN / 0 FAIL; `EXPECTED_FAIL.md` v77.

**Status:** DESIGN-ONLY. This spec captures the intended design and is executed by an
investigation-only plan. No `sf/src` change is authorized by this spec; every stage
below is either a design decision or an investigation item to be validated by the
feasibility spike. Async work proceeds only on a Go from the spike's STOP-present;
the Win9x prelude designs stand regardless of the async outcome.

**Seed material:** `sf/docs/corroutines.txt` (untracked; `.gitignore:52` ignores `*.txt`).
Its 6-stage proposal is the starting point. The plan moves it to a tracked path
(`docs/superpowers/specs/2026-09-13-z98-coroutine-ideas.md`) verbatim so the design
reference is in-tree.

---

## 1. Problem and motivation

Two independent problems are addressed in one spec because the second needs the first
for Win9x viability.

**1a. Win32 calling convention.** Win32 API functions use `__stdcall` on x86. Z98
currently has no calling-convention concept: the string in `extern "c" fn …` is parsed
and **discarded** (`sf/src/parser.zig:1554-1556`), and the convention is not represented
in the AST, type registry, LIR, or emitter. Extern non-variadic functions are emitted
**without a prototype** (`sf/src/c89_emit.zig:2418, 2566`), so current Win32 calls are
correct only by luck: `net_prelude.h` pulls in `<windows.h>`/`<winsock.h>`, whose real
`__stdcall` prototypes the C compiler sees at the call site. `mud_server` works because
it goes through `net_prelude.h` wrappers rather than declaring `WSAStartup` directly. A
user who declares an extern Win32 function without that include gets a `__cdecl`
assumption and a corrupted stack on return.

**1b. Async coroutines.** `sf/docs/corroutines.txt` proposes async builtins
(`@asyncFrameSize`, `@asyncInit`, `@asyncResume`, `@asyncSuspend`) plus a `std.async`
library and example integration. Recon shows the feature is greenfield: there is no
call graph, no `is_suspending`, no AST/liveness dataflow, no frame synthesis, and no
builtins. Two facts force design work: (i) the LIR already carries a basic-block CFG, so
the state-machine stages should attach to LIR rather than AST; (ii) `@asyncFrameSize`
cannot be a comptime constant because `phase_ComptimeEvaluation` (`sf/src/main.zig:490`)
runs before sema/lowering and no function-symbol→constant path exists.

**1c. Related prelude checks.** `extern struct` is unparsed (`sf/src/parser.zig:1072-1112`
has no `kw_extern` type branch) and not needed unless Z98's single layout path fails to
match the Win32 ABI. Inline assembly is unsupported (no token, no builtin).

---

## 2. Vision

A Z98 program can (a) declare extern functions with an explicit calling convention so
that direct Win32 calls are stack-correct without relying on an include, and (b) write
suspendable functions driven cooperatively by a scheduler on top of four type-erased
builtins, with the return-path/pointer rules enforced by the compiler.

## 3. Scope

This spec governs a **single shared plan** whose only outputs are documentation,
census/anchors, throwaway hand-written C89 prototypes, and a Go/No-Go recommendation:

- **Prelude A:** calling-convention qualifier design (`extern "stdcall"`/`"cdecl"`).
- **Prelude B:** `error[3020]` rule for taking a suspending function's pointer.
- **Prelude C:** `extern struct` / Win32 ABI layout verification.
- **Prelude D:** inline-asm status documentation.
- **Async:** Stage 1–6 design mapped to the compiler + feasibility spike.

## 4. Non-goals

- No implementation of any feature in this plan (no `sf/src` edits).
- No `@typeInfo`/`@Type`/`comptime`/generics; no threads or preemption.
- No `std.Io` event-loop abstraction; the scheduler is cooperative only.
- No port of `rogue_mud`/`mud_server` to coroutines in this plan (that is candidate
  sub-project 3 if async is a Go).
- No change to the compiler fixed point, seed, or `EXPECTED_FAIL` version.

---

## 5. Locked decisions

| # | Decision | Value |
|---|---|---|
| L1 | Suspension model | **Implicit await** (doc-literal): `@asyncSuspend` is an explicit yield, and a bare call to a suspending function is a suspension point. |
| L2 | Builtin surface | `@asyncFrameSize(fn)`, `@asyncInit(buf: [*]u8, fn) *void`, `@asyncResume(frame: *void, arg: *void) ?*void`, `@asyncSuspend(data: *void) *void`. |
| L3 | Result delivery | Caller-provided `*void` slot (no generics). |
| L4 | Prelude A syntax | `extern "<conv>" fn NAME(...) ...;` and `extern "<conv>" fn(params) Ret` as a function-pointer type. Valid strings: `"c"`/`"cdecl"` (= cdecl, default) and `"stdcall"`. Unknown string → new diagnostic. |
| L5 | Prelude A emission | Emit the convention on the extern prototype/definition and on the fn-pointer typedef. **Force a prototype for an extern function when a convention is present** (today none is emitted). |
| L6 | Prelude B error site | Taking a suspending function's address (fn-pointer formation/coercion) is the error site; not the call site. |
| L7 | Prelude C oracle | `i686-w64-mingw32-gcc` + `<windows.h>` printing `sizeof`/`offsetof` for `WNDCLASSEX` (+ `POINT`, `MSG`), compared to Z98's computed layout for an equivalent normal struct. |
| L8 | Spike depth | Record-only census **plus** three hand-written C89 prototypes, built and run deterministically. |
| L9 | Plan type | Investigation-only; no implementation. |

## 6. Investigation-driven (the spike must resolve; no value locked now)

- `@asyncFrameSize` timing/value mechanism (runtime-materialized constant vs an early
  AST pass vs another route).
- Implicit-await **frame ownership**: how a caller obtains/holds/drives a callee frame
  (embedded child frame vs caller-allocated from a Task arena), and the resulting
  frame-size composition.
- The exact new LIR op set and whether it fits `@sizeOf(LirInst)` / `lir_stream`.
- Liveness analysis cost and `-s<N>` spill impact.
- Whether `extern struct` is required at all (depends on the ABI oracle).
- Error/warning code assignments (3020 is taken; 3017-3019/3021/3022/3024-3029 free).

---

## 7. Current reality (recon verdicts)

**Reusable as-is:** function pointers (locals, struct fields, returns, recursive via
parameter, indirect calls — `repro/mi_matrix/fn_ptr_struct_field`,
`examples/z98/func_ptr_return`, `examples/z98/quicksort`); `*void`/`?*void` and
`@ptrCast` fn↔`*void` (`repro/mi_matrix/inferred_errorset_fnptr`); error unions +
`try`/`catch`; optionals incl. as struct fields (`repro/mi_matrix/dup_optptr_field_emit`);
`defer`/`errdefer` execution (`lower.zig:6174-6208`); declaration-order struct layout and
packed structs (`type_resolver.zig:129-160`); `@sizeOf`/`@alignOf`/`@offsetOf`
(`comptime_eval.zig:126-234`); arbitrary-width `u1..u64`/`i1..i63`; `if`/`switch`
expressions; recursion/TCO (`lower.zig:5771-5810`).

**Greenfield (nothing exists):** the four `@async*` builtins
(`semantic_analyzer.zig:257-298` lacks them); `is_suspending` (`symbol_table.zig:4-12`
has no such field); a program-wide call graph; AST-level CFG/liveness; frame synthesis;
state-machine lowering; `std.async` (grep over `sf/src/std*.zig` = 0 hits).

**Pipeline facts that shape the design**
- Phase order (`sf/src/main.zig:283-323`): import resolution → symbol registration →
  type resolution → front resolution → **comptime evaluation** → semantic analysis →
  static analyzers → **LIR lowering** → C89 emission.
- LIR already has a block CFG: `BasicBlock {id, insts, is_terminated}` (`lir.zig:280`)
  with `jump`/`branch`/`switch_br`/`ret` terminators, built by `lower.zig:createBlock`.
- Lowering already splits expressions into statement-level temps (`nextTemp`,
  `hoisted_temps`), so the doc's "AST lifting" is effectively already done.
- `-s<N>` spilling exists with `SPILL_COUNT = 5` (`spill_store.zig:16`).
- New LIR ops are appended variants; the union must stay ≤32 bytes
  (`lir.zig:110-167`), and `lir_stream.zig` serializes raw bytes.
- Gate harnesses (battery/matrix/run24/classify) are **not committed**; they live only
  under `/tmp` and must be reproduced/ported by the plan.

---

## 8. Prelude A — calling convention (design)

**Surface.**
```zig
extern "stdcall" fn MessageBoxA(hwnd: *void, text: [*]const u8, cap: [*]const u8, typ: u32) i32;
extern "cdecl"   fn printf(fmt: [*]const u8, ...) i32;      // exists today as extern "c"
const Cb = extern "stdcall" fn(i32) void;                    // fn-pointer type
```

**Current state (anchors).** The string is parsed and dropped
(`parser.zig:1554-1556`); only the `0x04` `is_extern` flag survives (`ast.zig:118`,
`type_registry.zig:84`). No convention token exists anywhere. Fn types carry
`FnPayload { …, is_extern, flags_packed }` with `flags_packed` bit0 = variadic and the
remaining bits free (`type_registry.zig:84`); `Type.flags` bits 0 (fn-ptr-used) and 1
(volatile) are used, bits 2-7 free (`type_registry.zig:76,612`). Emission has no
convention keyword (`c89_emit.zig:2134-2241`); the only convention string in the
compiler is `__cdecl` on `mainCRTStartup` (`c89_emit.zig:1021`).

**Design.**
1. Validation: capture the `extern` string and classify into `cdecl` (default; accept
   `"c"` and `"cdecl"`) or `stdcall`; anything else → a new `error[3xxx]`.
2. Representation: store the convention on the fn type (a free `FnPayload.flags_packed`
   bit, or a small field), so a `fn(...)T` value and its pointer typedefs agree.
3. Emission: emit the convention keyword/attribute on the extern prototype/definition
   and on the function-pointer typedef. Because x86 `__stdcall` decoration is
   target-specific, the emitter must place it portably (e.g. `__cdecl`/`__stdcall`
   tokens under MSVC/Watcom, `__attribute__((stdcall))`/`__attribute__((cdecl))` under
   gcc) and must not break the linux gates, where the tokens are inert or gated.
4. **Force a prototype** for an extern function when a convention is present (today
   non-variadic externs get none), so the convention actually takes effect.
5. `fn(...)T` types participate: forming/assigning a fn pointer of one convention to
   another is not a valid coercion.

**PAL coverage evaluation (spike).** Audit every Win32 call reachable from the compiler
and `std_net` (`zig_pal.c` calls `GetStdHandle`/`WriteConsoleA`/`WriteFile`/
`TerminateProcess`/`GetCurrentProcess`/`CreateFileA`/`ReadFile`/`CloseHandle`/
`GetFileAttributesA`/`GetModuleFileNameA`/`ExitProcess`; `net_prelude.h` supplies
Winsock prototypes). Classify each as "already safe via an include" vs "needs the
qualifier if declared directly", and document when a user must use the qualifier.

**Risks.** Convention placement differs per toolchain; `__stdcall` name decoration on
i386 (leading underscore + `@N`); variadic `__stdcall` is invalid; linux/gcc gates must
stay byte-identical when no convention is used.

## 9. Prelude B — `error[3020]` for suspending function pointers (design)

A `fn(i32) void` value cannot hold a suspending function because the call protocol
differs (a suspending call may yield, which a plain function pointer call cannot). The
error is raised at the **taking of the function's address** — where the function is used
as a value / coerced to a fn-pointer type — not at the call site. This requires
`is_suspending` from Stage 1. Rule and error site are specified now; implementation
belongs to the async implementation plan.

## 10. Prelude C — `extern struct` / Win32 ABI layout (design + verification)

Recon: `extern struct` is unparsed; all structs use one C-like layout path
(`type_resolver.zig:129-160`) with natural `alignUp` offsets and tail padding. The spike
compiles a C oracle with `i686-w64-mingw32-gcc` printing `sizeof`/`offsetof` for
`WNDCLASSEX`, `POINT`, and `MSG`, and compares it to Z98's computed layout for an
equivalent normal struct (via `@sizeOf`/`@offsetOf` dumps; optionally run under wine).
Outcome: either confirm the normal path matches the Win32 ABI (no `extern struct`
needed) or record exactly where it diverges and open `extern struct` as a follow-up.

## 11. Prelude D — inline assembly status

No `asm`/`__asm`/`@asm` token or builtin exists (`token.zig:5-114`;
`semantic_analyzer.zig:100-159`). The spec records that inline assembly is **not
accepted** in Z98 source, and documents the supported route (an `extern "c"`/
`extern "stdcall"` helper compiled out of band, or a PAL/runtime helper). `__asm`
appears only inside generated C for `pal_trap` (`zig1_seed` runtime bytes), which is not
a language feature.

## 12. Async design (Stages 1–6 mapped to the compiler)

### 12.1 Stage 1 — suspension detection
- Host: a new program-wide pass after import resolution (all modules parsed,
  `main.zig:359`) and before lowering, with `is_suspending` stored on the function
  `Symbol` (`symbol_table.zig:4-12`) or a `CompilerContext` side table
  (`main.zig:94-121`).
- Algorithm: extract direct callee edges from the AST, then a worklist fixed point:
  a function is suspending iff its body contains `@asyncSuspend` **or** it calls a
  suspending function. Verify termination on mutual recursion.
- Function pointers: `error[3020]` at address-taking (Prelude B).
- `main`/`export fn` may be suspending.

### 12.2 Stage 2 — frame layout
- Attach CFG + liveness to the existing **LIR** block graph (not AST). Compute locals,
  params, and temps live across each suspension point.
- Synthesize a frame: `state: uN` (u8/u16/u32 by suspension-point count) + hoisted
  locals (natural alignment) + all params. Preserve declaration order for determinism.
- Precedent for same-function layout code: `lir_opt_pass.zig` per-function analyses and
  emitter DCE (`c89_emit.zig:~8060-8200`). Per-function scratch reset pattern:
  `main.zig:722`, `c89_emit.zig:2644,2843`.

### 12.3 Stage 3 — state-machine lowering
- A new LIR-to-LIR transform (like `lir_opt_pass`): for each suspending function emit
  a frame struct and a `_step` function with `state` dispatch (entry 0, per-suspension
  `case N`, terminal). Suspension stores live state, sets next state, returns; resume
  switches on state.
- The implicit-await model means a bare call to a suspending callee is a suspension
  point; the spike resolves frame ownership (embedded child frame vs arena-allocated).
- New LIR ops only if required; must fit the `@sizeOf(LirInst)` ≤32 bytes and the
  `lir_stream` byte contract.

### 12.4 Stage 4 — builtin lowering
- Add the four builtins to the sema allow-list/typing (`semantic_analyzer.zig:100-298`,
  `:2087-2219`) and the lowering dispatch (`lower.zig:3911`).
- `@asyncSuspend` outside a suspending function → error; inside `defer`/`errdefer` →
  the existing invalid-scope error code (note: the speculated `ERR_4002` ban is
  currently **unenforced**, so this rule may need to be introduced).
- Buffer-too-small / null frame: `-fsafe` trap, `-ffast` UB (documented).

### 12.5 Stage 5 — `std.async`
- New `sf/src/std_async.zig` (concrete, no generics) re-exported from
  `sf/src/std.zig`; `Task`/`Scheduler` plain structs with cooperative
  `cancel_requested`; `suspend`/`awaitTask`/`addTask`/`tick`/`cancelAll`/`waitAll`.
- Install-surface touchpoints: seed `lib/` (`scripts/seed/build_from_seed.sh:139`,
  `scripts/seed/archive_seed.sh:109`), self-build (`scripts/self_compile/build_zig1_5.sh:12`),
  QUICK_REF install recipe, and the seed-archive std set.

### 12.6 Stage 6 — integration (candidate sub-project 3, not this plan)
Convert `rogue_mud` NPC AI and `mud_server` per-connection handling to coroutines;
cross-module task create/schedule/cancel; goldens must stay byte-identical.

### 12.7 Error codes
`3020` is taken (`ERR_3020_UNHANDLED_NODE_KIND`, `diagnostics.zig:47`) and `3023` is
`WARN_3023_MODULE_AS_VALUE` (`:50`); free are `3017-3019`, `3021`, `3022`, `3024-3029`.
The spec intentionally does **not** fix numbers; the spike recommends the assignment.

---

## 13. Testing strategy

- Prelude A: fixtures proving convention capture, prototype emission, fn-pointer
  typedefs, default-cdecl byte-identity, and the unknown-convention diagnostic. A Win32
  oracle (mingw/wine) is used if a runnable check is available; otherwise an emitted-C
  inspection gate.
- Prelude C: the mingw `windows.h` layout oracle vs Z98 dumps.
- Async: three hand-written C89 prototypes (`P1` minimal frame/step, `P2` implicit-await
  nesting, `P3` 3-task scheduler with cancel and error-union delivery), built and run
  deterministically with md5 evidence. No compiler fixtures until the async
  implementation plan.
- No fixed point / seed / corpus re-baseline occurs in this plan.

## 14. Go/No-Go criteria and decomposition

**Go** requires: all three prototypes build and run deterministically; every async stage
has a viable bounded attach point; no fatal blocker; a clear implementation
decomposition emerges. Otherwise **No-Go** for async (the prelude designs still stand).

Recommended decomposition if Go: (1) compiler core — Stages 1–4; (2) `std.async` —
Stage 5; (3) integration/port — Stage 6. The spike's STOP-present recommends the final
split.

## 15. Open investigation items (spike output)

1. `@asyncFrameSize` value mechanism.
2. Implicit-await frame ownership and frame-size composition.
3. New LIR op set + `@sizeOf`/`lir_stream` fit.
4. Liveness cost + `-s<N>` spill impact.
5. Win32 calling-convention PAL coverage audit (which direct declarations need A).
6. Whether `extern struct` is needed (ABI oracle result).
7. Error/warning code assignment for async + the calling-convention diagnostic.
8. Whether the `defer`/`errdefer` invalid-scope ban must be introduced before the async
   rules can be enforced.
