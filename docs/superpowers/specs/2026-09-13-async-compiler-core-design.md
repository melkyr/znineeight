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

**Frame record.** For each suspending function, synthesize fields in this
deterministic order:

1. `ctx: *Context` — pointer-sized, set by `@asyncInit`, read from the *current*
   frame at every child allocation (m1166).
2. `state: uN` — `u8` when `suspension_count <= 255`, else `u16`, else `u32`,
   where a suspension point is every explicit `@asyncSuspend` **plus** every
   implicit-await call to a suspending callee.
3. Every `LirParam` in `params` order.
4. Every `hoisted_temps` entry live across ≥1 suspension point, in `temp_id`
   (declaration) order. Temps not live across any suspension stay ordinary C
   locals and are not in the frame.

Offsets/size follow the single natural-layout path of
`type_resolver.zig:125-160` (`alignUp` + tail padding): `ctx` (4 B, align 4),
`state`, then fields at natural alignment; the total is rounded up to
`max_align`. `@asyncFrameSize(fn)` is this **flat** size and **excludes** child
frames (m1166/m1172). The runtime total is the sum of frame sizes along the
active call chain.

**Authoritative size (concern 3, §15.1).** `frame_sizes[key]` is written by the
Stage 1 pre-lowering pass using the *candidate* field set (every param plus every
body local/temp that can be live across a suspension), i.e. a conservative upper
bound. Stage 2 computes the precise live-across set and the natural-layout
`layout_size`; it requires `layout_size <= frame_sizes[key]` and pads the emitted
frame struct up to `frame_sizes[key]`. `@asyncFrameSize` returns
`frame_sizes[key]`. This guarantees a caller buffer can never under-size the
frame. A future precise-shrink refinement must move the writer and both readers
together; it is **not** part of v1.

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

**Transform.**

- **Synthesize** `__async_frame_<f>` in the `TypeRegistry` with the Stage 2
  fields; access via existing `load_field`/`store_field` (`lir.zig:45-46`),
  resolved to C member names by the emitter's field logic. The name is mangled
  through `nameManglerMangle` (`c89_emit.zig:455`).
- **Rewrite** `f` into `__async_step_<f>(frame: *void, arg: *void) ?*void`
  (non-null result = still yielded, null = done) emitted under the mangled step
  name; the original name remains the `@asyncInit` entry.
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
- **Implicit await at a call to suspending `g`:** the call site reads `ctx` from
  the **caller's** frame, allocates and initializes a child frame from the
  per-task frame stack, and drives `g`'s `_step` in a loop, updating the caller's
  live state; the call is itself suspension point N in `f`.
- **Terminal:** store the result through the caller-provided `*void` slot (L3)
  and `ret` null.

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

Error-site rules in sema: any `@async*` lexically outside a suspending function
→ `ERR_3018_ASYNC_SUSPEND_OUTSIDE_SUSPENDING = 3018` (resolved via the Stage 1
table on the enclosing `fn_decl` symbol); any `@async*` inside `defer`/`errdefer`
→ `ERR_3019_ASYNC_BUILTIN_IN_DEFER = 3019`, tracked by a new `defer_depth` counter
mirroring `switch_depth` (`semantic_analyzer.zig:46, 181, 1818`). Reviving the
dead `ERR_4002_DEFER_IN_INVALID_SCOPE` (`diagnostics.zig:53`) is the sanctioned
alternative for `3019`; v1 uses `3019` and leaves `ERR_4002` for the separate
general defer hardening item. `@asyncFrameSize` on a non-suspending/unknown
function → `ERR_3046_ASYNC_FRAME_SIZE_INVALID = 3046`.

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
  set `state = 0`, and return the frame pointer.
- `@asyncResume` → the state-machine drive (Stage 3), returning non-null while
  yielded.
- `@asyncSuspend` → the suspend transition of the enclosing function (Stage 3),
  returning the yielded value.

Buffer-too-small / null frame: `-fsafe` traps, `-ffast` is UB (documented).
Pool exhaustion at a suspension point → `error.OutOfFrame`, not a crash.

## 4. Interfaces

**Side tables (`CompilerContext`).**
```zig
suspending_fns: hash_mod.U64ToU32Map, // key=(module_id<<32)|name_id; 0/1
frame_sizes:    hash_mod.U64ToU32Map, // key=(module_id<<32)|name_id; flat bytes
```

**Analysis module (`sf/src/async_analysis.zig`, new).**
```zig
pub fn asyncKey(module_id: u32, name_id: u32) u64;
pub fn asyncIsSuspending(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) bool;
pub fn asyncFrameSizeOf(map: *hash_mod.U64ToU32Map, module_id: u32, name_id: u32) ?u32;
pub fn suspensionAnalysisRun(ctx: *CompilerContext) void; // pass body
```

**Frame/reference types (`sf/src/async_lowering.zig`, new).**
```zig
pub const AsyncFrameField = struct { name_id: u32, type_id: u32, offset: u32, kind: u8 };
// kind: 0=ctx, 1=state, 2=param, 3=live temp
pub const AsyncFrameLayout = struct {
    frame_size: u32,       // == frame_sizes[key]; authoritative
    layout_size: u32,      // natural-layout size, <= frame_size
    state_width: u8,       // 8/16/32
    suspension_count: u32,
    field_count: u32,
};
pub fn asyncLayoutFrame(lf: *lir_mod.LirFunction, reg: *type_mod.TypeRegistry,
    scratch: *alloc_mod.Sand, frame_size: u32) AsyncFrameLayout;
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
`Context` is opaque to the compiler core: `ctx` is a pointer-sized handle stored
in every frame and inherited unchanged down a call chain. Track 3 defines
`Context`'s pool shape (per-task LIFO frame stack, bump + mark) and its size.

**On-disk contract.** `buf` is the root frame, caller-owned, outside the pool.
`frame_sizes[key]` is the per-function flat size excluding child frames. A child
frame is allocated from the current frame's `ctx` at a suspending call site and
released when the child `_step` returns null.

## 5. Diagnostics (explicit numeric codes)

All new members are appended to `ErrorCode` (`sf/src/diagnostics.zig:10-73`) with
an explicit `= NNNN`; never a bare member. `ErrorCode` is an auto-incrementing
`enum(u16)`: `3017-3019` are free (after `ERR_3016_ORELSE_REQUIRES_OPTIONAL =
3016`, before `ERR_3020_UNHANDLED_NODE_KIND = 3020`) and `3045-3047` are free
(before `ERR_3048_CANNOT_READ_FILE = 3048`). This subspec owns `3017/3018/3019/
3046` (and optionally `3047`); Track 1 owns `3045`.

| Code | Name | Site |
|---|---|---|
| `ERR_3017_SUSPENDING_FUNCTION_POINTER = 3017` | Prelude B ban | `lower.zig:2994-3005, 3197, 3290` (function-value materialization) |
| `ERR_3018_ASYNC_SUSPEND_OUTSIDE_SUSPENDING = 3018` | async builtin outside a suspending function | sema `builtin_call` dispatch |
| `ERR_3019_ASYNC_BUILTIN_IN_DEFER = 3019` | async builtin inside `defer`/`errdefer` | sema `defer_depth` check |
| `ERR_3045_UNKNOWN_CALLING_CONVENTION = 3045` | *(Track 1; reserved here)* | Track 1 |
| `ERR_3046_ASYNC_FRAME_SIZE_INVALID = 3046` | `@asyncFrameSize` on non-suspending/unknown fn | sema `@asyncFrameSize` arm |
| `WARN_3047_ASYNC_FRAME_LARGE = 3047` | *(optional advisory)* | Stage 2 layout, threshold-gated |

`ERR_3048_CANNOT_READ_FILE = 3048` and every existing explicit value are
preserved; ICE `3043` (`ERR_9001_ICE`, auto-incremented) must not shift.

## 6. Testing

- **Stage 1:** `repro/mi_matrix/async_callgraph_xmod` — cross-module direct
  calls plus a mutual-recursion pair with no explicit suspend; `@asyncFrameSize`
  returns a nonzero value for each (proving propagation) and errors `3046` on a
  plain function. `repro/mi_matrix/async_fnptr_error_xmod` — `&yielder` produces
  exactly one `error[3017]` and zero `.c` files.
- **Stage 2:** `repro/mi_matrix/async_frame_xmod` — self-verifying:
  `@asyncFrameSize(f) == @sizeOf(Frame)` for a fixture struct that mirrors the
  specified field order; a second function with extra non-live temps still
  reports the same frame size.
- **Stage 3:** `repro/mi_matrix/async_await_xmod` — a root frame in a caller
  `buf`, an implicit await of a child, deterministic stdout across 3 runs and
  identical md5; plus a `-fsafe` pool-exhaustion probe that returns
  `error.OutOfFrame` (no crash).
- **Stage 4:** `repro/mi_matrix/async_builtin_scope_xmod` — `error[3018]`,
  `error[3019]`, and `error[3046]` cases; the positive typing case compiles.
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
