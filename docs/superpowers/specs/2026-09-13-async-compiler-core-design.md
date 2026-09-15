# Z98 Async Compiler Core (Track 2) — Design

**Date:** 2026-09-13
**Branch:** `zig1_improvements`
**Baseline HEAD:** `f755dbed`; compiler fixed point `1467d932a876402f40a56316dfcad0e5`;
seed v10 (`ca18fc9f9af55d58147fcb7ff7a662b6`); corpus 570 = 541 OK / 29 GREEN /
0 FAIL; `EXPECTED_FAIL.md` v77.

**Parent spec:** [`2026-09-13-async-prelude-and-feasibility-design.md`](./2026-09-13-async-prelude-and-feasibility-design.md).
**Derives from:** umbrella §5 (locked decisions L1–L9, esp. L1 implicit-await,
L2/m1166 `@asyncInit(ctx, buf, fn, args)`, L3 caller result slot, L6 Prelude B
error site), §6 (the five non-negotiable concerns), §12 Stages 1–4, §15
resolutions (especially §15.1 runtime-materialized frame size, §15.2/m1172 frame
ownership, §15.3 0 mandatory new `LirInst`, §15.4 no new spill level, §15.7
explicit numeric codes), §14.2 Track 2, and the umbrella Global Constraints.

**Sibling subspecs:**
[`2026-09-13-win9x-calling-convention-design.md`](./2026-09-13-win9x-calling-convention-design.md) (Track 1),
[`2026-09-13-std-async-design.md`](./2026-09-13-std-async-design.md) (Track 3),
[`2026-09-13-coroutine-integration-design.md`](./2026-09-13-coroutine-integration-design.md) (Track 4).
**Previous subspec:** win9x-calling-convention.
**Next subspec:** std-async.

**Plan:** [`../plans/2026-09-13-async-compiler-core-plan.md`](../plans/2026-09-13-async-compiler-core-plan.md).
**Status:** draft, amendable in place.

---

## 1. Scope

This subspec governs the **compiler core** of async coroutines — umbrella §14.2
Track 2 items **Stages 1–4 only**:

- **Stage 1 — suspension analysis.** A program-wide `is_suspending` fixed point
  over the AST call graph, hosted in a new `phase_SuspensionAnalysis` after
  `phase_SymbolRegistration` (`sf/src/main.zig:290`); plus the Prelude B
  `ERR_3017` ban at function-value materialization.
- **Stage 2 — frame layout.** Per-suspending-function flat frame layout computed
  on the existing LIR CFG (`sf/src/lir.zig:280-284, 494-513`) with the
  `lir_opt_pass` read/write-locator scratch pattern; the authoritative
  pre-lowering `frame_size` table.
- **Stage 3 — state-machine lowering.** A LIR-to-LIR transform run between
  `lowerFn` and `lirStreamAppend` (`sf/src/main.zig:719-720`) that rewrites each
  suspending function into a `_step` state machine (`switch_br` dispatch,
  `load_field`/`store_field` save/restore, `ctx`-in-frame, child frames from a
  per-task LIFO frame stack, `error.OutOfFrame`).
- **Stage 4 — builtin + diagnostic plumbing.** `@asyncFrameSize`,
  `@asyncInit`, `@asyncResume`, `@asyncSuspend` in sema
  (`sf/src/semantic_analyzer.zig:64-93, 99-159, 257-298, 2087-2219`) and lowering
  (`sf/src/lower.zig:3911`), with explicit numeric diagnostics.

Tracks 3 and 4 are out of scope here: this subspec **produces** the runtime /
builtin surface that `std.async` (Track 3) consumes, and does not implement it.

## 2. Non-goals

- No `std.async` library (`Task`/`Scheduler`/`Context`), no scheduler loop, no
  install-surface edits (Track 3).
- No `rogue_mud`/`mud_server` port (Track 4).
- No calling-convention capture/emission and no `std_net` migration (Track 1),
  except for the shared diagnostic-enum band and the explicit `= NNNN` rule.
- No generics, `@typeInfo`, threads, preemption, or `std.Io` event loop
  (umbrella §4).
- No new spill level: `SPILL_COUNT = 5` and `-s0..-s5` are unchanged
  (umbrella §15.4).
- No `extern struct`; no inline asm (umbrella §10/§11).
- No change to the fixed point, seed, or corpus in the design itself — the plan
  owns all gate movement and the N-hop seed rotation at closeout.

## 3. Detailed design

### 3.1 Stage 1 — suspension analysis and `is_suspending`

**Attachment point.** A new `fn phase_SuspensionAnalysis(ctx: *CompilerContext) void`
in `sf/src/main.zig`, invoked in `runCompiler` immediately after
`phase_SymbolRegistration` (line `:290`) and its `checkCombinedPeak` (line
`:291`), before `phase_TypeResolution` (`:292`). At that point every module is
parsed (`phase_ImportResolution`, `main.zig:359`) and every function symbol
exists (`phase_SymbolRegistration`, `main.zig:402`), so
`symbolRegistryQualifiedLookup` (`sf/src/symbol_table.zig:141`) resolves direct
callees. The pass is not run inside `phase_LIRLowering` (`main.zig:626`) because
the call graph must be program-wide while lowering is per-function and streamed.

**Storage — `CompilerContext` side tables** (rejected: a `Symbol.flags` bit,
because flags are node-kind-dependent and `has_capture`/`is_mutable` collide;
see umbrella §6 and the spike Task 2 §1.2). Add to `CompilerContext`
(`main.zig:94-121`), initialized from `&compiler_alloc.module` next to
`exported` (`main.zig:253-278`) so they survive to sema/lowering and are reset
only by `sandReset(&ctx.alloc.module)` at `main.zig:321`:

```zig
suspending_fns: hash_mod.U64ToU32Map, // key=(module_id<<32)|name_id; value 0/1
frame_sizes:    hash_mod.U64ToU32Map, // key=(module_id<<32)|name_id; value=bytes
```

Key helper and read accessors (module `sf/src/async_analysis.zig`, new file):

```zig
pub fn asyncKey(module_id: u32, name_id: u32) u64 {
    return (@intCast(u64, module_id) << @intCast(u64, 32)) | @intCast(u64, name_id);
}
pub fn asyncIsSuspending(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) bool;
pub fn asyncFrameSizeOf(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) ?u32;
```

The same `*hash_mod.U64ToU32Map` is threaded into `SemanticAnalyzer` and
`LirLowerer` as a new field/param, mirroring the existing `enum_val_tab` /
`call_arg_types` pattern (`main.zig:484, 538, 666`).

**AST edge extraction.** For every `ModuleEntry` (`sf/src/module_registry.zig:27`)
walk `astStoreNodeExtraChildren(store, entry.ast_root)`; for each
`AstKind.fn_decl` the body is `node.child_0` (parser `sf/src/parser.zig:1652`;
lowerer `sf/src/lower.zig:6676`). Recursively walk the body:

- `AstKind.fn_call = 30` (`sf/src/ast.zig:32`): `child_0` is the callee
  expression (`ast.zig:388-394`; lowerer `lower.zig:3881`).
  - `child_0.kind == ident_expr`: `name_id = astStoreIdentifier(child_0)`;
    `sym = symbolRegistryQualifiedLookup(sym_reg, module_id, name_id)`; if
    `sym.kind == SymbolKind.function`, emit edge
    `(module_id,name_id) → (sym.module_id,sym.name_id)`.
  - `child_0.kind == field_access` (module-qualified `m.f()`): resolve the base
    ident as an import/module and the field name, mirroring `lower.zig:3197`.
  - Any other callee (local/param/fn-pointer) or unresolved: **no static edge.**
    This is sound only because Prelude B (`ERR_3017`) forbids materializing a
    suspending function as a value; see concern 4 below.
- `AstKind.builtin_call = 31` (`ast.zig:33`): `child_0` is the builtin name id
  (`ast.zig:388`). If it equals `@asyncSuspend`'s name id, seed
  `is_suspending[f] = 1`.

**Monotone worklist.** Let `F` be the finite set of function symbols. Build
parallel edge arrays `edge_caller[]`/`edge_callee[]`, a CSR reverse index
`rev_off[|F|+1]`/`rev_to[|E|]`, and a `u32` queue seeded with every function
whose body directly contains `@asyncSuspend`. Pop `g`, and for each reverse
edge `(c → g)` with `is_suspending[c] == 0`, set it to `1` and push `c`.
`is_suspending` is monotone non-decreasing and flips at most once per function,
so the loop performs ≤ `|F|` propagations; mutual recursion is ordinary
propagation (A→B→A), never recursive descent. `main`/`export fn` are ordinary
functions and may be suspending. Edges use absolute `(module_id,name_id)` so
propagation spans modules.

**Prelude B — `ERR_3017` at function-value materialization.** The error site is
where a function becomes a fn-pointer *value*, not the call site (umbrella L6,
§9). The three `func_ref` emission sites in `sf/src/lower.zig` are
`:2994-3005` (`lowerIdent` function branch, the primary choke point — `&func`
also lands here through `address_of`), `:3197-3204` (module-qualified
`module.function`), and `:3290-3299` (fn-typed struct member resolving to a
cross-module function). Refactor all three through one helper
`materializeFnRef(self, sym) u32` that first checks
`asyncIsSuspending(...)` and, when true, emits
`ERR_3017_SUSPENDING_FUNCTION_POINTER` and returns `TEMP_NONE` (no `func_ref`).
Direct calls to a suspending callee remain legal (implicit await).

**The five non-negotiable concerns (umbrella §6) land here or are explicitly
discharged:**

1. **`fn_ptr_struct_field` emission gap** (`repro/mi_matrix/fn_ptr_struct_field`
   emits the field as `void`). Stage 1 ignores dynamic calls; a suspending
   function can never reach a call graph through a struct field because
   `ERR_3017` rejects the materialization. The gap is therefore *not* a Stage 1
   blocker, but Track 3 must not store a `step` fn-ptr in a struct field until
   the gap closes. Recorded as an explicit assumption and a Track 3 constraint.
2. **Module-scope mutable globals** (`module_pub_var_int` runtime gap). The
   analysis is pure compiler state (side table); no runtime scheduler global is
   introduced. Track 3 must take a caller-supplied `Scheduler`/`Task`.
3. **Frame-size single source of truth.** Stage 1 writes `frame_sizes[key]` once
   and only once for each function; Stage 2 consumes the exact value and pads its
   synthesized frame to it; Stage 4 emits `@asyncFrameSize` from it. No other
   pass writes the table (see §4).
4. **Dynamic-call soundness.** Ignoring fn-pointer calls is sound only because
   `ERR_3017` forbids materializing a suspending function as a value. The ban is
   implemented in the same plan and gated by `async_fnptr_error_xmod`.
5. **Explicit numeric diagnostic codes.** Every new `ErrorCode` member is
   appended with `= NNNN` (never a bare auto-increment member), preserving ICE
   `3043` and `ERR_3048_CANNOT_READ_FILE = 3048` (`diagnostics.zig:70-72`).

**Discharge status (Task 4, ASYNCTRACK2).** Concern 1 (`fn_ptr_struct_field`)
remains a Track 3 constraint: the emission gap is still open, and Track 3 must not
store a `step` fn-ptr in a struct field. Concerns 2 (module-scope mutable globals)
and 4 (dynamic-call soundness) are discharged — the analysis is pure compiler state
(side table, no runtime scheduler global) and `ERR_3017` now forbids materializing a
suspending function as a value at all three `func_ref` sites (gated by
`async_fnptr_error_xmod`). The `@asyncFrameSize` argument is a compile-time function
query, not a value, so the ban is suppressed while lowering it (the `func_ref` edge
is still emitted for module liveness).

### 3.2 Stage 2 — frame layout on the LIR CFG

**Structures walked.** `LirFunction { name_id, module_id, return_type, params,
blocks, hoisted_temps, switch_cases, side_table, temp_variant_sub_field,
is_extern, is_pub, is_variadic, poison_uninit }` (`sf/src/lir.zig:494-513`);
`BasicBlock { id, insts, is_terminated }` (`lir.zig:280-284`);
`hoisted_temps: TempDeclArrayList` of `TempDecl { temp_id, type_id }`
(`lir.zig:17-20`) populated by `nextTemp` (`lower.zig:620-657`); `params` of
`LirParam { name_id, type_id, temp_id }` (`lir.zig:11-15`).

**Liveness** reuses the `lir_opt_pass` per-function scratch pattern
(`sf/src/lir_opt_pass.zig:163-187`): `maxTempOf` (`:257-265`),
`resetScratch` (`:268`), `markRead`/`markDef`/`markArgRead`/`markAddrTaken`
(`:291-361`), `scanAll` (`:646`). A temp is **live across a suspension point**
when it is defined before the suspension and first read at or after it
(`df_bb`/`df_ii` vs `rd_bb`/`rd_ii`). Cost is O(blocks × insts) per suspending
function from `ctx.alloc.scratch`, reset per function (`main.zig:722`) — no new
spill level.

**Frame record (Amendment 7, operator ruling).** Frames are **typed
function-local `__Z98Frame_<f>` structs, `*void` at the builtin/API boundary**,
with a **hidden step word in the frame header**. For each suspending function,
synthesize fields in this **frozen deterministic order**:

1. `step` — **the hidden step word, at offset 0 ALWAYS.** It is
   **pointer-sized** (architecture-dependent): 4 bytes on typical 32-bit, and a
   DOS real-mode far function pointer differs in semantics, so the spec/passes
   **MUST NOT hard-code 4 bytes**. On the 32-bit fixture target it is `*void`.
   Written by `@asyncInit` for the target `fn` (and by child-frame init for the
   callee); read by `@asyncResume` to select the body. **Child frames carry
   their own step word.** The synthesized `__async_step_*` symbol is never
   user-materializable (see §3.4, Prelude B).
2. `ctx: *Context` — pointer-sized, set by `@asyncInit`, read from the *current*
   frame at every child allocation (m1166).
3. `state: uN` — `u8` when `suspension_count <= 255`, else `u16`, else `u32`,
   where a suspension point is every explicit `@asyncSuspend` **plus** every
   implicit-await call to a suspending callee. Read by `@asyncResume` for the
   dispatch; range-checked under `-fsafe` (Amendment 7). **Landed (Fix F2):**
   P2 (`asyncFrameSizeRun`) computes the count and stores the chosen type in the
   `state_widths` side table (`key -> TYPE_U8|TYPE_U16|TYPE_U32`); P3, the
   `@asyncInit` lowering, and the Stage-3 transform all read that one source, so
   the frame field, its stores/loads, the `switch` dispatch, and the `-fsafe`
   range-check limit share the width. A function with more than `u32` suspension
   points is out of scope (the count is a `u32`).
4. Every `LirParam` in `params` order.
5. Every `hoisted_temps` entry live across ≥1 suspension point, in `temp_id`
   (declaration) order. Temps not live across any suspension stay ordinary C
   locals and are not in the frame.
6. `child: *void` — **hidden, pointer-sized, appended at the tail** after
   `live-across`, present iff `f` contains an implicit-await call to a suspending
   callee. Written by `f` at the await site (the allocated child-frame pointer);
   read by `f` on resume (`loop_done_blk`) and at `after_blk`. It is live across
   the await suspension but does **not** exist in the pre-transform LIR P3 sees,
   so P2/P3 reserve it explicitly rather than liveness discovering it. It is
   saved/reloaded with the other hidden fields at every yield.
7. `result: *void` — **hidden, pointer-sized, appended at the tail**, present iff
   `f` is the target of an implicit await. It points at **that await's** hidden
   `parent_result` slot (kind 7, Amendment 10) for a value-returning target, or is
   written `null` for a void target; the awaited callee's terminal step writes its
   `.ret` value through it. Written by the caller at the await site; read by the
   callee's terminal step.
8. `parent_result: T_k` — **hidden, value-typed, one slot per value-returning
   implicit await** (Amendment 10, I1), appended at the tail in **source (program)
   order** after the other hidden fields. Slot `k` is typed to the `k`-th
   value-returning implicit await's result type. A **void** await reserves no slot
   (residual R8: gated on value-return only). Each slot's writer is the awaited
   callee's terminal step, which stores its `.ret` value through the `result`
   pointer the caller placed for **that** await; the reader is the caller, which
   loads that slot (in `after_blk`) and assigns it to that await's `result`
   temp. All slots are saved/reloaded with the other hidden fields across each
   yield. This replaces the Amendment-9 single per-caller slot, which truncated a
   caller with multiple value-returning awaits of different types to the first
   await's type (review finding I1).

Offsets/size follow the single natural-layout path of
`type_resolver.zig:125-160` (`alignUp` + tail padding): `step`
(pointer-sized, pointer alignment), `ctx` (pointer-sized, align 4 on the 32-bit
fixture), `state`, then fields at natural alignment; the total is rounded up to
`max_align`. On the 32-bit fixture target (`*void` step + `*void` ctx + `u8`
state + two `i32` params) the layout is `step@0 s4 / ctx@4 s4 / state@8 s1 /
params@12..` → **size 20** (was 16 pre-step). A function with >255 suspension
points widens `state` to `u16` (or `u32` above 65535), shifting the fields that
follow by the extra bytes. Because the step word is
pointer-sized, the authoritative size is target-dependent. `@asyncFrameSize(fn)`
is this **flat** size and **excludes** child frames (m1166/m1172). The runtime
total is the sum of frame sizes along the active call chain.

The gated hidden await fields (kind 5 `child`, kind 6 `result`, kind 7
`parent_result`) are appended after `live-across` at natural alignment and shift a
frame's size only when their predicate holds. Kind 7 is **one slot per
value-returning implicit await** (Amendment 10), so only callers with more than one
value-returning await gain extra slots. The `async_frame_xmod` `worker`
(no await, never awaited) adds **no** hidden field under the gated variant; its
frame size is now dominated by the widened rule-(a) per-node reservation (see
below) rather than the header/param/live core. The unconditional variant (all
three hidden fields reserved for every suspending function) would add only those
pointer-sized slots on top.

**Authoritative size (concern 3, §15.1; rule (a) widened by Fix F1).**
`frame_sizes[key]` is written by the Stage 1 pre-lowering pass using a
conservative field set: **the hidden pointer-sized `step` word**, every param,
and **one field for every AST node reachable in the function body** — named
`var_decl` locals *and* the result of every expression/sub-expression — typed by
the node's own resolved type (`resolved_types`), walking the **whole** body with
**no early stop at the first suspension**. This upper-bounds P3's precise
live-across set: every temp P3 can mark live is the result of a sub-expression
evaluated before a suspension, and that node's resolved type is the value's type,
so the per-node reservation covers it. The walk must not stop at the first
suspension: a value defined after one suspension and read after a later one is
live across the later suspension. Stage 2 computes the precise live-across set
and the natural-layout `layout_size`; it requires `layout_size <=
frame_sizes[key]` and pads the emitted frame struct up to `frame_sizes[key]`.
`@asyncFrameSize` returns `frame_sizes[key]`. This guarantees a caller buffer can
never under-size the frame. A future precise-shrink refinement must move the
writer and both readers together; it is **not** part of v1. Adding the step word
moved the authoritative size for every frame; P2 (the sole writer), P3 (the
reader), and both pinned gates (Task-5a `Expected` and Task-5c `LAYOUT …`) moved
in the **same commit** (Amendment 7; "pinned value churn" is exactly what Task 5c
owns).

**`-s<N>` impact.** No new spill level. Async data is runtime/scratch and baked
into the synthesized frame/emitted C; `SPILL_COUNT = 5`
(`sf/src/spill_store.zig:16`), `spillSetLevel`, and `SpillId` are untouched.

### 3.3 Stage 3 — LIR-to-LIR state-machine transform

**Host.** Run `lf = asyncTransform(&lf, ...)` in `phase_LIRLowering` between
`lowerFn` (`main.zig:719`) and `lirStreamAppend` (`main.zig:720`), before
`lirSlotArrayListAppend`/scratch reset (`:721-722`). The streamed LIR is already
state-machined, so `lir_stream.zig` and the emitter need no format change. The
transform consults the Stage 1 `frame_sizes` table (module arena, live until
`main.zig:321`). Emitter-side post-lowering (the `lirOptRun` position,
`c89_emit.zig:~2648`) is rejected for v1: the frame struct must be known at C
declaration time and streamed bytes would need re-patching.

**Two-phase layout pass (Amendment 9; forward references).** `async_layouts` (a
per-`asyncKey` `AsyncFrameLayout` map on `CompilerContext`) must be **complete for
every suspending function before any `asyncTransform` runs**, because an await
reads the callee's param offsets and `result` offset and a caller may be declared
before its callee. Run **phase A** (`lowerFn` → `asyncLayoutFrame(&lf)` → publish
the layout into `ctx.async_layouts`; retain the lowered `lf`) for every suspending
function, then **phase B** (`asyncTransform(&lf)` for every suspending function,
reading `ctx.async_layouts`/`actx.layout`). A single inline pass that layouts and
transforms one function at a time cannot resolve a callee declared after its
caller; today's fixtures happen to be dependency-ordered, which is incidental. The
transform signals `main.zig` that it consumed `lf` (the step, and for the root
`main` the driver, are streamed by the transform) so `main.zig` skips appending
the original.

**Transform.**

- **Synthesize** the typed function-local `__Z98Frame_<f>` in the `TypeRegistry`
  with the Stage 2 fields (`step` first/offset 0, then `ctx`, `state`, params,
  live-across); access via existing `load_field`/`store_field` (`lir.zig:45-46`),
  resolved to C member names by the emitter's field logic. The name is registered
  through the string interner / `TypeRegistry` (backend-neutral; Amendment 4) and
  the emitter mangles it generically (`nameManglerMangle`, `c89_emit.zig:455`).
  The type is `*void` at the builtin/API boundary.
- **Rewrite** `f` into `__async_step_<f>(frame: *void, arg: ?*void) ?*void`
  (non-null result = still yielded, null = done) emitted under the mangled step
  name; the original name remains the `@asyncInit` entry. When the frame crosses
  the builtin/API boundary it is `*void`, but the body operates on the typed
  function-local frame.
- **Step symbol naming (Amendment 7, Res 7).** The synthesized step **symbol** is
  `__Z98Step_<fn>`; `__async_step_<f>` names the **same** synthesized step
  function. The two spellings are equivalent — `__async_step_<f>` is the
  design/source-level name and `__Z98Step_<fn>` is the emitted symbol; they name
  one function, not two (implementers MUST NOT diverge).
- **Step word (Amendment 7).** `@asyncInit(ctx, buf, fn, args)` zeroes the root
  frame in `buf`, stores `ctx`, sets `state = 0`, and **writes the step word for
  the target `fn`**; it returns `*void`. `@asyncResume(frame, arg)` **loads the
  step word from offset 0 and dispatches** through it; the locked
  `@asyncResume(frame, arg)` signature is retained (no step parameter). The step
  word is pointer-sized and **offset 0 always**; child frames carry their own.
- **State numbering:** state `0` = fresh entry; states `1..K` assigned in program
  order of suspension points (deterministic, monotonic with `createBlock` ids,
  `lower.zig:949-958`); terminal state `K+1`.
- **Entry:** `load_field` `state`; `switch_br { cond=state, cases_start/count,
  else_bb=terminate }` (`lir.zig:37`) dispatching to resume blocks. State `0`
  initializes params from `arg`/frame, then `jump` to the post-prologue block.
- **Suspend at point N:** `store_field` each live temp into the frame;
  `int_const next_state = N` (`lir.zig:74`); `store_field state = N`; `ret` a
  null pointer (yield). The resume case for N `load_field`-reloads the live temps
  and `jump`s to the instruction after the suspend.
- **Implicit await at a call to suspending `g` (atomic; Amendment 7; mechanics
  pinned by Amendment 9).** The call site is itself suspension point N in `f` and
  emits a **block-pair per await** (`yield_blk` + `loop_done_blk`), not a linear
  segment split. In the pre-await segment: read `ctx` from the **caller's** frame;
  allocate the child at the interim bump offset (below); write `g`'s step word at
  the child's offset 0; store the child header (`ctx`, `state = 0`); copy the call
  args into `g`'s param offsets; persist the child pointer in `f`'s hidden `child`
  field (kind 5); then issue the **first child step**
  `r = call(g_step, [child, null])`, `hv = check_optional(r)`, and
  `branch hv → yield_blk, after_blk`. The call-site rewrite is part of the same
  (atomic) Task 6 as the body rewrite — no interim where `f` has no synchronous
  target.
  - **`yield_blk`:** `store_field` every PARAM+LIVE field **plus the hidden
    `child` field**; `store_field state = N`; `ret` a non-null optional. This is
    the only state store at the await.
  - **`loop_done_blk` is ONLY the resume target (`resume_target[N]`), never a
    fallthrough:** `load_field`+assign every PARAM+LIVE field **plus `child`**;
    re-issue the child step (`r = call(g_step, [child, null])`,
    `hv = check_optional(r)`, `branch hv → yield_blk, after_blk`). It does **not**
    copy the awaited value (Amendment 10, M1): the terminal stores no state, so the
    copy must not live here.
  - **`after_blk` (M1):** the awaited value was written by the child's terminal
    step into **that await's** hidden `parent_result` slot (kind 7, Amendment 10)
    and is copied from that slot into the call's `result` temp **here in
    `after_blk`** — reached by both the first-step false branch and the
    resume-re-drive false branch. Then emit the remainder of the original block
    after the `call_direct`. Placing the copy in `after_blk` (not `loop_done_blk`)
    is what lets an immediately-completing child deliver its value.
  - **First-step false branch goes to `after_blk`, NOT `loop_done_blk`:** a child
    that completes on its very first step returns a null optional; routing it to
    `loop_done_blk` would re-enter the resume path, re-issue the child step, and —
    because the terminal block stores no state — restart the child at state 0 and
    re-run its body (double side effects).
  - **Interim child allocation (residual R1, pinned; full pool is Task 7):**
    `ctx[0..4] = used` (4-byte bump counter), pool base `ctx+4`; at an await bump
    `used` by `frame_sizes[g]` and allocate the child at the **pre-bump** offset
    (nested `main→f→g` share one `ctx`). **No capacity/`oom` check in Task 6**
    (Task 7 adds `capacity`/`oom` and the per-task LIFO pool); `ctx` stays the
    opaque `*void` the fixtures already pass. **SUPERSEDED by the landed Task-7 /
    Rule-A layout**: `{used@0, capacity@4, oom@8}` + 4 bytes padding, pool base
    `ctx+16` DERIVED (see §4).
- **Synthesized-step emitted edge (Res 7).** `@asyncInit` on a **cross-module**
  function emits, in the **caller's C89 module**, an **extern decl for
  `__Z98Step_<fn>`** (and for the frame struct tag if any C type is shared). In
  the **callee's module** the step function is emitted with **external linkage
  (not `static`)**. There is **no user-visible symbol** for the synthesized step;
  the emitted edge is **compiler-managed** (it also keeps the callee module alive
  for the emitter's reachability closure).
- **Terminal (Amendment 9).** `remapInst` must **not** map `.ret => ret_void`.
  For `.ret value` with `return_type != void`: `rp = load_field(frame, result_off,
  *void)` (the hidden `result` field, kind 6); if `rp != null`, `p =
  ptr_cast(rp, *T)` and `store p = value`; then terminate with `set_optional_null`
  then `ret` (null). If `rp` is null (root task) skip the store. The existing
  terminal block keeps its null-optional return, so only the value store is added.

**Pool semantics (m1172).** `buf` passed to `@asyncInit` is the root frame, is
**outside** the pool, and is caller-owned. The pool is for **child frames only**;
it is a **per-task LIFO frame stack**, implemented as a bump pointer plus a mark:
the call site reads `ctx` from the caller frame, allocates a child frame, pushes
by advancing the bump pointer, and pops by restoring the mark when the child
returns. LIFO is naturally enforced (child freed exactly when it returns) — no
free list, no fragmentation. Exhaustion returns `error.OutOfFrame` (not a
crash); pool size is the caller's choice. `ctx` is shared down a call chain
(every nested frame inherits the same `ctx` pointer from its parent).

**LIR op set (§15.3).** **0 mandatory new `LirInst` variants.** The machine uses
`switch_br`, `branch`/`jump`, `ret`, `call`/`call_direct`, `load_field`/
`store_field`, `load`/`store`, `int_const`, and pointer temps (`lir.zig:35-74`).
Optional 12-byte sugar may be appended **after `width_wrap`** (`lir.zig:167`) so
existing tag ordinals stay stable: `async_frame_size { name_id, module_id,
result }`, `async_save { frame, field_id, value }`, `async_load { frame,
field_id, result }`. Any payload ≤ 20 B with 4-byte alignment keeps the
Z98-folded `@sizeOf(LirInst) = 32`; payloads > 20 B go through `side_table`
precedent (`CallDirectData`/`TailCallData`, `lir.zig:170-198, 515-533`). The
`lir_stream` raw-byte contract (`lir_stream.zig:110, 201`) is untouched.

### 3.4 Stage 4 — builtin and diagnostic plumbing

**Sema** (`sf/src/semantic_analyzer.zig`): add four `*_name_id: u32` fields beside
the existing builtin ids (`:64-93`); intern them in `semanticAnalyzerInit`
(`:99-159`, after `csc_id`); add four allow-list lines in
`semanticAnalyzerIsBuiltinSupported` (`:257-298`); add typing arms in the
`builtin_call` dispatch (`:2087-2219`, before the `ec.len >= 2` fallthrough at
`:2180`):

| Builtin | Sema result type | Argument typing |
|---|---|---|
| `@asyncFrameSize(fn)` | `TYPE_INT_LIT` | one function reference; must be a known suspending function else `ERR_3046` |
| `@asyncInit(ctx, buf, fn, args)` | `TYPE_PTR_VOID` (`*void`) | `ctx` pointer, `buf` `[*]u8`/`*void` pointer, `fn` function reference, `args` `?*const void` |
| `@asyncResume(frame, arg)` | optional pointer (`?*void`) | `frame` `*void`, `arg` `?*void` |
| `@asyncSuspend(data)` | `TYPE_PTR_VOID` (`*void`) | `data` `?*void` |

Error-site rules in sema (Amendment 7, Res 3; **[updated: 2026-09-15 — Fix F3]**
landed): **only `@asyncSuspend` is `ERR_3018`-gated.** An `@asyncSuspend`
lexically outside a suspending function →
`ERR_3018_ASYNC_SUSPEND_OUTSIDE_SUSPENDING = 3018`, resolved via the Stage 1
table on the enclosing `fn_decl` symbol: `semanticAnalyzerResolveFnBody` records
the enclosing function's `name_id` in `current_fn_name`, and the check consults
`asyncIsSuspending(suspending_fns, module_id, current_fn_name)`, emitting only
when the enclosing function is **not** suspending. The `async_analysis_ready`
gate is now **`true`** (Stage 1 runs before sema), so the check is live and
**reachable** (a module-scope `@asyncSuspend` — no enclosing function,
`current_fn_name == 0` — reports exactly one `error[3018]`). It cannot
false-positive on a legitimate body: Stage 1 self-seeds any function whose body
directly contains `@asyncSuspend`, so a function the sema walk sees with a
suspend is by construction already in `suspending_fns`. **`@asyncInit`/
`@asyncResume` operate on opaque `*void` frames, do not require the
suspension-detection pass, and are legal outside a suspending function (e.g. in
`main`); they must not call the `3018` helper.** Any `@asyncSuspend` /
`@asyncInit` / `@asyncResume` inside a `defer`/`errdefer` body →
`ERR_3019_ASYNC_BUILTIN_IN_DEFER = 3019`, tracked by a `defer_depth` counter
mirroring `switch_depth`: the sema statement walk increments `defer_depth`
around the recursive resolution of a `defer`/`errdefer` body, and each of the
three builtin arms emits exactly one `3019` at that builtin's span when
`defer_depth > 0` (`@asyncFrameSize` is a compile-time query and is not
`3019`-gated). Reviving the dead `ERR_4002_DEFER_IN_INVALID_SCOPE`
(`diagnostics.zig:53`) was the sanctioned alternative for `3019`; v1 uses `3019`
and leaves `ERR_4002` for the separate general defer hardening item.
`@asyncFrameSize` on a non-suspending/unknown function →
`ERR_3046_ASYNC_FRAME_SIZE_INVALID = 3046`.

**Prelude B at the builtins (Amendment 7).** `@asyncInit`'s `fn` argument and the
frame step word are **compiler-generated/compile-time queries** (the same class as
`@asyncFrameSize`), so they produce **no `ERR_3017`**: the `suppress_fnref_ban`
window applies while lowering `@asyncInit`'s `fn` (and the `func_ref`/step edge is
still emitted for module liveness). A synthesized `__async_step_<f>` is
**not user-materializable** — taking its address as an ordinary value is not
expressible in the language surface.

**Argument contract (pinned for Track 3).** `args` is a caller-declared struct
whose fields correspond in order and type to the target's parameters;
`@asyncInit` copies them into the frame's param slots at entry. A zero-parameter
target passes a null `args` pointer; sema accepts `null` for `args`. `result` is
delivered by the target writing through a pointer supplied in its own parameters
(L3), not by the runtime.

**Lowering** (`sf/src/lower.zig:3911`, chained before the `exit` arm at
`:4087-4094`): add four `async_*_name_id` fields to `LirLowerer` (`:356-426`) and
intern them in `lowererInit` (`:428-568`), then four dispatch arms:

- `@asyncFrameSize(fn)` → `int_const { value = frame_sizes[target] }` from the
  pre-lowering table (§15.1) — a runtime-materialized ordinary integer, never a
  comptime constant (the early AST `comptime` pass runs before sema/lowering,
  `main.zig:302`, and cannot see final layout).
- `@asyncInit` → allocate/zero the root frame in the caller `buf`, store `ctx`,
  set `state = 0`, **write the step word for the target `fn`**, and return the
  frame pointer (`*void`). For a cross-module target, emit the Res-7 extern
  step decl/edge in the caller's module.
- `@asyncResume` → the state-machine drive (Stage 3): **load the step word from
  offset 0 and dispatch**, returning non-null while yielded. The result is the
  **optional pointer `?*void`** (`null` = terminal, non-null = suspended).
- `@asyncSuspend` → the suspend transition of the enclosing function (Stage 3),
  returning the yielded value.

**Res 5 (Task-6 code fix, not a spec change).** The `?*void` result typing above
is **correct**. The lowering arm that currently emits/types a plain `*void`
placeholder is **wrong** and must be fixed to emit/type `?*void` as part of
Task 6 (recorded as a Task-6 work item, not a diagnostic or spec gap).

**Res 6 (`@ptrCast` arity).** The 1-argument `@ptrCast(expr)` form is silently
accepted and mis-lowered today; it must be **rejected with a new diagnostic**
(a compiler change, not a documentation-only fix). The explicit code is
`ERR_3049_PTRCAST_REQUIRES_TWO_ARGS = 3049` (next free value after `3048`);
the Task-6 fixtures use the 2-arg form `@ptrCast(T, expr)`.

Buffer-too-small / null frame: `-fsafe` traps, `-ffast` is UB (documented).
Pool exhaustion at a suspension point → `error.OutOfFrame`, not a crash.
**Amendment 7 `-fsafe` trap (the only new trap):** a **null step word** loaded by
`@asyncResume` and an out-of-range `state` are trapped, gated exactly like the
existing `check_trap`s (`lower.zig` numeric traps); `-ffast` leaves this UB.

## 4. Interfaces

**Side tables (`CompilerContext`).**
```zig
suspending_fns: hash_mod.U64ToU32Map, // key=(module_id<<32)|name_id; 0/1
frame_sizes:    hash_mod.U64ToU32Map, // key=(module_id<<32)|name_id; flat bytes
state_widths:   hash_mod.U64ToU32Map, // key=(module_id<<32)|name_id; TYPE_U8/U16/U32
```

**Analysis module (`sf/src/async_analysis.zig`, new).**
```zig
pub fn asyncKey(module_id: u32, name_id: u32) u64;
pub fn asyncIsSuspending(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) bool;
pub fn asyncFrameSizeOf(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) ?u32;
// Fix F2: P2 (asyncFrameSizeRun) is the sole writer of `state_widths`; consumers
// read the chosen type with `u64ToU32MapGet(state_widths, asyncKey(m, n))`.
pub fn suspensionAnalysisRun(ctx: *CompilerContext) void; // pass body
```

**Frame/reference types (`sf/src/async_frame_layout.zig`, landed).**
```zig
pub const AsyncFrameField = struct {
    kind: u8, name_id: u32, temp_id: u32, type_id: u32, offset: u32, size: u32, alignment: u32,
};
// kind: 0=ctx, 1=state, 2=param, 3=live temp, 4=step (hidden; offset 0 ALWAYS,
//       pointer-sized type_id per Amendment 7 — do NOT hard-code 4 bytes),
//       5=child (hidden pointer; tail; iff f has an implicit await),
//       6=result (hidden pointer; tail; iff f is awaited; targets that await's
//       parent_result slot, or null),
//       7=parent_result (hidden value-typed; tail; ONE slot per value-returning
//       implicit await, in source order, each typed to that await's result;
//       saved/reloaded across yields — residual R8 gates it on value-return
//       only, so a void await reserves no slot; Amendment 10 replaces the
//       Amendment-9 single per-caller slot)
pub const AsyncFrameLayout = struct {
    fields: AsyncFrameFieldArrayList,
    layout_size: u32,      // == frame_sizes[key]; padded authoritative size
};
pub fn asyncLayoutFrame(alloc: *alloc_mod.Sand, reg: *type_mod.TypeRegistry,
    lir_fn: *lir_mod.LirFunction, suspending_fns: *hash_mod.U64ToU32Map,
    frame_sizes: *hash_mod.U64ToU32Map, state_widths: *hash_mod.U64ToU32Map,
    awaited_fns: *hash_mod.U64ToU32Map, async_hidden_fns: *hash_mod.U64ToU32Map,
    parent_result_type_list: *ga_mod.U32ArrayList,
    parent_result_start: *hash_mod.U64ToU32Map,
    parent_result_count: *hash_mod.U64ToU32Map) AsyncFrameLayout;
pub fn asyncTransform(lf: *lir_mod.LirFunction, ctx: *AsyncTransformCtx) void;
```

**Synthesized symbols.**
```zig
// frame struct type, mangled through nameManglerMangle:
__async_frame_<fn>
// step function, emitted under the mangled name; original name = @asyncInit entry:
fn __async_step_<fn>(frame: *void, arg: ?*void) ?*void
```

**Builtin surface (pinned; Track 3 consumes).**
```zig
@asyncFrameSize(fn) u32
@asyncInit(ctx: *Context, buf: [*]u8, fn, args: ?*const void) *void
@asyncResume(frame: *void, arg: ?*void) ?*void
@asyncSuspend(data: ?*void) *void
```
`Context` is **not** heap-allocated and has **no fixed array inside the struct,
no generics**: under the Res-1 (Amendment 7) resolution, **ownership is INLINE** —
`ctx` owns a **slice to the caller-provided pool**, is stored in every frame as a
pointer-sized handle, and is inherited unchanged down a call chain. The compiler
emits **inline** pool-field reads at those offsets (bump + mark) rather than
calling runtime helpers.

**Context header (cross-track ABI, Rule A — canonical 16-byte layout):**

```
used      @ ctx+0    (usize)
capacity  @ ctx+4    (usize)
oom       @ ctx+8    (u8, sticky)
padding   @ ctx+9..15 (4 bytes; reserved)
pool_base = ctx+16   (DERIVED — never stored)
```

The header is **16 bytes** (not 12) so `pool_base = ctx+16` is 8-aligned whenever
`ctx` is 8-aligned; the compiler core's `CTX_POOL_OFF` is **16**
(`sf/src/async_state_machine.zig`), matching `std.async`'s `HEADER_SIZE = 16`.
The caller's buffer MUST be 8-aligned (a bare `[N]u8` array is only 1-aligned;
back it with a `u64` array cast to `[]u8`). Every `frame_sizes[key]` is padded to
a multiple of **8** so consecutive child frames stay 8-aligned. Pinned caller
idiom:

```zig
var pool: [512]u64 = undefined;
var ctx = std.async.contextInit(@ptrCast([*]u8, &pool)[0..4096]);
```

The frame **step word** (offset 0) is pointer-sized; its type is the target's
pointer type on that architecture (never a hard-coded 4-byte integer).
`@asyncResume(frame, arg)` returns `?*void` (`null` = terminal, non-null =
suspended); the synthesized `__async_step_<f>` is compiler-managed and not
user-materializable.

**On-disk contract.** `buf` is the root frame, caller-owned, outside the pool.
`frame_sizes[key]` is the per-function flat size excluding child frames. A child
frame is allocated from the current frame's `ctx` at a suspending call site and
released when the child `_step` returns null.

## 5. Diagnostics (explicit numeric codes)

All new members are appended to `ErrorCode` (`sf/src/diagnostics.zig:10-81`) with
an explicit `= NNNN`; never a bare member. `ErrorCode` is an auto-incrementing
`enum(u16)`. Landing status (Amendment 7; **[updated: 2026-09-15 — Fix F3]**):
`ERR_3017 = 3017` (Track 1), `3018` and `3019` are **landed** (Fix F3: the
`3018` gate is live and the `3019` defer ban emits), `ERR_3046 = 3046` is
**assigned**, `WARN_3047 = 3047` optional, and
`ERR_3048_CANNOT_READ_FILE = 3048` is preserved. The **next free value is
`3049`**, claimed by the Res-6 1-arg `@ptrCast` diagnostic (below). This subspec
owns `3017/3018/3019/3046/3049` (and optionally `3047`); Track 1 owns `3045`.

| Code | Name | Site |
|---|---|---|
| `ERR_3017_SUSPENDING_FUNCTION_POINTER = 3017` | Prelude B ban | `lower.zig:2994-3005, 3197, 3290` (function-value materialization) |
| `ERR_3018_ASYNC_SUSPEND_OUTSIDE_SUSPENDING = 3018` | **`@asyncSuspend` only** outside a suspending function (Res 3) | sema `builtin_call` `@asyncSuspend` arm, gated on `asyncIsSuspending(suspending_fns, module_id, current_fn_name)` |
| `ERR_3019_ASYNC_BUILTIN_IN_DEFER = 3019` | `@asyncSuspend`/`@asyncInit`/`@asyncResume` inside `defer`/`errdefer` | sema `defer_depth > 0` at each of the three builtin arms |
| `ERR_3045_UNKNOWN_CALLING_CONVENTION = 3045` | *(Track 1; reserved here)* | Track 1 |
| `ERR_3046_ASYNC_FRAME_SIZE_INVALID = 3046` | `@asyncFrameSize` on non-suspending/unknown fn | sema `@asyncFrameSize` arm |
| `WARN_3047_ASYNC_FRAME_LARGE = 3047` | *(optional advisory)* | Stage 2 layout, threshold-gated |
| `ERR_3049_PTRCAST_REQUIRES_TWO_ARGS = 3049` | **Res 6:** 1-arg `@ptrCast(expr)` rejected | sema `@ptrCast` arm (sema builtin/type-cast dispatch) — the emitter of `ERR_3049`; `3049` is confirmed free/explicit |

`ERR_3048_CANNOT_READ_FILE = 3048` and every existing explicit value are
preserved; ICE `3043` (`ERR_9001_ICE`, auto-incremented) must not shift.

## 6. Testing

- **Stage 1:** `repro/mi_matrix/async_callgraph_xmod` — cross-module direct
  calls plus a mutual-recursion pair with no explicit suspend; `@asyncFrameSize`
  returns a nonzero value for each (proving propagation) and errors `3046` on a
  plain function. `repro/mi_matrix/async_fnptr_error_xmod` — `&yielder` produces
  exactly one `error[3017]` and zero `.c` files.
- **Stage 2:** `repro/mi_matrix/async_frame_xmod` — self-verifying:
  `@asyncFrameSize(worker) == 68` under the widened rule (a) (Fix F1): the
  authoritative size is the header (hidden pointer-sized `step` + `ctx` +
  `state`) + param `x` + one 4-byte slot per body AST node. Before Fix F1 the
  reservation covered only `var_decl` locals, so `worker` was **20**; the per-node
  rule now dominates and `worker` is **68**. `repro/mi_matrix/async_frame_temps_xmod`
  is the Fix F1 regression: `foo(a) + foo(a) + foo(a) + bar(1)` (bar suspends)
  leaves three call-result temps live across the suspension; RED pre-fix
  `--dump-c89` rc=133 (`panic: async frame layout exceeds authoritative frame
  size`, 0 `.c`), GREEN post-fix rc=0 / 4 `.c` / gcc clean / link / run rc=0 with
  the `46` arithmetic self-check. **Hidden-field pinning (Amendments 9/10):** under
  the **gated** variant (`child`/`result`/`parent_result` reserved only where
  their predicates hold) `worker` has no await and is never awaited, so the hidden
  fields add nothing; under the **unconditional** variant all three add their
  pointer-sized slots. **Amendment 10 pinned values:** per-await kind-7 slots
  change only callers with **more than one** value-returning implicit await;
  `async_await_multi_xmod`'s `caller` pins **208** under the widened rule (was 64
  pre-Fix-F1, still well under its 1024-byte pool).
- **State width (Fix F2):** `repro/mi_matrix/async_state_width_xmod` — one
  suspending function with **300** sequential `@asyncSuspend(null)` points, so
  `state` is `u16`. RED pre-fix (u8 hard-coded): the emitted `switch` has case
  labels beyond the `u8` condition (`gcc -Wswitch-outside-range`), the `-fsafe`
  range-check limit `total_states == 300` truncates to `44` (run traps, rc=133),
  and under `-ffast` state 256 truncates to 0 so the resume loop never terminates
  (`timeout` rc=124). GREEN: rc=0 / 4 `.c` / gcc clean / link / run rc=0 with the
  `out.* == 300` self-check; the emitted state field is `unsigned short`.
- **Stage 3:** `repro/mi_matrix/async_await_xmod` — a root frame in a caller
  `buf`, an implicit await of a child, deterministic stdout across 3 runs and
  identical md5; plus a `-fsafe` pool-exhaustion probe that returns
  `error.OutOfFrame` (no crash). `@asyncInit`/`@asyncResume` may appear in the
  **non-suspending `main`** driver (Res 3): only `@asyncSuspend` is
  `ERR_3018`-gated.
- **Stage 4 (Fix F3 landed 2026-09-15):** `repro/mi_matrix/async_defer_error_xmod`
  — a suspending `worker` with `@asyncSuspend(null)` inside a `defer` block; RED
  pre-fix (dump rc=0, 0×`error[3019]`), GREEN post-fix (rc=2, exactly one
  `error[3019]`, 0 `.c`). The `ERR_3018` check is now live and **reachable**: a
  module-scope `@asyncSuspend` (no enclosing function, `current_fn_name == 0`)
  reports exactly one `error[3018]`; it does not fire on the existing async
  bodies because Stage 1 self-seeds their functions. `async_builtin_scope_xmod`
  is a positive/typing guard (rc=0, 4 `.c`): its `@asyncSuspend` is inside the
  suspending `plain_caller`, so neither `3018` nor `3019` fires.
  `async_framesize_invalid_xmod` keeps `error[3046]`; the positive typing cases
  compile.
- **Gate battery (every task):** build via the seed model
  (`scripts/seed/build_from_seed.sh`) or `bash sf/scripts/build_release.sh`;
  compile/run affected fixtures under `timeout 120`; run the corpus classifier
  from `docs/sf/QUICK_REF.md:134-145` by gcc exit code; keep the 4-MD5 gates and
  the 21-example matrix green. No classifier counts by empty stderr.
- **Closeout:** N-hop fixed-point closure; record the new fixed point md5; rotate
  the seed only at closeout via
  `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`.

## 7. Risks

- **Ordering of frame size vs lowering.** The pre-lowering size table is
  conservative; the emitted frame is padded to it. Mitigation: the explicit
  single-source rule in §3.2 and a Stage 2 assertion `layout_size <=
  frame_sizes[key]`.
- **`fn_ptr_struct_field` emission gap** (concern 1) blocks any `step` fn-ptr
  struct field; Stage 1 does not need it, but Track 3 must avoid it until fixed.
- **Synthetic struct type emission.** If emitting `__async_frame_<f>` proves
  difficult, fall back to an opaque `[N]u8` frame plus `load`/`store`
  (`lir.zig:48-49`) at the same natural offsets; the op-fit and stream contract
  are unaffected.
- **Cross-module/mutual-recursion propagation.** The worklist must not reuse a
  topological sort (which would drop SCCs); the RED fixture pins this.
- **Stream/byte stability.** Optional ops must be appended after `width_wrap`
  and stay ≤ 20 B; otherwise use `side_table`.
- **Track 1 enum coordination.** Both tracks append explicit codes; values never
  shift, so order of landing is immaterial.

## 8. Dependencies

**Consumes.**
- Umbrella §5 L1–L9, §6 concerns, §12 Stages 1–4, §15 resolutions, §14.2.
- Spike evidence and operator rulings m1166/m1172
  (`.superpowers/sdd/task-ASYNCPRELUDE-report.md`).
- Track 1 (`win9x-calling-convention-design.md`): only the shared diagnostic band
  and the explicit-`= NNNN` rule. Async `_step` functions use the default Z98
  cdecl convention; no calling-convention surface is consumed.
- Existing compiler surfaces: LIR CFG (`lir.zig:280-284, 494-513`), type layout
  (`type_resolver.zig:125-160`), `lir_opt_pass` scratch pattern
  (`lir_opt_pass.zig:163-361`), sema builtin registry
  (`semantic_analyzer.zig:64-93, 99-159, 257-298, 2087-2219`), lowering dispatch
  (`lower.zig:3911`), stream folding (`lir_stream.zig:110`).

**Produces.**
- The concrete runtime/builtin surface Track 3 (`std-async-design.md`) consumes:
  the four builtins and their pinned signatures; the frame field order and
  `@asyncFrameSize` flat-size semantics; `ctx`-in-frame inheritance; the
  per-task LIFO child-frame allocation contract and `error.OutOfFrame`; the
  `__async_step_<f>` ABI; and the `ERR_3017/3018/3019/3046` diagnostics.
- The suspension-analysis pass and `suspending_fns`/`frame_sizes` side tables.
- New corpus fixtures (`async_*_xmod`) and a moved compiler fixed point + rotated
  seed at closeout.

---

## 9. Closeout record (2026-09-15)

**Status: COMPLETE** (spec status stays "draft, amendable in place"). Full gate
evidence in `.superpowers/sdd/task-ASYNCTRACK2-report.md` `## Task 8 (re-run 2)`.

- **Fixed point:** `f5ee84800dd32d7c440bb383c10edb55` (the `-ffast` binary;
  two-hop closure `hop1 == hop2` from the committed seed v15
  `eda943dc1f77a48eae039e39ea4bfe04`).
- **Seed rotated v15 → v16:** archive md5 `e04b4063c554c90a51c34f6736fc1346`,
  internal `zig1` md5 `f5ee8480…`, `gen/` 45 `.c` + 46 `.h` (8,355,500 B), `lib/`
  8 std `.zig`; post-rotation closure `hop1 == hop2 == f5ee8480…`;
  `check_emit_support.sh` 5/5.
- **Diagnostics landed:** `ERR_3017 = 3017` (Track 1); **`ERR_3018 = 3018` and
  `ERR_3019 = 3019` are LANDED** (Fix F3: the `3018` gate is live on
  `suspending_fns` and the `3019` defer ban emits); `ERR_3046 = 3046`,
  `WARN_3047 = 3047`, `ERR_3049 = 3049` (Task 6b); the `@asyncFrameSize` /
  `@asyncInit` / `@asyncResume` / `@asyncSuspend` builtins; P2 `asyncFrameSizeRun`
  (sole `frame_sizes` writer), P3 `async_frame_layout`, and the
  `async_state_machine` LIR-to-LIR transform; per-task LIFO child frames +
  `error.OutOfFrame`.
- **Final-review fix wave F1–F4** (`7d81effc`, `3181b6a8`, `7f1a2288`,
  `06c3e195`): P2 reserves every body AST node's resolved type (F1,
  `async_frame_temps_xmod` CRASH→OK), suspension-count state width u8/u16/u32
  (F2, `async_state_width_xmod`, runtime-only), the `3018`/`3019` gates (F3,
  `async_defer_error_xmod` OK→GREEN), and the shared frame-offset helpers +
  `@asyncResume` arg pass-through (F4, `async_resume_arg_xmod`, runtime-only).
- **Regression I/F series Tasks 9/10:** kind-aware `nodeChildIsNode` /
  `nodeHasNodeExtraChildren` (`sf/src/ast.zig`) applied to all generic walkers
  (fixes the `repro/tu_void_prong` OOM), plus the `analyzer.zig` for-loop-body
  descent (`child_1`).
- **Corpus `-s0` 603 dirs = 563 OK / 37 GREEN / 3 emission-inspection FAIL**,
  `-ffast` == `-fsafe` zero-asymmetric; vs the v81 manifest (602 = 562/37/3) the
  only change is the new F4 fixture `async_resume_arg_xmod` (OK).
- **4-MD5 gates unchanged** (all eight rows byte-identical to v79/v81).
- `repro/mi_matrix/EXPECTED_FAIL.md` bumped **v81 → v82**.

Track 3 (`std.async`) consumes the produced surface; the Track-3/4 plan
re-amendment (drop `Task.step` and every `step` parameter) remains the recorded
pre-dispatch deferral (Amendment 7).
