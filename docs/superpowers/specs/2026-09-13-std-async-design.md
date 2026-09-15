# Z98 std.async Library (Track 3) — Design

**Date:** 2026-09-13
**Branch:** `zig1_improvements`
**Baseline HEAD:** `e2a0f30a` (Track 2 landed and closed); compiler fixed point
`eda943dc1f77a48eae039e39ea4bfe04`; seed v15 (archive md5
`cd09877cbc373ad5c8801b93faccf188`); corpus 603 = 563 OK / 37 GREEN / 3 FAIL;
`EXPECTED_FAIL.md` v82. **Track 3 depends on Track 2** (dispatch order Track 2 →
Track 3): the library calls the `@asyncResume` builtin (Amendment 7 self-dispatch)
and consumes the landed frame/`ctx` layout. Track 3 does **not** modify the
compiler import graph (`std_async.zig` + `std.zig`; `std.zig` is not imported by
`sf/src/main.zig`), so it does not move the fixed point. Target corpus after the
seven new fixtures: 610 = 570 OK / 37 GREEN / 3 FAIL; `EXPECTED_FAIL.md` bump
v82 → v83.

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

**Cross-track contract (dispatch order: Track 2 → Track 3 → Track 4).** Track 3
**depends on** the landed Track 2 compiler core and **consumes** its
builtin/frame surface (`@asyncFrameSize`/`@asyncInit`/`@asyncResume`/
`@asyncSuspend`, the `__async_step_<f>` ABI, the hidden pointer-sized step word at
frame offset 0, the frame/`ctx` layout, and the per-task LIFO child-frame
allocation contract). It **produces** the library that Track 4
(`coroutine-integration-design.md`) consumes when porting `rogue_mud`/`mud_server`.

**Dependency on Track 2 — NOT independent.** `std_async.zig` is a pure Z98 user
module in the sense that it adds **no** compiler-core machinery, but its scheduler
**self-dispatches through the compiler builtin `@asyncResume(frame, arg)`**
(Amendment 7): the compiler must provide `@asyncResume`, the hidden step word at
frame offset 0, and the frame/`ctx` layout. The library is therefore **not
independent of Track 2**; Track 2 is landed, so this dependency is satisfied.
Track 3's own fixtures build frames **by hand** (a struct whose first field is the
step function pointer at offset 0) and drive them through the library scheduler;
they do not need `@asyncInit`. Generated steps consume the builtins at
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

// The synthesized-step ABI (Track 2 `__async_step_<f>`). It is a type alias for
// documentation only: the scheduler never stores or passes a StepFn (Amendment 7
// self-dispatch); it drives `@asyncResume(t.frame, t.arg)` instead.
pub const StepFn = fn(frame: *void, arg: ?*void) ?*void;

// Context (DECIDED: branch (a), compiler-core canon; see §4). The caller
// declares an 8-ALIGNED buffer (a bare `[N]u8` array is only 1-aligned; use an
// 8-aligned backing, e.g. a `u64` array cast to `[]u8`); the Context sits at the
// HEAD of that buffer; the pool bytes follow the 16-byte header:
//   used     @ ctx+0   (usize)
//   capacity @ ctx+4   (usize)
//   oom      @ ctx+8   (u8 or bool)
//   reserved @ ctx+9..15 (padding)
//   pool     @ ctx+16  (DERIVED — NOT a stored field; `pool_base = ctx + 16`)
// The 16-byte header keeps `pool_base = ctx+16` 8-aligned whenever `buf` is
// 8-aligned, so child frames holding 8-byte-aligned members (e.g. `f64`) stay
// aligned. `pool_base = ctx+16` being DERIVED (not stored) is itself a design
// decision: it makes it impossible for the pool base to diverge from the
// allocation.
pub const Context = struct {
    used: usize,
    capacity: usize,
    oom: bool,
};

pub fn contextInit(buf: []u8) *Context; // buf MUST be 8-aligned and len >= 16
pub fn contextAlloc(ctx: *Context, size: usize) FrameError![*]u8;
pub fn contextMark(ctx: *Context) usize;
pub fn contextRelease(ctx: *Context, mark: usize) void;

pub const Task = struct {
    frame: *void,          // root frame from @asyncInit (caller-owned buf, outside the pool)
    ctx: *Context,         // this task's child-frame pool
    state: TaskState,
    cancel_requested: bool,
    result: *void,         // caller-provided result slot (L3)
    arg: *void,            // resume argument passed to @asyncResume
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

**Amendment 7 — heterogeneous self-dispatch.** `Task` has **no `step` field**,
and there is **no `step` parameter** on any scheduler function. `tick`/`waitAll`
drive each runnable task with `@asyncResume(t.frame, t.arg)`: the frame's hidden
step word (offset 0) selects the correct `__async_step_<f>`, so a scheduler may
hold tasks of different step functions (heterogeneous) with no user-nameable
step. This is the single scheduler model shared by Track 3 and Track 4 and
resolves umbrella §16.1's step/scheduler item.

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
  `contextAlloc` returns the derived pool base (`ctx + 16`) plus `used` and
  advances `used` by `size`;
  `contextRelease(mark)` restores `used`. A child frame is allocated before
  driving the child `_step` and released exactly when that `_step` returns null
  (terminal), so LIFO holds naturally — no free list, no fragmentation.
- **Caller-sized capacity (M1 — usable bytes after the header).** `contextInit`
  fixes `capacity = region_size - 16`: the usable pool bytes **after** the
  16-byte Context header, not the whole buffer. The caller chooses the region
  size; the static frame size returned by `@asyncFrameSize(fn)` **excludes**
  child frames (m1166), so the caller budgets for the deepest active chain. The
  pool fixtures must set `size - 16`; any fixture cleanup is a follow-up. M1 is
  **resolved by this convention** (part of the layout decision, not a standalone
  minor).
- **8-aligned buffers (precondition).** `contextInit` requires `buf.ptr` to be
  8-aligned and `@panic`s in both modes otherwise; the 16-byte header then keeps
  `pool_base = ctx + 16` 8-aligned, so allocated child frames holding
  `f64`/`u64` members are correctly aligned. Fixtures back the pool with a
  `[N]u64` array (or equivalent) to guarantee the alignment.
- **Per-task Context reset (M3).** A `Context` is per-task; `@asyncInit` sets
  `used = 0` and `oom = 0` on each call. Because `oom` is sticky for the pool's
  lifetime, reusing a Context after an exhaustion without re-`contextInit` (or
  `@asyncInit`) would carry the stale `oom` forward — `@asyncInit`'s reset is
  what clears it on reuse. M3 is **resolved by this convention** (part of the
  layout decision, not a standalone minor).

### 3.3 Step ABI (`StepFn`) and the fn-ptr struct-field constraint

`StepFn = fn(frame: *void, arg: ?*void) ?*void` is byte-for-byte the Track 2
`__async_step_<f>(frame, arg) ?*void` ABI: a **null** result means terminal
(done); a **non-null** result means still yielded.

**Amendment 7 — self-dispatch.** The step is **not stored in `Task` and not
passed per call**. The compiler writes the step word into the frame header
(**offset 0, pointer-sized**) at `@asyncInit`; `tick`/`waitAll` drive each task
with `@asyncResume(t.frame, t.arg)`, which **loads the step word and dispatches**.
`Task.arg` is a plain `*void` that coerces to `?*void` at the call. The
synthesized `__async_step_<f>` symbol is compiler-managed and **never
user-materializable** (Prelude B), so no user code — including `std.async` — can
name a step. A scheduler is therefore **heterogeneous**: tasks backed by
different synthesized steps coexist in one scheduler. `StepFn` remains only as
the documented ABI alias (the `fn_ptr_struct_field` emission gap is no longer a
dependency of this design, and was re-verified **closed** at the current fixed
point).

### 3.4 Scheduler semantics

- **Cooperative, single-pass.** `tick` visits tasks `0..count` in order and
  resumes each currently-runnable task exactly once: skip `done`/`cancelled`;
  honor `cancel_requested` (transition to `cancelled`, do not resume); skip a
  task whose `waiting_on` dependency is not yet `done`/`cancelled`, clearing the
  dependency once it settles; otherwise set `current`, mark `running`, drive
  `@asyncResume(t.frame, t.arg)` (self-dispatch through the frame step word), and
  set `done` on a null result or `suspended` on non-null.
- **`suspend(s, t)`** marks `t` suspended (cooperative-yield bookkeeping).
- **`awaitTask(s, t)`** suspends the currently-running task (`s.tasks[s.current]`)
  until `t` is `done`/`cancelled`. If the scheduler has no registered task
  (`s.count == 0`) it `@panic`s (`std.async: awaitTask called with no registered
  task`) instead of reading `s.tasks[0]` out of bounds — "forgot `addTask`, then
  await" is surfaced rather than silently reading OOB.
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

`std_async.zig` is plain Z98 (`@import`, structs, free functions) — it adds no
`net_prelude.h`, `zig_pal.c`, runtime, or `@cInclude` surface. It does call the
Track 2 builtin `@asyncResume` (Amendment 7), so it is **not** independent of
Track 2. Because it is not in the compiler import graph (`sf/src/main.zig`), the
emitted compiler C and the self-emission fixed point are unchanged; only the
archive's `lib/` contents move.

## 4. Interfaces

**Produces (for Track 4 and user programs).**
- The complete `std.async` API of §3.1, reachable as `std.async.*` through the
  `std.zig` re-export.
- The **decided** `Context` layout (branch (a), compiler-core canon — see the
  reconciliation below): `{ used @ ctx+0, capacity @ ctx+4, oom @ ctx+8, pool
  @ ctx+16 (DERIVED) }` and the bump+mark pool primitive semantics;
  `contextInit(buf: []u8) *Context` places the Context at the head of `buf`.
  **PRECONDITION: `buf` MUST be 8-aligned and `len >= 16`** (`contextInit`
  traps in both modes on a misaligned buffer; under `-fsafe` it traps on
  `len < 16`).
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
  root `buf` and each Context pool region.
- `ctx`-in-frame inheritance and the per-task LIFO child-frame allocation
  contract (`buf` outside the pool).

**Context-layout reconciliation — DECIDED: branch (a).** The earlier "RESOLVED"
claim (Amendment 7, Res 1, inline at `{pool, capacity, used, oom}`) is **struck**:
it does not match what landed. The compiler core (Track 2, Task 7) **originally**
pinned the inline layout `{ used @ ctx+0, capacity @ ctx+4, oom @ ctx+8 }` with a
**12-byte** header (`pool base = ctx+12`), which diverged from this design's
16-byte `std.async` header (`pool base = ctx+16`). The **cross-track ABI fix
(Rule A, 2026-09-15)** moved the compiler core to the **16-byte** header
(`CTX_POOL_OFF = 16`), so both tracks now pin `{ used @ ctx+0, capacity @ ctx+4,
oom @ ctx+8, 4 bytes padding, pool base = ctx+16 (DERIVED) }`. **Track 3 accepts
that layout (branch (a))** (operator ruling m1662): `Context` physically sits at
the head of the caller's pool buffer and `contextInit` returns a `*Context`
pointing into that buffer.
The caller's `buf` **MUST be 8-aligned**; the 16-byte header then makes
`pool_base = ctx + 16` 8-aligned. Ownership remains INLINE (no heap, no fixed
array in the struct, no generics); the compiler reads the pool fields inline
(bump + mark). `pool_base` is **derived** (`ctx + 16`), not stored — making it
impossible for the pool base to diverge from the allocation.
The decided caller idiom:

```zig
var buf: [4096]u8 = undefined;   // MUST be 8-aligned (a [N]u8 array is only 1-aligned; use an 8-aligned backing, e.g. a u64 array)
var ctx = std.async.contextInit(buf[0..]);   // *Context, points into buf
// pass `ctx` (not `&ctx`) to contextAlloc/contextMark/contextRelease;
// read ctx.used / ctx.oom.
```

**Rejected alternative — by-value `Context` + separate `pool_base`.** Keeping a
by-value `Context` returned from `contextInit` plus a separate `pool_base`
argument/field was **rejected** (operator ruling m1662): it redoes landed Track 2
work for a smaller safety margin. The landed compiler reads/writes the Context
inline at `ctx+0/+4/+8` and derives `pool_base = ctx+16`; a stored `pool_base`
would be a second source of truth and a cross-read hazard. (Worth a pass after
the track closeout to re-check.)

> **WARNING — the two layouts are NOT interchangeable.** A reader that assumes
> the **stored-pointer** layout `{pool@0, capacity@4, used@8, oom@12}` against
> the landed inline header would **misread `used` as `pool`, `capacity` as
> capacity (coincidentally right), `oom` as `used`, and derive the pool base
> into the wrong region** — silent memory corruption. Do not cross-read the two
> layouts; Track 3 has picked branch (a).

**Seed-lib contract.** The rebuilt compiler's `<exe_dir>/lib/` carries the 8
existing std `.zig` + `std_async.zig` (9 total); `std.zig` re-exports `async`,
so a bare `@import("std")` resolves `std.async`.

## 5. Diagnostics

**None.** `std.async` is user code: pool exhaustion is the Zig error
`FrameError.OutOfFrame`, not a compiler diagnostic. No `ErrorCode` member is
added and no existing numeric value shifts. The async builtin diagnostics
(`ERR_3017/3018/3019/3046`) and their explicit `= NNNN` assignments remain Track
2's (umbrella §12.7). A fixture that fails to compile (e.g. before the module is
installed) is an ordinary frontend `error[3000]`/`error[20]` — RED evidence, not a
new code.

## 6. Testing

Seven new corpus fixtures under `repro/mi_matrix/`, with deterministic byte-exact
stdout over 3 runs (`-ffast`, `RUNRC=0`):

| Fixture | Import | Covers | Exact stdout | stdout md5 (3x) |
|---|---|---|---|---|
| `stdlib_async_pool_xmod` | `std.async.*` | `contextInit`/`contextAlloc`/`contextMark`/`contextRelease`; LIFO reclaim; `OutOfFrame`; sticky `oom`/`used` | `1 1 1 1 1 0 1 1` | `c16d5048077564d79de58d17c0e6b43e` |
| `stdlib_async_headerexact_xmod` | `std.async.*` | header-exact (16 B) buffer -> `capacity == 0`; first alloc is `OutOfFrame`, sticky `oom`, `used` stays 0 | `1 1 1 1` | `97b36f60d6c645fe73e654a950d10b72` |
| `stdlib_async_f64align_xmod` | `std.async.*` | `pool_base = ctx+16` is 8-aligned; `@sizeOf(Frame)` alloc returns an 8-aligned pointer; `f64` field round-trips | `1 1 1` | `280262bb00bfccfa4c24774d8faccde2` |
| `stdlib_async_sched_xmod` | `@import("std_async.zig")` | `schedulerInit`/`addTask`/`suspend`/`tick`/`waitAll`; `count`; **heterogeneous self-dispatch** (`@asyncResume(t.frame, t.arg)`, no `Task.step`, no step parameter) | `1 3 2 10 20 30` | `29d3c32a9c1d30152faffca161cccac0` |
| `stdlib_async_await_xmod` | `@import("std_async.zig")` | `awaitTask` dependency ordering + `cancel` | `10 20 4` | `7bbb0c578b9e01e312325b4d2e5f8c93` |
| `stdlib_async_cancelall_xmod` | `@import("std_async.zig")` | `cancelAll` at a tick boundary; states settle to `cancelled` | `4 4 4` | `83b80a0f4d19b15f7cb1da65abf557a9` |
| `stdlib_async_oom_xmod` | `@import("std_async.zig")` | `contextAlloc` exhaustion sets `oom`; `tick` propagates `error.OutOfFrame` (no crash) | `1 1` | `f2160c8ffedf48068f2e1137e0a3a7e7` |

`stdlib_async_pool_xmod` (plus `stdlib_async_headerexact_xmod` and
`stdlib_async_f64align_xmod`) exercises the `std.zig` re-export directly
(function calls and `*std.async.Context` annotations). The other four import the
installed module file `std_async.zig` through the compiler's `<exe_dir>/lib`
search path, because `@import("std")` + `std.async.Task{...}` /
`std.async.TaskState.ready` (value-position nested module access) currently trips
the pre-existing compiler `error[3042]` "non-value base expression in field
access" (see §7). Both import forms exercise the same installed module; the
direct form is the documented workaround.

Gate battery (every task; full sweep at closeout):
- Build from the seed model
  (`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>`), gate
  `=== [seed] Done: <out> ===`.
- Per fixture: dump with the rebuilt compiler, compile every `DIR/*.c` with the
  binding flag set, link/run via the emitted `build_target.sh`, assert the
  byte-exact stdout and md5 across 3 runs.
- Corpus classifier by gcc exit code (`docs/sf/QUICK_REF.md:134-145`), never by
  empty stderr: baseline 603 = 563 OK / 37 GREEN / 3 FAIL -> **610 = 570 OK / 37
  GREEN / 3 FAIL / 0 ICE / 0 CRASH**, `-ffast` == `-fsafe` zero-asymmetric.
- `scripts/check_emit_support.sh <zig1>` -> `[check] OK: 5/5 support files
  byte-identical to canonical` (user-module install does not touch emitted
  support).
- `EXPECTED_FAIL.md` header bump v82 → v83 with the new universe count (no class
  movement on pre-existing dirs).
- Closeout seed rotation via
  `bash scripts/seed/archive_seed.sh <zig1> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`;
  assert the gcc-only archive fixed-point md5 is still
  `eda943dc1f77a48eae039e39ea4bfe04` and the `lib/` now has 9 modules.

## 7. Risks

- **Context ABI vs Track 2 "opaque" wording — DECIDED: branch (a) (m1662).** The
  earlier "RESOLVED" claim is **struck**. Ownership is INLINE and Track 3 adopts
  the compiler-core layout `{used@0, capacity@4, oom@8, pool base ctx+16
  (DERIVED)}` (not the earlier `{pool, capacity, used, oom}` order); the header
  is **16 bytes** so `pool_base = ctx+16` is 8-aligned when the caller's `buf`
  is 8-aligned (a documented precondition; `contextInit` traps on a misaligned
  buffer in both modes). `contextInit` returns a `*Context` pointing into the
  caller's buffer. The by-value + separate `pool_base` alternative is
  **rejected** (redoes landed Track 2 work; a stored base is a second source of
  truth). See §4.
- **`fn_ptr_struct_field` regression — no longer a dependency (Amendment 7).**
  `Task.step` is removed; the scheduler self-dispatches through the frame step
  word, so this design no longer relies on a fn-ptr struct field. The gap was
  re-verified **closed** at the current fixed point; `stdlib_async_sched_xmod`
  now covers heterogeneous self-dispatch instead.
- **Optional-pointer struct fields + `[N]T = undefined`.** Arrays of a struct with
  an optional pointer field emit invalid C (`field = 0` to an `Opt_` type) at the
  design fixed point. `Task` therefore uses `waiting_on: *Task` plus a
  `has_waiting_on: bool` rather than `waiting_on: ?*Task`. Do not "simplify" it
  back to an optional field without fixing the emitter.
- **Module-scope mutable globals.** The library takes a caller-supplied
  `Scheduler`/`Context` and defines no module state (umbrella §6 concern 2).
  Fixtures keep the OOM path global-free; no fixture of record needs a global.
- **`std.async` value-position nested access (`error[3042]`) — DOCUMENT BEFORE
  TRACK 3, DO NOT RESOLVE BEFORE TRACK 3 (Amendment 7, Res 4).** At the design
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
- Track 2 (`async-compiler-core-design.md`), **landed and closed**: the pinned
  builtin surface, the `__async_step_<f>` ABI, the hidden step word at frame
  offset 0, `ctx`-in-frame inheritance, `@asyncFrameSize` flat semantics, and the
  LIFO child-frame contract. Track 3 **depends on** this surface: the library
  scheduler calls `@asyncResume(frame, arg)` (Amendment 7) and its fixtures
  hand-build frames with the step word at offset 0. Dispatch order Track 2 →
  Track 3.
- Existing tooling: `scripts/seed/build_from_seed.sh`,
  `scripts/seed/archive_seed.sh`, `scripts/self_compile/build_zig1_5.sh`,
  `scripts/check_emit_support.sh`, `scripts/corpus/list_corpus_dirs.sh`,
  `docs/sf/QUICK_REF.md`.

**Produces.**
- `sf/src/std_async.zig` + `std.zig` re-export + install touchpoints + 7 corpus
  fixtures + seed `lib/` rotation.
- The `std.async` API and decided `Context` (branch (a); §4) / `StepFn` ABI
  that Track 4 (`coroutine-integration-design.md`) consumes for the
  `rogue_mud`/`mud_server` port.
