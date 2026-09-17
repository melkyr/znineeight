# 12 — Async / Coroutines (`@async*` + `std.async`) [updated: 2026-09-17 — Track 4 closeout]

## Summary

Z98 implements **cooperative, stackless coroutines** with four builtins and a library module:

| Piece | Location | Role |
|-------|----------|------|
| Suspension analysis | `sf/src/async_analysis.zig` | Program-wide `is_suspending` fixed point + authoritative frame sizes / state widths |
| Frame layout reader | `sf/src/async_frame_layout.zig` | Precise per-function frame layout (step/ctx/state/params/live/hidden tail) |
| State-machine transform | `sf/src/async_state_machine.zig` | Lowers each suspending function to `__Z98Step_<f>`; defines the `Context` header ABI |
| Builtin lowering | `sf/src/lower.zig` (`@asyncFrameSize` 4371, `@asyncInit` 4389, `@asyncResume` 4555, `@asyncSuspend` 4592) | Builtin semantics + `-fsafe` checks |
| Type checking | `sf/src/semantic_analyzer.zig` (2331-2368) | Result types + diagnostics 3017/3018/3019/3046 |
| Pipeline wiring | `sf/src/main.zig` (phase A 770-784, phase B 868-893, emission grouping 1160-1203) | Runs the passes; emits each step in its owning module |
| Scheduler library | `sf/src/std_async.zig` | `Context` / `Task` / `Scheduler` / drive primitives |

There is no `async`/`await` keyword and no `Future(T)` type. Coroutine state is type-erased to
`*void`, and the "event loop" is the ordinary `std.async` library driven from `main` or an
`export fn`. The formal pre-implementation plan lives in `sf/docs/corroutines.txt`; where it
differs from the landed surface below, the code is authoritative.

---

## 1. The `@async*` builtins

| Builtin | Result | Summary |
|---------|--------|---------|
| `@asyncFrameSize(fn)` | integer constant | Byte size of `fn`'s root frame; `fn` must be a known suspending function (`error[3046]`) |
| `@asyncInit(ctx, buf, fn, args)` | `*void` | Initialize a fresh root frame in `buf` for `fn`; returns the frame |
| `@asyncSuspend(data)` | `*void` | Explicit suspension point; only inside a suspending function (`error[3018]`), not in `defer`/`errdefer` (`error[3019]`) |
| `@asyncResume(frame, arg)` | `?*void` | Resume a step; `null` = finished, non-`null` = still suspended |

`@asyncFrameSize` is folded at compile time to the frame size that `asyncFrameSizeRun` computed
(`sf/src/async_analysis.zig:605`). The other three lower to raw-byte frame stores/loads and a
function-pointer call (`sf/src/lower.zig:4389-4596`); the step function is reached through the
generic `__Z98StepFn` type (`?*void (*)(*void, ?*void)`), so the scheduler never stores a
per-function pointer type.

**`@asyncInit`.** It (a) resets the caller-supplied context header (`used = 0` at `ctx+0`, sticky
`oom = 0` at `ctx+2*usize`; the caller's `contextInit` already set `capacity`), (b) zero-fills the
frame, (c) writes the `__Z98Step_<fn>` word at frame offset 0, (d) stores `ctx` at the frame's ctx
offset and `state = 0`, and (e) copies the `args` record **positionally** into `fn`'s parameters.
The result is the frame pointer.

**`-fsafe` bounds check.** When `self.ctx.safe_checks` is set and the frame size is compile-time
known, `@asyncInit` recovers `buf`'s length only if the argument's resolved type is a pointer to a
concrete `[N]u8` array; then it emits `check_trap` kind 7 (trap when `N < frame_size`)
(`sf/src/lower.zig:4438-4462`). A slice/many-pointer buffer has no compile-time length, so the
check is skipped. `@asyncResume` similarly emits `check_trap` kind 4 (null-unwrap) when the loaded
step word is zero (`sf/src/lower.zig:4561-4567`). `-ffast` emits neither.

---

## 2. The compiled step machine

A function is **suspending** if its body directly contains `@asyncSuspend` (a seed) or directly
calls a suspending function (propagation). `suspensionAnalysisRun` (`sf/src/async_analysis.zig:178`)
builds a dense function index, collects direct-call edges and direct-`@asyncSuspend` seeds over the
AST, then runs a monotone worklist over a CSR reverse index. Mutual recursion is ordinary
propagation, never recursive descent. The result is stored in `ctx.suspending_fns`, keyed
`(module_id << 32) | name_id` (`asyncKey`, `sf/src/async_analysis.zig:37`).

Every suspending function is rewritten to a **step** named `__Z98Step_<f>` with the ABI

```zig
fn __Z98Step_<f>(frame: *void, arg: ?*void) ?*void
```

and the original synchronous body is **not** emitted. The step loads its hidden `state`, switches to
the numbered resume segment, and runs to the next suspension or to completion. An explicit
`@asyncSuspend` becomes: save every frame field, store `state = N`, return a non-`null` `?*void`;
the matching resume segment reloads the fields and continues. Returning `null` is terminal
(`sf/src/async_state_machine.zig:757`, `asyncTransform`).

**Implicit await.** A direct call to a suspending callee is an implicit await (`emitAwait`,
`sf/src/async_state_machine.zig:415`). The caller:
1. loads `ctx` from its own frame and inline-reads `used`/`capacity`/`oom` from the context header;
2. rounds `used` up to 8, checks `used_r + child_frame_size <= capacity`, and on overflow sets the
   sticky `oom` and takes the terminal path;
3. bump-allocates the child at `pool_base + used_r`, writes the callee's step word at child+0,
   stores the child's `ctx`/`state`, and copies the call arguments into the child's param offsets;
4. for a value-returning callee, points the child's hidden `result` at the caller's k-th
   `parent_result` slot;
5. drives the child's step once and yields (returns non-`null`) while the child is suspended; on
   resume it re-drives the child until the child returns `null`, then pops the child frame
   (`used -= child_frame_size`) and delivers the awaited value to the call result.

**Root `main`.** The single exception is the root `pub fn main`: it keeps its source name, module,
`is_pub`, and params, plus a minimal synchronous driver (`emitMainDriver`,
`sf/src/async_state_machine.zig:613`) that declares a local root buffer and a fixed 256-byte pool
(`ASYNC_ROOT_POOL_BYTES`, `sf/src/async_state_machine.zig:595`), initializes the context header,
writes the step word, copies params, and drives its own step to completion. This keeps the C
`int main` wrapper and direct-call regression fixtures working.

---

## 3. Frame layout / step ABI

`asyncLayoutFrame` (`sf/src/async_frame_layout.zig:522`) reads the lowered LIR and builds the exact
frame layout. The rows below are in **layout order** (offset order); the `Kind` column is the source
`ASYNC_FIELD_*` numeric value (`sf/src/async_frame_layout.zig:43-50`):

| Order | Kind | Field | Notes |
|-------|------|-------|-------|
| 0 | 4 (`ASYNC_FIELD_STEP`) | `step` | Pointer-sized step word at offset **0** |
| 1 | 0 (`ASYNC_FIELD_CTX`) | `ctx` | Pointer-sized per-task pool pointer |
| 2 | 1 (`ASYNC_FIELD_STATE`) | `state` | `u8` / `u16` / `u32` chosen from the suspension-point count |
| 3 | 2 (`ASYNC_FIELD_PARAM`) | `param` | Each `LirParam`, in order |
| 4 | 3 (`ASYNC_FIELD_LIVE`) | `live` | Hoisted temps live across ≥ 1 suspension, in temp-id order |
| 5 | 5 (`ASYNC_FIELD_CHILD`) | `child` | One `*void` child-frame slot (when the function awaits) |
| 6 | 6 (`ASYNC_FIELD_RESULT`) | `result` | One `*void` slot for the value returned through an await |
| 7 | 7 (`ASYNC_FIELD_PARENT_RESULT`) | `parent_result` | One slot per value-returning implicit await, in program order |

The state width is the single source of truth written by `asyncFrameSizeRun`
(`sf/src/async_analysis.zig:605`): `u8` for ≤ 255 suspension points, `u16` for ≤ 65535, else `u32`
(`asyncStateTypeForCount`, `sf/src/async_analysis.zig:518`). The Stage-3 transform fails closed with
`ERR_9001_ICE` if the actual LIR count exceeds the chosen width
(`sf/src/async_state_machine.zig:951`).

The authoritative frame size is computed by the AST-level conservative pass (it reserves a field for
every reachable AST node) and then padded up to 8 bytes. The precise LIR reader asserts
`precise <= frame_sizes[key]` (ICE otherwise) and reports the padded size
(`sf/src/async_frame_layout.zig:647-665`). **Every frame is 8-byte padded** so consecutive pool
frames stay 8-aligned given an 8-aligned pool base.

---

## 4. Multi-module `__Z98Step_<f>` emission

Each suspending function's step is emitted in its **owning module** (the step's `module_id` equals
the source function's). The pipeline runs in two phases (`sf/src/main.zig`):

- **Phase A (per module):** lower each function; if it is suspending, compute and publish its frame
  layout (`asyncLayoutPublish`), retain the LIR, and do **not** stream the original body.
- **Phase B (after all modules):** transform every retained suspending function. Layouts are
  published before any transform, so a caller declared before its callee still resolves the callee's
  offsets.

Because the synthesized step slots are appended to `lir_slots` **after** the per-module lowering
run, the multi-file emission path stable-groups every slot by owning module id (module ids are
dense: `mods[i].id == i`) before the cursor walk, so each module's `.c`/`.h` carries its own
originals plus its own steps (`sf/src/main.zig:1160-1203`, the Track-4 S15 fix). The single-file path
emits the whole slot list unchanged.

---

## 5. The `Context` ABI

`std.async.Context` occupies the first 16 bytes of a caller-supplied buffer; the child-frame pool
follows it. On the 32-bit target (`usize` = 4 bytes):

| Offset | Field | Notes |
|--------|-------|-------|
| `0` | `used` | Bump pointer (bytes consumed in the pool) |
| `4` | `capacity` | Usable bytes **after** the 16-byte header |
| `8` | `oom` | Sticky `u8` overflow flag |
| `9..15` | pad | Reserved; the compiler reserves a pointer-sized pad slot at `12..15` |
| `16` | pool base | `pool_base = ctx + HEADER_SIZE` (derived, never stored) |

`HEADER_SIZE = 16` (`sf/src/std_async.zig:51`) — not 12 — so `ctx + 16` stays 8-aligned whenever
`ctx` is 8-aligned. Buffers **must** be 8-aligned: back them with a `[K]u64` array (a bare `[N]u8`
is only 1-aligned) and cast to `[]u8`. `contextInit` traps if the buffer is misaligned and sets
`capacity = buf.len - 16` (`sf/src/std_async.zig:68`).

`contextAlloc` rounds `used` up to 8 before handing out a frame, checks `aligned + size > capacity`,
and on exhaustion sets `oom` and returns `error.OutOfFrame` — never a crash
(`sf/src/std_async.zig:82`). `contextMark` / `contextRelease` bracket a child so it is reclaimed
exactly when it returns. The Stage-3 transform uses the same constants inline (`CTX_USED_OFF = 0`,
`CTX_CAP_OFF = 4`, `CTX_OOM_OFF = 8`, `CTX_POOL_OFF = 16`; `sf/src/async_state_machine.zig:71-74`),
so a compiler-allocated child frame and one allocated by `std.async.contextAlloc` share one ABI.
The root-frame arena for `@asyncInit` targets **must start at `HEADER_SIZE`**, because the first 16
bytes are the `Context` header (aliasing them corrupts frame 0's step word).

---

## 6. `std.async` API

### `Context` / `Task` / `Scheduler`

```zig
pub const TaskState = enum(u8) { ready = 0, running = 1, suspended = 2, done = 3, cancelled = 4 };
pub const FrameError = error{OutOfFrame};

pub const Context = struct { used: usize, capacity: usize, oom: bool };
pub const Task = struct {
    frame: *void, ctx: *Context, state: TaskState, cancel_requested: bool,
    result: *void, arg: *void, waiting_on: *Task, has_waiting_on: bool,
};
pub const Scheduler = struct {
    tasks: [*]*Task, capacity: usize, count: usize, current: usize, in_task: bool,
};
```

`Task` stores **no step pointer**: `tick`/`waitAll` self-dispatch with `@asyncResume(t.frame, t.arg)`,
which loads the hidden step word at frame offset 0 (heterogeneous self-dispatch). `Scheduler.tasks`
is `[*]*Task`, so `addTask` stores the caller's handle — a task can be shared, cancelled, and
removed through the same object.

### Primitives

| Function | Context | Behavior |
|----------|---------|----------|
| `contextInit(buf) *Context` | any | Place the header at `buf[0..16]`; traps if `buf` is misaligned |
| `contextAlloc(ctx, size)` | any | 8-aligned bump alloc; `error.OutOfFrame` + sticky `oom` on exhaustion |
| `contextMark(ctx)` / `contextRelease(ctx, mark)` | any | LIFO child-frame reclaim |
| `schedulerInit(tasks) Scheduler` | any | Wrap a caller-owned `[]*Task` |
| `addTask(s, t) bool` | any | **Idempotent**: a registered active task returns `false`; a registered settled task is reset in place to `ready` (clearing `cancel_requested`/`has_waiting_on`) and returns `true`; otherwise appended, or `false` when the scheduler is already at `capacity` |
| `removeTask(s, t)` | any non-suspending | Compact `t` out of the scheduler; no-op if absent; does not change `t.state` |
| `tick(s) FrameError!void` | any | Resume every ready/suspended task once; observes `cancel_requested`; skips tasks parked on `waiting_on`; returns `error.OutOfFrame` if a resumed task's pool overflowed |
| `suspend(s, t)` | any | Mark `t` suspended (yield bookkeeping) |
| `awaitTask(s, t)` | **coroutine-internal** | Mark the current task suspended and `waiting_on = t`; `@panic` if `!s.in_task` (non-suspending context) or if the scheduler is empty |
| `waitFor(s, t) FrameError!void` | any non-suspending | Drive `tick` until `t` is settled; `@panic` if `t` is neither registered nor settled |
| `waitAll(s) FrameError!void` | any | Tick until every task is done/cancelled |
| `cancel(s, t)` / `cancelAll(s)` | any | Set `cancel_requested`; observed at the next tick boundary |

**The two wait contexts.** `awaitTask` is the *coroutine-internal* wait: it only parks the currently
running task (guarded by `Scheduler.in_task`, set by `tick` around `@asyncResume`) and is how a
suspending function waits on another task. `waitFor` is the *any-context* drive: it needs no caller
frame and is safe from `main`, an `export fn`, or a helper — but `tick` resumes **every** registered
non-done task, so `waitFor` is only appropriate when the other registered tasks do not block.

### `@asyncInit` coroutine-parameter ABI

`@asyncInit` copies the `args` record **positionally** into `fn`'s parameters, so the record's
fields *are* the coroutine's parameters. Pass a plain `*const void`:

```zig
pub const NpcCoroutineArgs = struct { na: *NpcArgs };
pub fn npcCoroutine(na: *NpcArgs) void { /* ... */ }

const rec = NpcCoroutineArgs{ .na = &args[n] };
task.frame = @asyncInit(ctx, @ptrCast([*]u8, frame), npcCoroutine,
    @ptrCast(*const void, &rec));
```

A `?*const void` cast must **not** be used (a non-scalar optional emits invalid C89); the
non-optional `*const void` coerces into the parameter. `drawToSocketCoroutine(ctx, args)` in
`rogue_mud/ui.zig` is *not* an `@asyncInit` target — it is called directly — and therefore keeps a
normal `(ctx, args)` signature.

---

## 7. Examples

| Entry | File | Shape |
|-------|------|-------|
| E1 NPC AI | `examples/z98/rogue_mud/lib/combat.zig:108` | `npcCoroutine(na: *NpcArgs)` + `NpcCoroutineArgs{ na }`; `npcStep(na)` then `@asyncSuspend(null)` in `while (true)`; `spawnEnemies` allocates root frames from the **permanent** `async_arena` and `addTask`s them; `updateEnemies(sched)` is `try std.async.tick(sched)` |
| E2 per-client broadcast | `examples/z98/rogue_mud/main.zig:433` | `clientFrameCoroutine(ctx, cfa: *ClientFrameArgs)` + `ClientFrameCoroutineArgs{ ctx, cfa }`; one long-lived task per client slot, self-gating on `.active`; builds into its **own** `client_cells[i]`; one row per `@asyncSuspend(null)` |
| E3 cross-module lifecycle | `main.zig` / `lib/combat.zig` / `ui.zig` | Tasks are created in `main.zig`/`combat.zig`, scheduled via `std.async`, and cancelled in `main.zig` (`cancel` per client, `cancelAll` on shutdown); each step is emitted in its owning module |
| E4 per-client tasks | `examples/z98/mud_server/main.zig:244` | `clientCoroutine(cta: *ClientTaskArgs)` + `ClientCoroutineArgs{ cta }`; one non-blocking `recv` + line processing then `@asyncSuspend(null)`; `main` accepts, `@asyncInit`s, `addTask`s; the drive is **readiness-gated** — only `select`-ready sockets are `@asyncResume`d, and a `null` return frees the slot directly (close socket, `is_active=false`, `state=.done`, `removeTask`) with no `waitFor`/`tick` |

**Two rules the examples pin.**
- **Permanent root frames.** A task's root frame must live for the task's whole life. `rogue_mud`
  allocates NPC/client frames from a dedicated `async_arena` (backed by `async_storage`, starting at
  `std.async.HEADER_SIZE`), never from the per-turn `temp_arena` that `sand_reset` reclaims.
- **Per-client buffers.** Each client task needs its own scratch (e.g. `client_cells[i]`); a shared
  buffer would interleave/corrupt between concurrent tasks.

---

## 8. Known limitations / declared residuals

- **Diagnostics.** `@asyncSuspend` outside a suspending function → `error[3018]`; an `@async*`
  builtin inside `defer`/`errdefer` → `error[3019]`; `@asyncFrameSize` on an unknown/non-suspending
  function → `error[3046]`; taking the address of a suspending function → `error[3017]`.
- **`-fsafe` only.** The `@asyncInit` frame-size bounds check and the `@asyncResume` null-step check
  exist only under `-fsafe`; `-ffast` omits them (bad input is UB).
- **Only root `main` keeps a synchronous entry.** A non-`main` suspending function (including an
  `export fn`) is replaced by its `__Z98Step_<f>` and keeps no synchronous/export entry; the root
  `pub fn main` is the sole function for which the compiler synthesizes a driver.
- **Root-`main` pool is fixed.** The synthesized `main` driver's child-frame pool is a fixed 256
  bytes (`ASYNC_ROOT_POOL_BYTES`), so a suspending `main` whose implicit awaits need larger child
  frames overflows. Use an explicit task + `std.async` pool for larger needs.
- **`waitFor` drives the whole scheduler.** `tick` resumes every registered non-done task, so
  `waitFor`/`waitAll` are unsuitable when other registered tasks block (e.g. blocking `recv`); the
  `mud_server` completion path therefore frees the slot directly.
- **`removeTask` mid-drive edge.** `removeTask` compacts the tail over the entry and adjusts
  `current`; do not call it for a task a coroutine is currently awaiting. It does not modify the
  task's own state.
- **Single-task scheduler caveats.** `awaitTask` panics on an empty scheduler or from a
  non-suspending context; `Scheduler.in_task` is public by design (Z98 has no private fields), so
  the guard is advisory to in-tree callers.
- **No preemption / threads / `std.Io`.** Coroutines are cooperative and round-robin only; there is
  no typed future (`Future(T)`) because generics are unavailable, and coroutine state is erased to
  `*void`.
- **For-loop array items are by-value copies.** `for (arr) |row|` where the item is itself a fixed
  array copies the row byte-wise (`sf/src/lower.zig:6138-6145`); this is real Zig `for |row|`
  semantics, so a mutation through `row` does not write back to `arr`. The broader array-to-array
  emission class (for-loop iteration, `*[N]T` element access, multi-dim field stores, array-literal
  init, row store) was closed in Track-4 Task 2g-F.
- **`*T`→`[*]T` at return/call-arg.** This coercion remains tolerated (not promoted to a hard
  `error[3000]`) because the compiler's valid array→pointer idiom (`&arr[0]`) relies on it; it is a
  declared residual from the Track-4 coercion work.
