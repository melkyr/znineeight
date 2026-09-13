# Z98 std.async Library (Track 3) — Design

**Date:** 2026-09-13
**Branch:** `zig1_improvements`
**Baseline HEAD:** `f755dbed`; compiler fixed point `1467d932a876402f40a56316dfcad0e5`;
seed v10 (`ca18fc9f9af55d58147fcb7ff7a662b6`); corpus 570 = 541 OK / 29 GREEN / 0 FAIL;
`EXPECTED_FAIL.md` v77. (Track 3 does not modify the compiler import graph, so it
does not move the fixed point. If it lands after Track 2, record Track 2's
closeout fixed point at plan Task 1 and use that value throughout.)

**Parent spec:** [`2026-09-13-async-prelude-and-feasibility-design.md`](./2026-09-13-async-prelude-and-feasibility-design.md).
**Derives from:** umbrella §12.5 (Stage 5 `std.async`), §6 (the five non-negotiable
concerns), §15.2 + operator rulings m1166/m1172 (frame ownership and Context-pool
semantics), §14.2 Track 2 item 2, and the umbrella Global Constraints.

**Sibling subspecs:**
[`2026-09-13-win9x-calling-convention-design.md`](./2026-09-13-win9x-calling-convention-design.md) (Track 1),
[`2026-09-13-async-compiler-core-design.md`](./2026-09-13-async-compiler-core-design.md) (Track 2),
[`2026-09-13-coroutine-integration-design.md`](./2026-09-13-coroutine-integration-design.md) (Track 4).
**Previous subspec:** async-compiler-core.
**Next subspec:** coroutine-integration.

**Plan:** [`../plans/2026-09-13-std-async-plan.md`](../plans/2026-09-13-std-async-plan.md).
**Status:** draft, amendable in place.

---

## 1. Scope

This subspec governs **Stage 5** of the umbrella async track — the concrete,
no-generics Z98 runtime library that drives compiler-synthesized coroutine steps —
plus **every install touchpoint** that makes the module usable from a rebuilt
compiler:

1. New `sf/src/std_async.zig`:
   - types `TaskState`, `StepFn`, `FrameError`, `Context`, `Task`, `Scheduler`;
   - `Context` pool primitives `contextInit`, `contextAlloc`, `contextMark`,
     `contextRelease`;
   - scheduler free functions `schedulerInit`, `addTask`, `tick`, `suspend`,
     `awaitTask`, `cancel`, `cancelAll`, `waitAll`.
2. Re-export from `sf/src/std.zig` as `pub const async = @import("std_async.zig");`
   after the `net` re-export (`sf/src/std.zig:7`).
3. Install touchpoints (spike report §5.3): `scripts/seed/build_from_seed.sh:139`
   (and its `:24` "8 std" comment), `scripts/seed/archive_seed.sh:109` (and its
   `:28-29`, `:156-158`, `:210-211` std-set lists/counts),
   `scripts/self_compile/build_zig1_5.sh:12`, the `docs/sf/QUICK_REF.md:98`
   install recipe, and `docs/sf/QUICK_REF.md:36-37` (the "8 std `.zig`" seed
   inventory, which becomes 9).
4. Seed `lib/` rotation at closeout (the seed `lib/` gains the 9th module; the
   compiler fixed point is unchanged).

**Cross-track contract.** Track 3 **consumes** the builtin/frame surface pinned
by Track 2 (`@asyncFrameSize`/`@asyncInit`/`@asyncResume`/`@asyncSuspend`, the
`__async_step_<f>` ABI, `ctx`-in-frame, and the per-task LIFO child-frame
allocation contract) and **produces** the library that Track 4
(`coroutine-integration-design.md`) consumes when porting `rogue_mud`/`mud_server`.

**Deliberate independence.** `std_async.zig` is a pure Z98 user module: it uses no
`@async*` builtin and needs no compiler change. Its fixtures drive hand-written
state-machine step functions, so the library can be implemented, gated, and landed
independently of Track 2. The builtins are consumed only by generated steps at
integration time (Track 4).

## 2. Non-goals

- No compiler-core change (Track 2): no suspension analysis, no frame layout, no
  state-machine lowering, no builtin plumbing, no new `ErrorCode`.
- No integration/port (Track 4): no `rogue_mud`/`mud_server` conversion.
- No generics, `@typeInfo`, `@Type`, `anytype`, closures, or threads/preemption
  (umbrella §4); the scheduler is cooperative only.
- No `std.Io` event-loop abstraction.
- No module-scope mutable globals in the library (umbrella §6 concern 2): the
  caller supplies the `Scheduler` and every `Context`.
- No fixed-point movement and no `EXPECTED_FAIL` code-value change; only the
  corpus directory count/bucket counts move (new OK fixtures).
- No new calling-convention surface (Track 1); all functions use the default Z98
  C convention.

## 3. Detailed design

### 3.1 Public API (exact signatures)

The complete module surface, as it must appear in `sf/src/std_async.zig`:

```zig
pub const TaskState = enum(u8) {
    ready = 0,
    running = 1,
    suspended = 2,
    done = 3,
    cancelled = 4,
};

pub const FrameError = error{OutOfFrame};

pub const StepFn = fn(frame: *void, arg: ?*void) ?*void;

pub const Context = struct {
    pool: [*]u8,
    capacity: usize,
    used: usize,
    oom: bool,
};

pub fn contextInit(pool: []u8) Context;
pub fn contextAlloc(ctx: *Context, size: usize) FrameError![*]u8;
pub fn contextMark(ctx: *Context) usize;
pub fn contextRelease(ctx: *Context, mark: usize) void;

pub const Task = struct {
    frame: *void,          // root frame in caller-owned buf (outside the pool)
    ctx: *Context,         // this task's child-frame pool
    state: TaskState,
    cancel_requested: bool,
    result: *void,         // caller-provided result slot (L3)
    step: StepFn,          // compiler-synthesized __async_step_<f>
    arg: *void,            // resume argument passed to step
    waiting_on: *Task,     // awaitTask dependency (valid iff has_waiting_on)
    has_waiting_on: bool,
};

pub const Scheduler = struct {
    tasks: [*]Task,        // caller-owned backing array
    capacity: usize,
    count: usize,          // number of registered tasks
    current: usize,        // index of the running task
};

pub fn schedulerInit(tasks: []Task) Scheduler;
pub fn addTask(s: *Scheduler, t: *Task) bool;
pub fn tick(s: *Scheduler) FrameError!void;
pub fn suspend(s: *Scheduler, t: *Task) void;
pub fn awaitTask(s: *Scheduler, t: *Task) void;
pub fn cancel(s: *Scheduler, t: *Task) void;
pub fn cancelAll(s: *Scheduler) void;
pub fn waitAll(s: *Scheduler) FrameError!void;
```

`addTask` copies `t.*` into `s.tasks[s.count]` (scheduler-owned slot), forces
`state = .ready` and `has_waiting_on = false`, increments `count`, and returns
`false` when `count == capacity`. Callers address registered tasks through the
scheduler (`&s.tasks[i]`) after registration.

### 3.2 Context pool semantics (m1166 / m1172)

- **`buf` is outside the pool.** `@asyncInit(ctx, buf, fn, args)` places the
  **root** frame in the caller-owned `buf`; the pool never manages it.
- **The pool is per task and for CHILD frames only.** `Context` is a **per-task
  LIFO frame stack**, not a shared bump allocator. Each `Task` carries its own
  `ctx`; a `Context` is never shared between tasks.
- **`ctx` is stored in every frame and inherited unchanged.** Every nested frame
  gets the same `ctx` pointer from its parent's frame; the compiler-generated
  suspending call site reads `ctx` from the **caller** frame.
- **LIFO by bump + mark.** `contextMark` returns the current bump (`used`);
  `contextAlloc` returns `pool + used` and advances `used` by `size`;
  `contextRelease(mark)` restores `used`. A child frame is allocated before
  driving the child `_step` and released exactly when that `_step` returns null
  (terminal), so LIFO holds naturally — no free list, no fragmentation.
- **Caller-sized capacity.** `contextInit(pool)` fixes `capacity = pool.len`. The
  caller chooses the pool size; the static frame size returned by
  `@asyncFrameSize(fn)` **excludes** child frames (m1166), so the caller budgets
  for the deepest active chain.

### 3.3 Step ABI (`StepFn`) and the fn-ptr struct-field constraint

`StepFn = fn(frame: *void, arg: ?*void) ?*void` is byte-for-byte the Track 2
`__async_step_<f>(frame, arg) ?*void` ABI: a **null** result means terminal
(done); a **non-null** result means still yielded. `tick` calls
`t.step(t.frame, t.arg)`; `Task.arg` is a plain `*void` that coerces to `?*void`
at the call.

The step pointer is stored in the `Task.step` **struct field**. The historical
`fn_ptr_struct_field` emission gap (umbrella §6 concern 1) is **closed** at the
design fixed point: a `Task`-shaped struct with a
`fn(frame: *void, arg: ?*void) ?*void` field emits the field as a real fn-pointer
typedef and indirect-calls it correctly (verified 2026-09-13 on
`1467d932a876402f40a56316dfcad0e5`; prints the expected value). **Contingency:**
if a future change reopens the gap, drop `Task.step` and pass the step pointer
per call (`tick(s, t, step)`, `awaitTask(s, t, step)`) — this preserves
no-generics and no-fn-ptr-struct-field.

### 3.4 Scheduler semantics

- **Cooperative, single-pass.** `tick` visits tasks `0..count` in order and
  resumes each currently-runnable task exactly once: skip `done`/`cancelled`;
  honor `cancel_requested` (transition to `cancelled`, do not resume); skip a
  task whose `waiting_on` dependency is not yet `done`/`cancelled`, clearing the
  dependency once it settles; otherwise set `current`, mark `running`, call the
  step, and set `done` on a null result or `suspended` on non-null.
- **`suspend(s, t)`** marks `t` suspended (cooperative-yield bookkeeping).
- **`awaitTask(s, t)`** suspends the currently-running task (`s.tasks[s.current]`)
  until `t` is `done`/`cancelled`.
- **`cancel(s, t)`** sets `t.cancel_requested`; cancellation is observed at the
  next tick boundary (cooperative, never preemptive). `cancelAll` requests
  cancellation of every non-`done` task.
- **`waitAll(s)`** ticks until every task is `done` or `cancelled`.

### 3.5 Error model

- Pool exhaustion is `FrameError = error{OutOfFrame}`, **never a crash**
  (umbrella §12.4, m1166). `contextAlloc` returns `error.OutOfFrame` and sets the
  sticky `Context.oom` flag; `used` is not advanced.
- `tick` observes `t.ctx.oom` immediately after resuming a step and returns
  `error.OutOfFrame` before resuming further tasks; `waitAll` propagates it via
  `try`. `oom` stays set for the pool's lifetime (clear it by re-`contextInit`).
- `suspend`/`awaitTask`/`cancel`/`cancelAll` do not allocate and cannot fail.
- Compiler-level buffer-too-small / null-frame handling remains Track 2's
  `-fsafe` trap / `-ffast` UB contract; this library does not duplicate it.

### 3.6 Install surface

`std_async.zig` ships next to the compiler in `<exe_dir>/lib/`. Every point that
enumerates the std module set must include it (exact edits in the plan):

| # | Touchpoint | Change |
|---|---|---|
| 1 | `sf/src/std_async.zig` | new file |
| 2 | `sf/src/std.zig` | append `pub const async = @import("std_async.zig");` after `net` |
| 3 | `scripts/seed/build_from_seed.sh:139` | append `"$ROOT"/sf/src/std_async.zig` to the `lib/` `cp` (8 -> 9) |
| 4 | `scripts/seed/build_from_seed.sh:24` | comment "8 std .zig" -> 9 |
| 5 | `scripts/seed/archive_seed.sh:109` | add `std_async.zig` to the `for f in std.zig ... std_debug.zig` loop |
| 6 | `scripts/seed/archive_seed.sh:28-29,156-158,210-211` | std-set lists/"8 std" -> 9 |
| 7 | `scripts/self_compile/build_zig1_5.sh:12` | append `"$ROOT"/sf/src/std_async.zig` to the `lib/` `cp` |
| 8 | `docs/sf/QUICK_REF.md:98` | append `sf/src/std_async.zig` to the install recipe |
| 9 | `docs/sf/QUICK_REF.md:36-37` | "the 8 std `.zig`" -> 9 |
| 10 | `release/seed/zig1-seed.tgz` + `release/seed/CHANGELOG.md` | closeout rotation: the seed `lib/` gains the 9th module |

`std_async.zig` is pure Z98 (`@import`, plain structs/functions) — it needs no
`net_prelude.h`, `zig_pal.c`, runtime, or `@cInclude` change. Because it is not in
the compiler import graph (`sf/src/main.zig`), the emitted compiler C and the
self-emission fixed point are unchanged; only the archive's `lib/` contents move.

## 4. Interfaces

**Produces (for Track 4 and user programs).**
- The complete `std.async` API of §3.1, reachable as `std.async.*` through the
  `std.zig` re-export.
- The frozen `Context` layout `{ pool: [*]u8, capacity: usize, used: usize,
  oom: bool }` and the bump+mark pool primitive semantics.
- The `StepFn` ABI `fn(frame: *void, arg: ?*void) ?*void` and the `Task`/
  `Scheduler` records.

**Consumes (from Track 2, `async-compiler-core-design.md`).**
- The four builtins and their pinned signatures:
  ```zig
  @asyncFrameSize(fn) u32
  @asyncInit(ctx: *Context, buf: [*]u8, fn, args: ?*const void) *void
  @asyncResume(frame: *void, arg: ?*void) ?*void
  @asyncSuspend(data: ?*void) *void
  ```
- The `__async_step_<f>(frame: *void, arg: ?*void) ?*void` ABI (identical to
  `StepFn`) and the null=done / non-null=yielded convention.
- `@asyncFrameSize` **flat** semantics (excludes child frames) for sizing the
  root `buf` and each `Context.pool`.
- `ctx`-in-frame inheritance and the per-task LIFO child-frame allocation
  contract (`buf` outside the pool).

**Frozen-ABI reconciliation (must be resolved jointly before integration).**
Track 2 §3.3/§4 calls `Context` "opaque to the compiler core" while the Track 2
plan (Task 7) emits inline bump/mark reads of `ctx`. The two cannot both hold:
the field order above is the Track 3 contract. The implementation must pick one
mechanism — generated inline access at these offsets, **or** a runtime helper with
`contextAlloc`/`contextMark`/`contextRelease` semantics — and amend the other
subspec to match. This subspec fixes the **layout and semantics**; the emission
mechanism is amendable.

**Seed-lib contract.** The rebuilt compiler's `<exe_dir>/lib/` carries
`std.zig` + the 8 existing modules + `std_async.zig`; `std.zig` re-exports
`async`, so a bare `@import("std")` resolves `std.async`.

## 5. Diagnostics

**None.** `std.async` is user code: pool exhaustion is the Zig error
`FrameError.OutOfFrame`, not a compiler diagnostic. No `ErrorCode` member is
added and no existing numeric value shifts. The async builtin diagnostics
(`ERR_3017/3018/3019/3046`) and their explicit `= NNNN` assignments remain Track
2's (umbrella §12.7). A fixture that fails to compile (e.g. before the module is
installed) is an ordinary frontend `error[3000]`/`error[20]` — RED evidence, not a
new code.

## 6. Testing

Five new corpus fixtures under `repro/mi_matrix/`, with deterministic byte-exact
stdout over 3 runs (`-ffast`, `RUNRC=0`):

| Fixture | Import | Covers | Exact stdout | stdout md5 (3x) |
|---|---|---|---|---|
| `stdlib_async_pool_xmod` | `std.async.*` | `contextInit`/`contextAlloc`/`contextMark`/`contextRelease`; LIFO reclaim; `OutOfFrame`; sticky `oom`/`used` | `1 1 1 1 0 1 1` | `38f19e53c09cbb69c1919cb5385c708d` |
| `stdlib_async_sched_xmod` | `@import("std_async.zig")` | `schedulerInit`/`addTask`/`suspend`/`tick`/`waitAll`; `count`; step fn-ptr struct field | `1 3 2 10 20 30` | `29d3c32a9c1d30152faffca161cccac0` |
| `stdlib_async_await_xmod` | `@import("std_async.zig")` | `awaitTask` dependency ordering + `cancel` | `10 20 4` | `7bbb0c578b9e01e312325b4d2e5f8c93` |
| `stdlib_async_cancelall_xmod` | `@import("std_async.zig")` | `cancelAll` at a tick boundary; states settle to `cancelled` | `4 4 4` | `83b80a0f4d19b15f7cb1da65abf557a9` |
| `stdlib_async_oom_xmod` | `@import("std_async.zig")` | `contextAlloc` exhaustion sets `oom`; `tick` propagates `error.OutOfFrame` (no crash) | `1 1` | `f2160c8ffedf48068f2e1137e0a3a7e7` |

`stdlib_async_pool_xmod` exercises the `std.zig` re-export directly (function
calls and `*std.async.Context` annotations). The other four import the installed
module file `std_async.zig` through the compiler's `<exe_dir>/lib` search path,
because `@import("std")` + `std.async.Task{...}` / `std.async.TaskState.ready`
(value-position nested module access) currently trips the pre-existing compiler
`error[3042]` "non-value base expression in field access" (see §7). Both import
forms exercise the same installed module; the direct form is the documented
workaround.

Gate battery (every task; full sweep at closeout):
- Build from the seed model
  (`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>`), gate
  `=== [seed] Done: <out> ===`.
- Per fixture: dump with the rebuilt compiler, compile every `DIR/*.c` with the
  binding flag set, link/run via the emitted `build_target.sh`, assert the
  byte-exact stdout and md5 across 3 runs.
- Corpus classifier by gcc exit code (`docs/sf/QUICK_REF.md:134-145`), never by
  empty stderr: baseline 570 = 541 OK / 29 GREEN / 0 FAIL -> **575 = 546 OK / 29
  GREEN / 0 FAIL / 0 ICE / 0 CRASH**, `-ffast` == `-fsafe` zero-asymmetric.
- `scripts/check_emit_support.sh <zig1>` -> `[check] OK: 5/5 support files
  byte-identical to canonical` (user-module install does not touch emitted
  support).
- `EXPECTED_FAIL.md` header bump to v78 with the new universe count (no class
  movement on pre-existing dirs).
- Closeout seed rotation via
  `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`;
  assert the gcc-only archive fixed-point md5 is still
  `1467d932a876402f40a56316dfcad0e5` (or Track 2's post-closeout value) and the
  `lib/` now has 9 modules.

## 7. Risks

- **Frozen Context ABI vs Track 2 "opaque" wording.** The single largest
  cross-track risk; see §4. Mitigation: the layout/primitive contract is pinned
  here and the plan's Task 1 states it; either Track 2 amends its wording or
  adoption of a runtime helper, and no field is added silently.
- **`fn_ptr_struct_field` regression.** `Task.step` relies on the gap staying
  closed. Mitigation: a dedicated fixture (`stdlib_async_sched_xmod`) indirect-calls
  through the field, and §3.3 states the per-call-step fallback.
- **Optional-pointer struct fields + `[N]T = undefined`.** Arrays of a struct with
  an optional pointer field emit invalid C (`field = 0` to an `Opt_` type) at the
  design fixed point. `Task` therefore uses `waiting_on: *Task` plus a
  `has_waiting_on: bool` rather than `waiting_on: ?*Task`. Do not "simplify" it
  back to an optional field without fixing the emitter.
- **Module-scope mutable globals.** The library takes a caller-supplied
  `Scheduler`/`Context` and defines no module state (umbrella §6 concern 2).
  Fixtures keep the OOM path global-free; no fixture of record needs a global.
- **`std.async` value-position nested access (`error[3042]`).** At the design
  fixed point, a bare `@import("std")` consumer can call `std.async.fn(...)` and
  annotate `*std.async.Context`, but **cannot** write `std.async.Task{...}`,
  `std.async.TaskState.ready`, or `const T = std.async.Task;` — the re-exported
  module is not usable as a value/constructor base (`error[3042]` "non-value base
  expression in field access" + `warning[3023]`). This is a pre-existing compiler
  limitation, not introduced here; fixing it is a compiler follow-up outside
  Track 3's file scope. Documented workaround: import the installed module file
  directly, `const sa = @import("std_async.zig");`, which resolves via
  `<exe_dir>/lib` and supports the full API. The `std.zig` re-export stays
  (required by umbrella §12.5 and used for the function/type surface).
- **Install-count drift.** The seed `lib/` set is enumerated in several scripts and
  docs; a missed anchor leaves a rebuilt compiler unable to resolve `std.async`
  (bare import fails `error[20]`/`error[3000]`). The plan lists every anchor.
  Known out-of-list staleness to record, not silently fix: `docs/sf/AGENTS.md:476`
  ("the 4 std `.zig`") and `scripts/check_emit_support.sh:16` ("the 8 std `*.zig`").
- **Fixed-point movement assumption.** If any Track 3 edit accidentally lands in
  the compiler import graph, the fixed point moves and the seed-rotation
  assertions change. Mitigation: only `sf/src/std_async.zig` and `sf/src/std.zig`
  change under `sf/src`; `std.zig` is not imported by `sf/src/main.zig`.

## 8. Dependencies

**Consumes.**
- Umbrella §5 (L1 implicit-await, L2/m1166 `@asyncInit(ctx, buf, fn, args)`, L3
  result slot), §6 non-negotiable concerns, §12.4/§12.5, §15.2, §14.2 Track 2 item
  2; spike report Task 2 §5 and operator rulings m1166/m1172.
- Track 2 (`async-compiler-core-design.md`): the pinned builtin surface, the
  `__async_step_<f>` ABI, `ctx`-in-frame inheritance, `@asyncFrameSize` flat
  semantics, and the LIFO child-frame contract. Track 3's own implementation and
  fixtures do not require the builtins to exist; only generated steps at
  integration consume them.
- Existing tooling: `scripts/seed/build_from_seed.sh`,
  `scripts/seed/archive_seed.sh`, `scripts/self_compile/build_zig1_5.sh`,
  `scripts/check_emit_support.sh`, `scripts/corpus/list_corpus_dirs.sh`,
  `docs/sf/QUICK_REF.md`.

**Produces.**
- `sf/src/std_async.zig` + `std.zig` re-export + install touchpoints + 5 corpus
  fixtures + seed `lib/` rotation.
- The `std.async` API and frozen `Context`/`StepFn` ABI that Track 4
  (`coroutine-integration-design.md`) consumes for the `rogue_mud`/`mud_server`
  port.
