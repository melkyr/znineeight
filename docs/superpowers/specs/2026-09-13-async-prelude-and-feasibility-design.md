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
- **Prelude B:** `error[3017]` rule for taking a suspending function's pointer.
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
| L2 | Builtin surface | `@asyncFrameSize(fn)`, `@asyncInit(ctx: *Context, buf: [*]u8, fn, args) *void`, `@asyncResume(frame: *void, arg: ?*void) ?*void`, `@asyncSuspend(data: ?*void) *void`. `ctx` is NEW and stored in the frame; `buf` is the root frame, caller-owned and outside the pool (m1166/m1172). **Amendment 7:** the signature stays `@asyncResume(frame, arg)` (no step parameter) — it **self-dispatches via the frame step word** (pointer-sized, offset 0). |
| L3 | Result delivery | Caller-provided `*void` slot (no generics). |
| L4 | Prelude A syntax | `extern "<conv>" fn NAME(...) ...;` and `extern "<conv>" fn(params) Ret` as a function-pointer type. Valid strings: `"c"`/`"cdecl"` (= cdecl, default) and `"stdcall"`. Unknown string → new diagnostic. |
| L5 | Prelude A emission | Emit the convention on the extern prototype/definition and on the fn-pointer typedef. **Force a prototype for an extern function when a convention is present** (today none is emitted). |
| L6 | Prelude B error site | Taking a suspending function's address (fn-pointer formation/coercion) is the error site; not the call site. |
| L7 | Prelude C oracle | `i686-w64-mingw32-gcc` + `<windows.h>` printing `sizeof`/`offsetof` for `WNDCLASSEX` (+ `POINT`, `MSG`), compared to Z98's computed layout for an equivalent normal struct. |
| L8 | Spike depth | Record-only census **plus** three hand-written C89 prototypes, built and run deterministically. |
| L9 | Plan type | Investigation-only; no implementation. |

## 6. Investigation-driven items (resolved by the spike)

Spike resolutions (evidence in `.superpowers/sdd/task-ASYNCPRELUDE-report.md`):

- **`@asyncFrameSize` timing/value mechanism → runtime-materialized constant.** It
  lowers to an ordinary `int_const` emitted during lowering, sourced from a
  pre-lowering frame-size table built by the Stage-1 AST pass; the early-AST
  `comptime` pass is rejected (runs before sema/lowering, needs a duplicate
  type/layout resolver, and cannot see final LIR liveness). [§15.1]
- **Implicit-await frame ownership → caller/Context-pool child frames on a per-task
  frame stack.** The root frame lives in the caller-owned `buf`, outside the pool;
  nested suspending calls allocate child frames from a per-task LIFO frame stack
  (`ctx` read from the current frame). Per-function flat frame size, no transitive
  composition, mutual recursion safe. [§15.2; m1166, m1172]
- **New LIR op set → 0 mandatory new `LirInst` variants.** The state machine is
  expressible with existing control flow + a synthesized frame struct. Optional
  12-byte ops appended after `width_wrap` keep `@sizeOf(LirInst)` = 32 and leave the
  `lir_stream` raw-byte contract untouched; >20-byte payloads go through
  `side_table`. [§15.3]
- **Liveness analysis cost and `-s<N>` spill impact → no new spill level.** The
  async pass reuses the `lir_opt_pass` rc/wc locator pattern, O(blocks×insts) per
  function, per-function scratch; `SPILL_COUNT = 5` and `-s0..-s5` are unchanged
  (async data is runtime/scratch, not compiler IR). [§15.4]
- **`extern struct` → not required.** The ABI oracle proved Z98's single normal
  layout path matches the Win32 (i686) ABI for `WNDCLASSEX`/`POINT`/`MSG`. [§15.6]
- **Error/warning code assignment → explicit numeric values.** `ErrorCode` is an
  auto-incrementing `enum(u16)`; the free codes are `3017-3019` and `3045-3047`; all
  new members must be appended with an explicit `= NNNN` (never a bare member). See
  §12.7. [§15.7] **Amendment 7:** those values are now assigned (`3017/3018/3019`
  async, `3045` Track 1, `3046` async, `3047` optional advisory); the **next free
  value is `3049`**, claimed by the Res-6 1-arg `@ptrCast` diagnostic
  (`ERR_3049_PTRCAST_REQUIRES_TWO_ARGS`).

**Non-negotiable.** The five recorded concerns below MUST be resolved as part of the
**Prelude B** (suspending-fn-pointer) ban; the async Stage-1 dynamic-call soundness
argument depends on every one of them:

1. `fn_ptr_struct_field` emission gap (`repro/mi_matrix/fn_ptr_struct_field` emits the
   field as `void`) — **CLOSED at HEAD (Amendment 7; re-verified 2026-09-14 at the
   Task-5c review-fix fixed point `d6e7cb84e6e9615bc81f3e86ad92ffa5`: the corpus
   `fn_ptr_struct_field` and a minimal `struct{f: fn(i32)i32}` probe both emit a real
   fn-pointer member and indirect-call correctly).** The ruled architecture no longer
   depends on this (the frame carries a raw pointer-sized step word at offset 0 and
   `@asyncResume` self-dispatches).
2. Module-scope mutable globals (`module_pub_var_int` runtime gap) — blocks a global
   scheduler; `std.async` must take a caller-supplied `Scheduler`/`Task`.
3. Frame-size single source of truth — the pre-lowering size table and the Stage-2
   synthesized frame layout must agree, or a caller buffer under-sizes.
4. Dynamic-call soundness — Stage 1 ignores fn-pointer calls, which is sound **only**
   because Prelude B (`ERR_3017`) forbids materializing a suspending function as a
   value; the ban must be enforced in the same implementation plan.
5. Explicit numeric diagnostic codes — every new code appended with `= NNNN`, or
   downstream codes (including ICE `3043` and `ERR_3048_CANNOT_READ_FILE`) silently
   shift. (This also corrects the previous list, which wrongly named
   `3021/3022/3024-3029` as free.)

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
(volatile) are used, and **bit 4 is packed (`0x10`, `typeRegistrySetPacked`,
`type_registry.zig:1057`, read at `type_resolver.zig:133`)**, so the free bits are
`2, 3, 5, 6, 7` (`type_registry.zig:76,612`). Emission has no
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

**Future migration (operator ruling m1155-A).** Once Prelude A is implemented and A.4
forces extern prototypes, `sf/src/std_net.zig` and any related Win32 extern std calls
MUST migrate to `extern "stdcall"` (otherwise the emitted prototype conflicts with the
real `winsock.h` declaration). `std_net` externs to migrate: `htons`/`htonl`
(`std_net.zig:18-19`), `socket`/`bind`/`listen`/`setsockopt` (`:35-38`),
`accept_os`/`connect_os`/`send_os`/`recv_os`/`select_os`/`close_os` (`:39-44`),
`closesocket`/`WSAStartup`/`WSACleanup` (`:45-47`). This is a mandatory
**future-implementation** step, not part of this investigation plan.

**Risks.** Convention placement differs per toolchain; `__stdcall` name decoration on
i386 (leading underscore + `@N`); variadic `__stdcall` is invalid; linux/gcc gates must
stay byte-identical when no convention is used.

## 9. Prelude B — `error[3017]` for suspending function pointers (design)

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
- Function pointers: `error[3017]` at address-taking (Prelude B).
- `main`/`export fn` may be suspending.

### 12.2 Stage 2 — frame layout
- Attach CFG + liveness to the existing **LIR** block graph (not AST). Compute locals,
  params, and temps live across each suspension point.
- Synthesize a frame: `ctx: *Context` (set at init; **every frame carries it** and
  codegen reads it from the current frame, m1166) + `state: uN` (u8/u16/u32 by
  suspension-point count) + all params + hoisted locals/temps live across a suspension
  (natural alignment). Preserve declaration order for determinism.
- `@asyncFrameSize(fn)` returns this per-function **flat** size and EXCLUDES child
  frames (m1166). The runtime total is the sum of frame sizes along the active call
  chain (a 10-deep chain of 40-byte frames uses 400 bytes, not 40).
- Single source of truth for the size: the pre-lowering table (§15.1) and the Stage-2
  layout consume the same `frame_size` value (non-negotiable concern 3, §6).
- Precedent for same-function layout code: `lir_opt_pass.zig` per-function analyses and
  emitter DCE (`c89_emit.zig:~8060-8200`). Per-function scratch reset pattern:
  `main.zig:722`, `c89_emit.zig:2644,2843`.

### 12.3 Stage 3 — state-machine lowering
- A new LIR-to-LIR transform (like `lir_opt_pass`): for each suspending function emit
  a frame struct and a `_step` function with `state` dispatch (entry 0, per-suspension
  `case N`, terminal). Suspension stores live state, sets next state, returns; resume
  switches on state.
- **Pool semantics (m1172).** `buf` (the root frame passed to `@asyncInit`) is
  OUTSIDE the pool and is NOT pool-managed; the caller owns it and allocates it
  wherever. The pool is for CHILD frames only and is shaped as a **per-task frame
  stack** (not a shared bump allocator). A suspending call site reads `ctx` from the
  CALLER's frame, allocates + initializes a child frame, then resumes it. LIFO is
  enforced naturally (the child is freed exactly when it returns): a bump pointer plus
  a mark, no free list and no fragmentation. This resolves the Task-3 root-vs-pool
  ambiguity.
- The implicit-await model means a bare call to a suspending callee is a suspension
  point; frame ownership is the per-task child-frame stack above.
- Deep recursion exhausts the pool and returns `error.OutOfFrame` (NOT a crash); pool
  size is the caller's choice at context creation (m1166).
- New LIR ops only if required; must fit the `@sizeOf(LirInst)` ≤32 bytes and the
  `lir_stream` byte contract — 0 mandatory new variants (§15.3).

### 12.4 Stage 4 — builtin lowering
- Add the four builtins to the sema allow-list/typing (`semantic_analyzer.zig:100-298`,
  `:2087-2219`) and the lowering dispatch (`lower.zig:3911`).
- `@asyncSuspend` (and context-invalid `@asyncInit`/`@asyncResume`) outside a
  suspending function → `ERR_3018_ASYNC_SUSPEND_OUTSIDE_SUSPENDING = 3018`; inside
  `defer`/`errdefer` → `ERR_3019_ASYNC_BUILTIN_IN_DEFER = 3019` (or revive the dead
  `ERR_4002_DEFER_IN_INVALID_SCOPE`). The `defer`/`errdefer` ban is NOT a prerequisite
  (§15.8).
- `@asyncFrameSize` on a non-suspending/unknown function →
  `ERR_3046_ASYNC_FRAME_SIZE_INVALID = 3046`.
- Pool exhaustion at a suspension point → `error.OutOfFrame`, not a crash (m1166).
- Buffer-too-small / null frame: `-fsafe` trap, `-ffast` UB (documented).

### 12.5 Stage 5 — `std.async`
- New `sf/src/std_async.zig` (concrete, no generics) re-exported from
  `sf/src/std.zig`; `Task`/`Scheduler`/`Context` plain structs with cooperative
  `cancel_requested`; `suspend`/`awaitTask`/`addTask`/`tick`/`cancelAll`/`waitAll`.
- `Context` owns the caller-sized per-task frame pool (a frame stack for child frames);
  the root `buf` frame is separate and caller-owned (m1172). No global scheduler
  (module-scope mutable globals are a non-negotiable concern, §6).
- Install-surface touchpoints: seed `lib/` (`scripts/seed/build_from_seed.sh:139`,
  `scripts/seed/archive_seed.sh:109`), self-build (`scripts/self_compile/build_zig1_5.sh:12`),
  QUICK_REF install recipe, and the seed-archive std set.

### 12.6 Stage 6 — integration (candidate sub-project 3, not this plan)
Convert `rogue_mud` NPC AI and `mud_server` per-connection handling to coroutines;
cross-module task create/schedule/cancel; goldens must stay byte-identical.

### 12.7 Error codes
`ErrorCode` is an auto-incrementing `enum(u16)` (`diagnostics.zig:10`), so every new
member MUST carry an explicit numeric value or it silently shifts every downstream code
(including ICE `3043` and `ERR_3048_CANNOT_READ_FILE`). `3020`
(`ERR_3020_UNHANDLED_NODE_KIND`, `diagnostics.zig:47`) and `3023`
(`WARN_3023_MODULE_AS_VALUE`, `:50`) are taken. The truly free codes are **`3017-3019`
and `3045-3047`** (the earlier list `3021/3022/3024-3029` was wrong: it is occupied by
auto-incremented members). Assigned explicitly:

| Code | Name | Use |
|---|---|---|
| `3017` | `ERR_3017_SUSPENDING_FUNCTION_POINTER` | Prelude B: taking a suspending function's address / coercing it to a fn pointer (operator ruling m1155-B; explicit `= 3017`). |
| `3018` | `ERR_3018_ASYNC_SUSPEND_OUTSIDE_SUSPENDING` | An async builtin used outside a suspending function. |
| `3019` | `ERR_3019_ASYNC_BUILTIN_IN_DEFER` | An async builtin inside `defer`/`errdefer` (alternative: revive the dead `ERR_4002_DEFER_IN_INVALID_SCOPE`). |
| `3045` | `ERR_3045_UNKNOWN_CALLING_CONVENTION` | Prelude A: unknown `extern "<conv>"` string. |
| `3046` | `ERR_3046_ASYNC_FRAME_SIZE_INVALID` | `@asyncFrameSize` applied to a non-suspending/unknown function. |

`3047` remains free/optional. Preserve `ERR_3048_CANNOT_READ_FILE = 3048` and every
existing explicit value; append all new members with `= NNNN`, never as a bare member.

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

### 14.1 Verdict: **GO** (async); the Win9x prelude designs stand independently

| Criterion | Evidence | Result |
|---|---|---|
| P1–P3 build and run deterministically | `gcc -m32 -std=c89 -O0`, exit 0, byte-exact stdout (`p1 3`, `p2 10`, exact 5-line P3), identical md5 across 3 runs (`52ef279a…`, `6a770034…`, `b9cc5130…`). | PASS |
| Every async stage has a viable bounded attach point | Stage 1 `phase_SuspensionAnalysis` after `phase_SymbolRegistration` (`main.zig:290`); Stage 2/3 on the existing LIR CFG; Stage 3 transform between `lowerFn` and `lirStreamAppend` (`main.zig:719-720`); Stage 4 sema allow-list + lowering dispatch; Stage 5 new `std_async.zig` + install touchpoints; Stage 6 examples. | PASS |
| No fatal blocker | No compiler change needed for the design; 0 mandatory new `LirInst`; no new spill level; the Prelude C ABI matches. | PASS |
| A clear decomposition emerges | The two independent sub-projects in §14.2. | PASS |

### 14.2 Recommended decomposition

Two independent implementation tracks. The async track gates on this Go; the prelude
track may proceed regardless.

**Track 1 — Win9x calling-convention prelude (sub-project 1).**
1. Prelude A: capture/represent/emit `extern "stdcall"`/`"cdecl"`, force a prototype
   when a convention is present, and add `ERR_3045_UNKNOWN_CALLING_CONVENTION`.
2. Explicit numeric diagnostic codes (Prelude B `ERR_3017`, Prelude A `ERR_3045`) with
   explicit `= NNNN` values.
3. `std_net.zig`/related Win32 extern migration to `extern "stdcall"` (operator ruling
   m1155-A, §8). (`extern struct` is confirmed unnecessary; inline asm stays documented
   as unsupported.)

**Track 2 — async coroutines.**
1. **Compiler core — Stages 1–4:** suspension analysis/`is_suspending`; LIR frame
   layout; LIR-to-LIR state-machine transform; builtin + diagnostic plumbing.
2. **`std.async` — Stage 5:** concrete no-generics `Task`/`Scheduler`/`Context`
   library + install touchpoints.
3. **Integration/port — Stage 6:** `rogue_mud`/`mud_server` coroutine conversion
   (candidate sub-project 3); goldens stay byte-identical.

The Prelude B ban (`ERR_3017`) and the five non-negotiable concerns in §6 must land
with Stage 1, or Stage 1's dynamic-call soundness does not hold.

## 15. Investigation items — RESOLVED (with evidence)

All items below are resolved by the feasibility spike; evidence is in
`.superpowers/sdd/task-ASYNCPRELUDE-report.md` (Tasks 1–3) and the referenced source
anchors. None remain open.

1. **`@asyncFrameSize` value mechanism — RESOLVED.** Runtime-materialized `int_const`
   emitted during lowering, from a pre-lowering frame-size table built by the Stage-1
   AST pass; the early-AST `comptime` pass was rejected. (§6; Task 2 §4.2)
2. **Implicit-await frame ownership and frame-size composition — RESOLVED.**
   Caller/Context-pool child frames on a per-task LIFO frame stack; `@asyncFrameSize`
   is the per-function flat size excluding child frames; the runtime total is the sum
   of frame sizes along the active call chain; `buf` is outside the pool.
   (m1166/m1172; Task 3. Errata: `OpFrame` = 16 B under `gcc -m32`, so P3's live
   footprint is 60 B, not 56 B.)
3. **New LIR op set + `@sizeOf`/`lir_stream` fit — RESOLVED.** 0 mandatory new
   variants; optional 12-byte ops appended after `width_wrap` keep `@sizeOf(LirInst)`
   = 32 and leave the raw-byte `lir_stream` contract untouched; >20-byte payloads go
   via `side_table`. (Task 2 §3.4)
4. **Liveness cost + `-s<N>` spill impact — RESOLVED.** O(blocks×insts) per function
   with per-function scratch; no new spill level (`SPILL_COUNT = 5` unchanged). (Task 2 §2.4)
5. **Win32 calling-convention PAL coverage audit — RESOLVED.** All Win32/Winsock calls
   are safe via include today; `std_net` externs must migrate to `extern "stdcall"`
   once A.4 forces prototypes (operator ruling m1155-A). (Task 1 §2; §8)
6. **Whether `extern struct` is needed — RESOLVED.** Not needed: Z98's normal struct
   matches the Win32 (i686) ABI for `WNDCLASSEX`/`POINT`/`MSG` (48/0/8/20/40, 8/0/4,
   28/0/4). (Task 1 §4)
7. **Error/warning code assignment — RESOLVED.** Explicit values in §12.7:
   `3017`/`3018`/`3019`/`3045`/`3046`; `3047` optional; `ERR_3048` preserved. (Task 2 §4.3)
8. **Whether the `defer`/`errdefer` invalid-scope ban must be introduced — RESOLVED:
   no.** No enforcement exists (`ERR_4002` is dead; `break`/`continue` outside loops are
   silently ignored), so the async `defer` rule is a new additive check (reuse
   `ERR_3019` or revive `ERR_4002`); the general ban is a separate hardening item, not a
   prerequisite. (Task 2 §6.2)

## 16. Implementation subspecs and plans (execution order)

The feasibility spike (this spec + `docs/superpowers/plans/2026-09-13-async-prelude-and-feasibility-plan.md`) is complete. Implementation is split into four independently testable tracks, each with its own subspec derived from this spec and its own amendable plan. Execute in order; each plan's `Sequence` line names the previous and the next plan.

| # | Subspec | Plan | Depends on |
|---|---|---|---|
| 1 | [`2026-09-13-win9x-calling-convention-design.md`](./2026-09-13-win9x-calling-convention-design.md) | [`2026-09-13-win9x-calling-convention-plan.md`](../plans/2026-09-13-win9x-calling-convention-plan.md) | — |
| 2 | [`2026-09-13-async-compiler-core-design.md`](./2026-09-13-async-compiler-core-design.md) | [`2026-09-13-async-compiler-core-plan.md`](../plans/2026-09-13-async-compiler-core-plan.md) | Track 1 (call-convention surface) |
| 3 | [`2026-09-13-std-async-design.md`](./2026-09-13-std-async-design.md) | [`2026-09-13-std-async-plan.md`](../plans/2026-09-13-std-async-plan.md) | Track 2 (builtins/frame surface) |
| 4 | [`2026-09-13-coroutine-integration-design.md`](./2026-09-13-coroutine-integration-design.md) | [`2026-09-13-coroutine-integration-plan.md`](../plans/2026-09-13-coroutine-integration-plan.md) | Track 3 (`std.async`) |

Chain: **1 → 2 → 3 → 4.** Tracks 1 and 2 move the compiler fixed point (N-hop + seed rotation in their closeout tasks); Track 3 changes the seed `lib/` (8 → 9 std files) without moving the fixed point; Track 4 is examples-only (no fixed point / seed movement).

### 16.1 Cross-track reconciliations owed before advancing

Surfaced by the four authoring passes; each must be resolved in the owning subspec/plan (or here) before the dependent track starts. None changes the Go verdict. **Status at Amendment 7: items 1, 2 and 4 are RESOLVED; item 3 is DEFERRED (documented before Track 3); items 5–6 are standing coordination notes.**

1. **`Context` ABI ownership (Track 2 vs Track 3) — RESOLVED (Amendment 7, Res 1): INLINE.** `ctx` owns a slice to the caller-provided pool (`buf` is outside the pool); no heap, no fixed array inside the struct, no generics. The compiler reads the pool fields inline at the frozen Track-3 layout (bump + mark); the Track-2 "opaque" wording is amended. Pinned caller idiom — `var pool: [4096]u8 = undefined; var ctx = std.async.Context.init(pool[0..]);` — is an explicit **"verify at Track 3"** item.
2. **`fn_ptr_struct_field` status — RESOLVED (Amendment 7): CLOSED at HEAD.** Re-verified at the Task-5c fixed point `d6e7cb84…`; the ruled architecture does not depend on it (frame step word + self-dispatch). The Track-3 `Task.step` decision is moot: `Task.step` is removed.
3. **`std.async` value-position gap — DEFERRED (Amendment 7, Res 4).** Bare `@import("std")` + `std.async.Task{...}` / `std.async.TaskState.ready` hits pre-existing `error[3042]` + `warning[3023]`. **Documented before Track 3; NOT resolved before Track 3** (the documented direct-import workaround stands). A compiler follow-up may add value-position re-export later.
4. **`@asyncInit` `args` ABI — RESOLVED (Amendment 7, B3):** adopt the pinned struct-of-params ABI (`?*const void`, null for zero params) and fix the Task-6 fixtures accordingly (struct-of-params `args` plus the 2-arg `@ptrCast(T, expr)` form). No ABI change.
5. **Shared `ErrorCode` band.** Tracks 1 and 2 both append explicit-valued members (Track 1 `ERR_3045`; Track 2 `ERR_3017/3018/3019/3046`; **Amendment 7 adds the non-async Res-6 code `ERR_3049_PTRCAST_REQUIRES_TWO_ARGS = 3049`**). Order-independent because every member is `= NNNN`; both subspecs keep the explicit-value discipline.
6. **Track ordering.** Track 3's hand-written step fixtures need no `@async*` builtins, so it may start before Track 2 lands; if Track 2 lands first, Track 3 records the new fixed point/seed at its Task 1. Track 4 depends on Track 3.
