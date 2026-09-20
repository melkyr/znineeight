# Async & Streams — `std.async` + `std_stream`

| | |
|---|---|
| **Modules** | `std.async`, `std_stream` |
| **Layers** | `std.async` — async runtime: the cooperative task scheduler and the per-task child-frame pool behind Z98 coroutines; `std_stream` — `L6` composition layer: coroutine-aware line and length-prefixed frame readers over L3 file/socket resources |
| **Import (re-export)** | `const std = @import("std");` → `std.async` |
| **Import (by path)** | `const std_async = @import("std_async");`, `const std_stream = @import("std_stream");` |

## Module overview

**Model C: cooperative yield, caller-driven.** Z98 coroutines have no executor
and no poll loop. A suspending function compiles to a step machine
(`@asyncInit`, `@asyncSuspend`, `@asyncResume`, `@asyncFrameSize`); the caller
owns a `Scheduler` and advances the world explicitly with `tick`. There is no
background thread and no hidden polling: a coroutine runs only while it is being
resumed, and it yields only when it chooses to (`@asyncSuspend`). `tick` resumes
every ready/suspended task once; `waitAll`/`waitFor` loop `tick` until tasks
settle.

**`Task` stores no step pointer.** `tick` self-dispatches with
`@asyncResume(t.frame, t.arg)`, which loads the hidden pointer-sized step word
the compiler writes at frame offset 0. `StepFn` is the documented
`__async_step_<f>` ABI alias only — the scheduler never stores or passes one.
The root frame lives in the caller-owned `buf` passed to `@asyncInit` and is
**outside** the child-frame pool.

**The `Context` is a per-task child-frame stack, not an allocator.** It occupies
the first `HEADER_SIZE` (16) bytes of a caller-supplied buffer; the pool bytes
follow at `ctx + 16`. The buffer **must be 8-aligned** — a `[N]u8` array is only
1-aligned, so back it with an 8-aligned type such as `var storage: [K]u64 =
undefined;` and cast to `[]u8`. `contextAlloc` bump-allocates 8-aligned child
frames; `contextMark`/`contextRelease` bracket a child so it is reclaimed exactly
when it returns. Exhaustion returns `error.OutOfFrame` and sets a sticky `oom`
flag — it is never a crash. The caller supplies **all** storage (R1); nothing
here owns memory.

**`std_stream` composes L3 resources with Model C.** `FileLineReader`,
`SocketLineReader`, and `MsgReader` each wrap a caller-owned resource and a
caller-owned `buf`. Every `read*` has a `Sync` (blocking, no suspension) and an
`Async` (cooperative-yield) form that are **separate implementations** sharing
the read primitive; the async path reaches the language-level `@asyncSuspend`
builtin directly, so `std_stream` does **not** import `std.async`. A program
that drives a `std_stream` coroutine imports `std.async` explicitly to own the
scheduler and call `tick`. The async paths yield on `error.WouldBlock`
(non-blocking sockets) or after each incomplete read (files).

**Line contract (both line readers).** A line is terminated by `\n` or `\r\n`;
the terminator is stripped. The final unterminated line at EOF is returned as-is.
`null` means EOF with nothing buffered. A line longer than `buf` is returned as a
full-buffer prefix and the remainder follows on subsequent calls. The reader
carries boundary state so a line whose length is an **exact multiple** of
`buf.len` does not surface a spurious empty line, and a `\r` landing exactly at
the buffer boundary is carried so a following `\n` closes the same line. The
returned slice aliases `buf` and is valid only until the next call; the reader
never allocates.

**Frame contract (`MsgReader`).** Each frame is a `u32` length prefix in
**network byte order (big-endian)** followed by that many body bytes. A declared
length greater than `buf.len` is `error.FrameTooLarge`. A zero-length prefix is a
**valid empty frame** (a length-0 slice, never `null`). A frame truncated by peer
close (EOF mid-prefix or mid-body) surfaces as `null`.

## Quick start

A driver loop plus one coroutine. `main` owns the scheduler, the frame pool, and
the task; the coroutine yields once per iteration.

```zig
const std = @import("std");
const std_async = @import("std_async");
const arena_mod = @import("std_arena");

var g_storage: [8192]u8 = undefined;
var g_arena = arena_mod.init(g_storage[0..]);

fn worker(count: *u32) void {
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        count.* += 1;
        _ = @asyncSuspend(null);
    }
}

pub fn main() void {
    var pool: [4096]u64 = undefined;
    var ctx = std_async.contextInit(@ptrCast([*]u8, &pool)[0..4096 * 8]);

    var count: u32 = 0;
    const frame_sz = @intCast(usize, @asyncFrameSize(worker));
    const frame_store = arena_mod.alloc(&g_arena, frame_sz) catch @panic("frame");

    var task: std_async.Task = undefined;
    task.frame = @asyncInit(@ptrCast(*void, ctx), @ptrCast([*]u8, frame_store), worker, @ptrCast(*const void, &count));
    task.ctx = ctx;
    task.arg = @ptrCast(*void, &count);
    task.result = @ptrCast(*void, &count);
    task.cancel_requested = false;
    task.waiting_on = &task;
    task.has_waiting_on = false;

    var pt: [1]*std_async.Task = undefined;
    pt[0] = &task;
    var s = std_async.schedulerInit(pt[0..]);
    _ = std_async.addTask(&s, &task);

    while (task.state != std_async.TaskState.done and task.state != std_async.TaskState.cancelled) {
        std_async.tick(&s) catch @panic("tick");
    }

    std.io.printInt(@intCast(i32, count));
    std.io.writeByte('\n');
}
```

## API

### `std.async`

#### `TaskState`

**Purpose** — the cooperative task lifecycle: `ready`, `running`, `suspended`,
`done`, `cancelled`.

**When to use** — to read or compare `Task.state`, and to know when a task has
settled (`done` or `cancelled`).

**Signature** — `pub const TaskState = enum(u8) { ready = 0, running = 1, suspended = 2, done = 3, cancelled = 4 };`

**Parameters** (members)
- `ready` — registered and eligible to be resumed.
- `running` — set by `tick` while the task is being resumed.
- `suspended` — yielded; `tick` resumes it unless it has a pending dependency.
- `done` — the step machine returned `null` (terminal).
- `cancelled` — a cancellation request was observed at a tick boundary.

**Returns** — an enum value.

**Errors** — none.

**Example**
```zig
if (task.state == std_async.TaskState.done) {
    std.io.write("settled\n");
}
```

**Gotchas** — a settled task is `done` **or** `cancelled`; test both when waiting.
`running` is only observable from inside a resume.

#### `FrameError`

**Purpose** — the scheduler's error set: child-frame pool exhaustion.

**When to use** — when naming the error from `tick`, `waitAll`, or `waitFor`.

**Signature** — `pub const FrameError = error{OutOfFrame};`

**Parameters** — none.

**Returns** — an error set, not a value.

**Errors** — `error.OutOfFrame`.

**Example**
```zig
std_async.tick(&s) catch |e| {
    if (e == error.OutOfFrame) return;
    return;
};
```

**Gotchas** — exactly one member. A pool that overflowed stays poisoned (the
`Context.oom` flag is sticky).

#### `StepFn`

**Purpose** — the documented `__async_step_<f>` ABI alias:
`fn(frame: *void, arg: ?*void) ?*void`.

**When to use** — only when writing a hand-rolled step function for a fixture
that sets it as the first `Frame` field so it lands at frame offset 0. Normal
code uses `@asyncInit`/`@asyncSuspend`.

**Signature** — `pub const StepFn = fn(frame: *void, arg: ?*void) ?*void;`

**Parameters** — none (it is a function type).

**Returns** — `null` means terminal (done); non-null means still yielded.

**Errors** — none.

**Example**
```zig
const Frame = struct { step: std_async.StepFn, ticks: u32 };

fn stepInc(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    if (fr.ticks < 2) {
        fr.ticks += 1;
        return f;
    }
    return null;
}
```

**Gotchas** — documentation only; the scheduler never stores or passes a
`StepFn` (it self-dispatches via `@asyncResume`). The historical
`fn_ptr_struct_field` gap is closed.

#### `HEADER_SIZE`

**Purpose** — the number of bytes reserved at the head of the caller's buffer
for the `Context` header: `16`.

**When to use** — when sizing the pool buffer; the usable pool is
`buf.len - HEADER_SIZE`.

**Signature** — `pub const HEADER_SIZE: usize = 16;`

**Parameters** — none.

**Returns** — a `usize` constant.

**Errors** — none.

**Example**
```zig
const cap = pool_bytes.len - std_async.HEADER_SIZE;
```

**Gotchas** — 16 (not 12) so `pool_base = ctx + 16` stays 8-aligned whenever the
buffer is 8-aligned. This is the cross-track ABI constant the compiler core's
`CTX_POOL_OFF` must match.

#### `Context`

**Purpose** — a per-task child-frame pool: a bump cursor, the usable capacity
after the header, and a sticky out-of-frame flag.

**When to use** — you hold a `*Context` only to pass to `@asyncInit` and
`contextAlloc`/`contextMark`/`contextRelease`; create it with `contextInit`.

**Signature** — `pub const Context = struct { used: usize, capacity: usize, oom: bool };`

**Parameters** (fields)
- `used` — bytes handed out so far (`@ ctx+0`).
- `capacity` — usable bytes after the 16-byte header (`@ ctx+4`).
- `oom` — sticky pool-exhaustion flag (`@ ctx+8`).

**Returns** — a plain value type; `contextInit` returns a pointer into the buffer.

**Errors** — none.

**Example**
```zig
var pool: [1024]u64 = undefined;
var ctx = std_async.contextInit(@ptrCast([*]u8, &pool)[0..1024 * 8]);
```

**Gotchas** — bytes 9..15 are reserved padding; `pool_base = ctx + 16` is
derived, never stored. The buffer must be 8-aligned and at least 16 bytes.

#### `contextInit`

**Purpose** — places a `Context` at the head of `buf` and returns a pointer to
it, with `used == 0` and `oom == false`.

**When to use** — once per task, on an 8-aligned buffer of at least 16 bytes.

**Signature** — `pub fn contextInit(buf: []u8) *Context`

**Parameters**
- `buf` — the caller-owned pool buffer. `buf.ptr` must be 8-aligned and
  `buf.len` must be at least 16.

**Returns** — `*Context` pointing into `buf`; `capacity` is `buf.len - 16`.

**Errors** — none exposed; a misaligned pointer `@panic`s, and under `-fsafe` a
`buf.len < 16` traps (the subtraction overflow check).

**Example**
```zig
var pool: [4096]u64 = undefined;
var ctx = std_async.contextInit(@ptrCast([*]u8, &pool)[0..4096 * 8]);
```

**Gotchas** — back the buffer with an 8-aligned type (`[K]u64`), not `[K]u8`.
The `Context` aliases `buf`; keep `buf` alive for the task's lifetime.

#### `contextAlloc`

**Purpose** — bump-allocates `size` bytes from the task's child-frame pool and
returns an 8-aligned pointer.

**When to use** — inside the compiler-generated frame machinery, or a fixture
that hand-manages child frames. Normal coroutines never call it directly.

**Signature** — `pub fn contextAlloc(ctx: *Context, size: usize) FrameError![*]u8`

**Parameters**
- `ctx` — the task's pool.
- `size` — bytes to reserve; the bump pointer is rounded up to 8 first, so the
  result is always 8-aligned.

**Returns** — `[*]u8` to `size` uninitialized bytes inside the pool.

**Errors** — `error.OutOfFrame` when `aligned + size > capacity`; this also sets
the sticky `ctx.oom` flag.

**Example**
```zig
const p = std_async.contextAlloc(ctx, 64) catch @panic("pool");
```

**Gotchas** — no free; reclaim children in LIFO order with `contextMark` /
`contextRelease`. Exhaustion is an error, never a crash. Once `oom` is set the
scheduler reports `OutOfFrame` for that task.

#### `contextMark`

**Purpose** — returns the current bump cursor, to be passed to
`contextRelease` when a child returns.

**When to use** — immediately before allocating a child frame whose lifetime is
bounded by a call.

**Signature** — `pub fn contextMark(ctx: *Context) usize`

**Parameters**
- `ctx` — the task's pool.

**Returns** — the current `used` value (an opaque mark).

**Errors** — none.

**Example**
```zig
const mark = std_async.contextMark(ctx);
const child = std_async.contextAlloc(ctx, 32) catch @panic("child");
std_async.contextRelease(ctx, mark);
```

**Gotchas** — a mark is only meaningful for its own pool, and only until the
matching `contextRelease`. Marks are LIFO.

#### `contextRelease`

**Purpose** — rewinds the bump cursor to a previously taken `contextMark`,
reclaiming every child frame allocated since.

**When to use** — when a child frame returns, bracketed by its `contextMark`.

**Signature** — `pub fn contextRelease(ctx: *Context, mark: usize) void`

**Parameters**
- `ctx` — the task's pool.
- `mark` — a value returned by `contextMark` for this pool.

**Returns** — nothing.

**Errors** — none exposed; under `-fsafe`, `mark > used` traps (the subtraction
overflow check). In both modes `used` ends at `mark`.

**Example**
```zig
const mark = std_async.contextMark(ctx);
std_async.contextRelease(ctx, mark);
```

**Gotchas** — releasing a mark that is not currently on the stack corrupts the
pool; only release marks you took, in LIFO order.

#### `Task`

**Purpose** — one cooperative task: its root frame, child-frame pool, state,
cancellation flag, result slot, argument, and optional dependency.

**When to use** — as the unit registered with a `Scheduler`; populate it from
`@asyncInit`'s return plus the caller's result/arg pointers.

**Signature** — `pub const Task = struct { frame: *void, ctx: *Context, state: TaskState, cancel_requested: bool, result: *void, arg: *void, waiting_on: *Task, has_waiting_on: bool };`

**Parameters** (fields)
- `frame` — the root frame in caller `buf` (from `@asyncInit`).
- `ctx` — the task's child-frame pool.
- `state` — lifecycle state; start `ready`.
- `cancel_requested` — set by `cancel`/`cancelAll`, observed at a tick boundary.
- `result` — caller's result slot (L3); the scheduler never writes it.
- `arg` — the argument pointer passed to `@asyncInit`; `tick` passes it to
  `@asyncResume`.
- `waiting_on` — the dependency task when `has_waiting_on`.
- `has_waiting_on` — true while `tick` must skip the task until `waiting_on`
  settles.

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var task: std_async.Task = undefined;
task.frame = @asyncInit(@ptrCast(*void, ctx), frame_store, worker, @ptrCast(*const void, &args));
task.ctx = ctx;
task.arg = @ptrCast(*void, &args);
task.result = @ptrCast(*void, &args);
task.cancel_requested = false;
task.waiting_on = &task;
task.has_waiting_on = false;
```

**Gotchas** — `result`/`arg` are opaque to the scheduler; wire them to real
storage. `state` is set by `addTask` and `tick`. A task is not refcounted — the
caller owns the storage.

#### `Scheduler`

**Purpose** — a fixed-capacity list of `*Task` plus the current index and an
in-task flag.

**When to use** — as the value returned by `schedulerInit` and passed to every
scheduler function.

**Signature** — `pub const Scheduler = struct { tasks: [*]*Task, capacity: usize, count: usize, current: usize, in_task: bool };`

**Parameters** (fields)
- `tasks` — caller-owned array of task pointers.
- `capacity` — `tasks.len`.
- `count` — registered tasks.
- `current` — index of the task being resumed (`awaitTask` uses it).
- `in_task` — true while inside a resume (`awaitTask` guards on it).

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var pt: [2]*std_async.Task = undefined;
var s = std_async.schedulerInit(pt[0..]);
```

**Gotchas** — the scheduler does not own the `tasks` array or the tasks; keep
both alive. It never allocates.

#### `schedulerInit`

**Purpose** — wraps a caller-owned `[]*Task` as a `Scheduler` with `count == 0`.

**When to use** — once, before `addTask`.

**Signature** — `pub fn schedulerInit(tasks: []*Task) Scheduler`

**Parameters**
- `tasks` — the caller-owned backing array; its pointer and length are stored.

**Returns** — a `Scheduler` with `capacity == tasks.len` and `count == 0`.

**Errors** — none.

**Example**
```zig
var pt: [4]*std_async.Task = undefined;
var s = std_async.schedulerInit(pt[0..]);
```

**Gotchas** — the array must outlive the scheduler and must not be resized.

#### `addTask`

**Purpose** — registers `t` with `s`; idempotent, so re-adding a `*Task` never
duplicates an entry.

**When to use** — to put a task under scheduler control, and to restart a
settled task in place.

**Signature** — `pub fn addTask(s: *Scheduler, t: *Task) bool`

**Parameters**
- `s` — the scheduler.
- `t` — the task to register.

**Returns** — `true` when `t` was appended, or was already registered and
settled (`done`/`cancelled`) and has been reset in place to `ready` (clearing
`cancel_requested` and `has_waiting_on`). `false` when `t` is already registered
and still active (ready/running/suspended), or when the scheduler is at capacity.

**Errors** — none; `false` is the failure signal.

**Example**
```zig
if (!std_async.addTask(&s, &task)) {
    std.io.write("scheduler full or task active\n");
}
```

**Gotchas** — the restart path resets `cancel_requested` and `has_waiting_on` but
does **not** reset the root frame; re-`@asyncInit` it if the task should run from
the top.

#### `removeTask`

**Purpose** — retires `t` from `s`, compacting the tail so `count` drops by one.

**When to use** — to unregister a task that will not run again. No-op when `t`
is not registered.

**Signature** — `pub fn removeTask(s: *Scheduler, t: *Task) void`

**Parameters**
- `s` — the scheduler.
- `t` — the task to remove.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std_async.removeTask(&s, &task);
```

**Gotchas** — `current` is adjusted to stay in range. `t`'s own state is not
changed. Valid from any non-suspending context (main/`export fn`/helper); do not
remove a task another coroutine is currently awaiting.

#### `tick`

**Purpose** — resumes every ready/suspended task once, in registration order.

**When to use** — the driver's per-iteration call; `waitAll`/`waitFor` loop it
for you.

**Signature** — `pub fn tick(s: *Scheduler) FrameError!void`

**Parameters**
- `s` — the scheduler.

**Returns** — nothing.

**Errors** — `error.OutOfFrame` when a resumed task's pool overflowed; the tick
stops without resuming further tasks.

**Example**
```zig
while (task.state != std_async.TaskState.done and task.state != std_async.TaskState.cancelled) {
    std_async.tick(&s) catch @panic("tick");
}
```

**Gotchas** — a task with `cancel_requested` becomes `cancelled` and is skipped;
a task whose `waiting_on` dependency has not settled is skipped; a task whose step
returns `null` becomes `done`, otherwise `suspended`. `tick` sets
`state = running` and `in_task = true` around the resume.

#### `suspend`

**Purpose** — marks `t` suspended (cooperative-yield bookkeeping).

**When to use** — rarely; `awaitTask` and `@asyncSuspend` are the normal yield
paths. This sets the state without installing a dependency.

**Signature** — `pub fn suspend(s: *Scheduler, t: *Task) void`

**Parameters**
- `s` — ignored (accepted for symmetry).
- `t` — the task to mark.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std_async.suspend(&s, &task);
```

**Gotchas** — a suspended task is still resumed by the next `tick` unless it has
a pending dependency (`has_waiting_on`); this call alone does not defer a task.

#### `suspendUntil`

**Purpose** — the Model C suspending primitive: yields via `@asyncSuspend(null)`
once per tick until `pred()` is true.

**When to use** — to wait on a caller-defined condition inside a coroutine
without a dependency task (e.g. "until this flag flips").

**Signature** — `pub fn suspendUntil(pred: fn() bool) void`

**Parameters**
- `pred` — a **non-suspending** function pointer invoked indirectly once per
  resume. It must be a named function (Z98 has no anonymous function literals).

**Returns** — nothing; returns once `pred()` is true.

**Errors** — none.

**Example**
```zig
var g_flag: bool = false;

fn isReady() bool {
    return g_flag;
}

fn worker(c: *u32) void {
    _ = c;
    std.async.suspendUntil(isReady);
}
```

**Gotchas** — the caller must be a suspending function (the body of
`suspendUntil` contains `@asyncSuspend`, so it self-seeds as suspending). `pred`
must not suspend. Each tick calls `pred` exactly once.

#### `waitAll`

**Purpose** — ticks until every registered task is `done` or `cancelled`.

**When to use** — to drive a whole task set to completion from a non-suspending
context.

**Signature** — `pub fn waitAll(s: *Scheduler) FrameError!void`

**Parameters**
- `s` — the scheduler.

**Returns** — nothing once all tasks settle.

**Errors** — `error.OutOfFrame` when a resumed task's pool overflows.

**Example**
```zig
std_async.waitAll(&s) catch @panic("waitAll");
```

**Gotchas** — loops forever if a task can never settle; pair with `cancel`/
`cancelAll` for tasks that may not finish. Valid from any non-suspending context.

#### `waitFor`

**Purpose** — ticks until a single task `t` is `done` or `cancelled`.

**When to use** — to drive one task to completion while letting others tick too.

**Signature** — `pub fn waitFor(s: *Scheduler, t: *Task) FrameError!void`

**Parameters**
- `s` — the scheduler.
- `t` — the task to wait for.

**Returns** — nothing once `t` settles.

**Errors** — `error.OutOfFrame` when a resumed task's pool overflows. Panics if
`t` is neither registered nor already settled (hang guard).

**Example**
```zig
std_async.waitFor(&s, &task) catch @panic("waitFor");
```

**Gotchas** — does not suspend and needs no caller frame, so it is valid from
`main`, an `export fn`, or a plain helper. Unlike `awaitTask`, it drives other
tasks as a side effect.

#### `awaitTask`

**Purpose** — suspends the currently-running task until `t` is done or
cancelled.

**When to use** — inside a coroutine that must wait on another task (a
dependency), rather than blocking the driver.

**Signature** — `pub fn awaitTask(s: *Scheduler, t: *Task) void`

**Parameters**
- `s` — the scheduler; its `current`/`in_task` identify the caller.
- `t` — the dependency task.

**Returns** — nothing; the current task is marked suspended with
`waiting_on = t` and is skipped by `tick` until `t` settles.

**Errors** — none; panics if called from a non-suspending context or with no
registered task.

**Example**
```zig
fn step(f: *void, arg: ?*void) ?*void {
    _ = arg;
    var fr = @ptrCast(*Frame, f);
    if (fr.first) {
        fr.first = false;
        std.async.awaitTask(fr.sched, fr.sched.tasks[0]);
    }
    return null;
}
```

**Gotchas** — must be called from within a coroutine resume (`in_task`); it sets
the dependency but does not itself call `@asyncSuspend`, so the coroutine must
then reach a suspension point (returning non-null from its step does this).

#### `cancel`

**Purpose** — requests cooperative cancellation of `t`, observed at the next
tick boundary.

**When to use** — to ask a task to stop without running its completion path.

**Signature** — `pub fn cancel(s: *Scheduler, t: *Task) void`

**Parameters**
- `s` — ignored (accepted for symmetry).
- `t` — the task to cancel.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std_async.cancel(&s, &task);
```

**Gotchas** — sets `cancel_requested`; the task is not interrupted mid-resume.
`tick` flips it to `cancelled` and skips it. A `done` task is unaffected.

#### `cancelAll`

**Purpose** — requests cancellation of every registered task that is not already
`done`.

**When to use** — teardown, or to bound `waitAll` when tasks may not finish.

**Signature** — `pub fn cancelAll(s: *Scheduler) void`

**Parameters**
- `s` — the scheduler.

**Returns** — nothing.

**Errors** — none.

**Example**
```zig
std_async.cancelAll(&s);
std_async.waitAll(&s) catch @panic("drain");
```

**Gotchas** — sets `cancel_requested` on each non-`done` task (including
`cancelled` ones); each is observed at the next tick boundary.

### `std_stream`

#### `StreamError`

**Purpose** — the module's named error set; an alias of the file reader's source
set `std_file.FileError`.

**When to use** — when naming or matching a file-reader failure. The socket and
frame readers use their own inferred sets (see below).

**Signature** — `pub const StreamError = file_mod.FileError;`

**Parameters** — none.

**Returns** — an error set, not a value.

**Errors** — the members of `std_file.FileError` (`OpenFailed`, `ReadFailed`,
`WriteFailed`, `SeekFailed`, `SizeFailed`, `FlushFailed`, `RemoveFailed`,
`RenameFailed`, `OutOfMemory`); the readers produce `error.ReadFailed`.

**Example**
```zig
const m = std_stream.readFileLineSync(&lr) catch |e| {
    if (e == error.ReadFailed) return;
    return null;
};
_ = m;
```

**Gotchas** — only the file reader uses this alias. `readSocketLineSync`/
`readSocketLineAsync` infer `std_net.NetError`; `readMsgSync`/`readMsgAsync`
infer `std_net.NetError` **plus** `error.FrameTooLarge`. `FrameTooLarge` is not a
member of `NetError`; it is the one operator-authorized `std_stream` framing
error.

#### `FileLineReader`

**Purpose** — the line reader state over a caller-owned `*std_file.File`: the
source, the accumulation buffer, the unconsumed slice, and the two boundary
carries.

**When to use** — as the value returned by `initFileLineReader` and passed to
`readFileLineSync`/`readFileLineAsync`.

**Signature** — `pub const FileLineReader = struct { src: *file_mod.File, buf: []u8, pending: []u8, pending_cr: bool, overflow_cont: bool };`

**Parameters** (fields)
- `src` — the open file (caller-owned).
- `buf` — the caller-owned accumulation buffer.
- `pending` — the unconsumed slice into `buf`.
- `pending_cr` — a boundary `\r` carried from an overflow.
- `overflow_cont` — an exact-multiple line's terminator is still unread.

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var rbuf: [256]u8 = undefined;
var lr = std_stream.initFileLineReader(&file, rbuf[0..]);
```

**Gotchas** — the reader never allocates and never owns `buf`/`src`. A returned
line aliases `buf` and is invalidated by the next call.

#### `initFileLineReader`

**Purpose** — creates a `FileLineReader` over an open file and a caller buffer.

**When to use** — once per file, before the first read.

**Signature** — `pub fn initFileLineReader(src: *file_mod.File, buf: []u8) FileLineReader`

**Parameters**
- `src` — an open `*std_file.File`.
- `buf` — the accumulation buffer; must be non-empty for reads to return data.

**Returns** — a `FileLineReader` with empty `pending` and both carries false.

**Errors** — none.

**Example**
```zig
var file = try std_file.open(&arena, "in.txt", std_file.Mode.Read);
var rbuf: [256]u8 = undefined;
var lr = std_stream.initFileLineReader(&file, rbuf[0..]);
```

**Gotchas** — `buf.len == 0` makes both read functions return `null` immediately.
Keep `file` open until the reader is done.

#### `readFileLineSync`

**Purpose** — blocking line read: reads until a line is buffered or EOF, with no
suspension.

**When to use** — for file input outside a coroutine, or where blocking is
acceptable.

**Signature** — `pub fn readFileLineSync(lr: *FileLineReader) StreamError!?[]u8`

**Parameters**
- `lr` — an initialized reader.

**Returns** — `?[]u8`: the next line (terminator stripped, final unterminated
line at EOF included), or `null` at EOF with nothing buffered. An overlong line
returns a full-buffer prefix. The slice aliases `lr.buf`.

**Errors** — `error.ReadFailed` when the underlying file read fails.

**Example**
```zig
while (true) {
    const m = std_stream.readFileLineSync(&lr) catch @panic("read");
    if (m) |line| {
        std.io.write(line);
        std.io.writeByte('\n');
    } else break;
}
```

**Gotchas** — strips `\n` and the `\r` of `\r\n`; a lone `\r` at EOF is exposed
as its own line. The returned slice is valid only until the next call. The
exact-multiple overflow contract is carried across calls.

#### `readFileLineAsync`

**Purpose** — cooperative-yield line read: reads a bounded chunk and suspends via
`@asyncSuspend` once per incomplete read.

**When to use** — inside a coroutine, so other tasks run while the file is read.

**Signature** — `pub fn readFileLineAsync(lr: *FileLineReader) StreamError!?[]u8`

**Parameters**
- `lr` — an initialized reader.

**Returns** — same `?[]u8` contract as `readFileLineSync`. Each incomplete read
yields; the caller's tick counter advances once per suspension.

**Errors** — `error.ReadFailed` when the underlying file read fails.

**Example**
```zig
fn co(c: *CoCtx) void {
    while (true) {
        const m = std_stream.readFileLineAsync(c.lr) catch return;
        if (m) |line| {
            std.io.write(line);
            std.io.writeByte('\n');
        } else return;
    }
}
```

**Gotchas** — must be called from a suspending function. A **separate**
implementation from the sync path (it never calls it). Reads at most a quarter of
`buf.len` per chunk, so a line can suspend several times.

#### `SocketLineReader`

**Purpose** — the line reader state over a caller-owned `*std_net.Socket`; the
same fields as `FileLineReader` with a socket source.

**When to use** — as the value returned by `initSocketLineReader` and passed to
`readSocketLineSync`/`readSocketLineAsync`.

**Signature** — `pub const SocketLineReader = struct { src: *net_mod.Socket, buf: []u8, pending: []u8, pending_cr: bool, overflow_cont: bool };`

**Parameters** (fields)
- `src` — the socket (caller-owned; non-blocking for the async path).
- `buf` — the caller-owned accumulation buffer.
- `pending` — the unconsumed slice into `buf`.
- `pending_cr` — a boundary `\r` carried from an overflow.
- `overflow_cont` — an exact-multiple line's terminator is still unread.

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var rbuf: [256]u8 = undefined;
var lr = std_stream.initSocketLineReader(&sock, rbuf[0..]);
```

**Gotchas** — for the async path the socket must first be set non-blocking
(`std_net.setNonBlocking`); the sync path requires blocking mode.

#### `initSocketLineReader`

**Purpose** — creates a `SocketLineReader` over a socket and a caller buffer.

**When to use** — once per socket, before the first read.

**Signature** — `pub fn initSocketLineReader(src: *net_mod.Socket, buf: []u8) SocketLineReader`

**Parameters**
- `src` — the socket; set it non-blocking for the async path.
- `buf` — the accumulation buffer.

**Returns** — a `SocketLineReader` with empty `pending` and both carries false.

**Errors** — none.

**Example**
```zig
std.net.setNonBlocking(&sock) catch @panic("nonblocking");
var rbuf: [256]u8 = undefined;
var lr = std_stream.initSocketLineReader(&sock, rbuf[0..]);
```

**Gotchas** — `buf.len == 0` makes both read functions return `null`
immediately. The same line contract as `FileLineReader` applies.

#### `readSocketLineSync`

**Purpose** — blocking socket line read: reads until a line is buffered or the
peer closes.

**When to use** — for socket input outside a coroutine, on a blocking socket.

**Signature** — `pub fn readSocketLineSync(lr: *SocketLineReader) !?[]u8`

**Parameters**
- `lr` — an initialized reader.

**Returns** — `?[]u8`: the next line, or `null` at peer close with nothing
buffered. The slice aliases `lr.buf`.

**Errors** — the inferred `std_net.NetError`; `error.WouldBlock` if the socket is
non-blocking and no data is ready, plus `Io`/`ConnReset`/etc. on a real socket
error.

**Example**
```zig
const m = std_stream.readSocketLineSync(&lr) catch |e| {
    if (e == error.WouldBlock) return;
    return null;
};
_ = m;
```

**Gotchas** — requires a blocking socket for the normal path; on a non-blocking
socket it surfaces `error.WouldBlock` rather than retrying. Same line contract as
`readFileLineSync`.

#### `readSocketLineAsync`

**Purpose** — cooperative-yield socket line read: suspends on `error.WouldBlock`
and is re-driven on the next tick.

**When to use** — inside a coroutine over a non-blocking socket.

**Signature** — `pub fn readSocketLineAsync(lr: *SocketLineReader) !?[]u8`

**Parameters**
- `lr` — an initialized reader over a socket set non-blocking.

**Returns** — same `?[]u8` contract as `readSocketLineSync`.

**Errors** — the inferred `std_net.NetError`; `error.WouldBlock` is consumed
internally (it yields and retries), so it is not surfaced to the caller.

**Example**
```zig
fn co(c: *CoCtx) void {
    while (true) {
        const m = std_stream.readSocketLineAsync(c.lr) catch return;
        if (m) |line| {
            std.io.write(line);
        } else return;
    }
}
```

**Gotchas** — the socket must be non-blocking (`std.net.setNonBlocking`). A
**separate** implementation from the sync path. Suspends once per would-block, so
the caller's tick counter measures the wait.

#### `MsgReader`

**Purpose** — the length-prefix frame reader state over a caller-owned
`*std_net.Socket`: the source, the buffer, and the pending body slice.

**When to use** — as the value returned by `initMsgReader` and passed to
`readMsgSync`/`readMsgAsync`.

**Signature** — `pub const MsgReader = struct { src: *net_mod.Socket, buf: []u8, pending: []u8 };`

**Parameters** (fields)
- `src` — the socket (caller-owned; non-blocking for the async path).
- `buf` — the caller-owned frame buffer; its length caps a frame.
- `pending` — the body bytes read so far.

**Returns** — a plain value type.

**Errors** — none.

**Example**
```zig
var fbuf: [16]u8 = undefined;
var mr = std_stream.initMsgReader(&sock, fbuf[0..]);
```

**Gotchas** — a declared frame larger than `buf.len` is `error.FrameTooLarge`;
size `buf` to the largest expected frame. `buf.len == 0` makes both read
functions return `null` immediately.

#### `initMsgReader`

**Purpose** — creates a `MsgReader` over a socket and a caller buffer.

**When to use** — once per socket, before the first frame read.

**Signature** — `pub fn initMsgReader(src: *net_mod.Socket, buf: []u8) MsgReader`

**Parameters**
- `src` — the socket; set it non-blocking for the async path.
- `buf` — the frame buffer; the maximum body length.

**Returns** — a `MsgReader` with empty `pending`.

**Errors** — none.

**Example**
```zig
std.net.setNonBlocking(&sock) catch @panic("nonblocking");
var fbuf: [16]u8 = undefined;
var mr = std_stream.initMsgReader(&sock, fbuf[0..]);
```

**Gotchas** — the whole frame (prefix plus body) lives in `buf`; the prefix is
not part of the returned slice.

#### `readMsgSync`

**Purpose** — blocking frame read: reads a 4-byte big-endian length prefix, then
the body.

**When to use** — for framed socket input outside a coroutine, on a blocking
socket.

**Signature** — `pub fn readMsgSync(mr: *MsgReader) !?[]u8`

**Parameters**
- `mr` — an initialized reader.

**Returns** — `?[]u8`: the frame body (a length-0 slice for a zero-length frame),
or `null` at EOF mid-prefix or mid-body. The slice aliases `mr.buf`.

**Errors** — the inferred `std_net.NetError` (including `error.WouldBlock` on a
non-blocking socket) and `error.FrameTooLarge` when the declared length exceeds
`mr.buf.len`.

**Example**
```zig
const got = std_stream.readMsgSync(&mr) catch |e| {
    if (e == error.FrameTooLarge) return;
    return;
};
_ = got;
```

**Gotchas** — requires a blocking socket for the normal path. A zero-length
prefix is a valid empty frame, never `null`. A 1-byte frame proves the prefix is
decoded big-endian.

#### `readMsgAsync`

**Purpose** — cooperative-yield frame read: suspends on `error.WouldBlock` and is
re-driven on the next tick.

**When to use** — inside a coroutine over a non-blocking socket.

**Signature** — `pub fn readMsgAsync(mr: *MsgReader) !?[]u8`

**Parameters**
- `mr` — an initialized reader over a socket set non-blocking.

**Returns** — same `?[]u8` contract as `readMsgSync`.

**Errors** — the inferred `std_net.NetError` and `error.FrameTooLarge` when the
declared length exceeds `mr.buf.len`; `error.WouldBlock` is consumed internally.

**Example**
```zig
fn co(c: *CoCtx) void {
    while (true) {
        const m = std_stream.readMsgAsync(c.mr) catch return;
        if (m) |frame| {
            std.io.write(frame);
        } else return;
    }
}
```

**Gotchas** — the socket must be non-blocking. A **separate** implementation from
the sync path. The prefix is accumulated one wire byte at a time so no array local
is live across a suspension.

## See also

- `std.async`, `std_stream` — the modules in this doc.
- [`net.md`](net.md) — `std.net`'s `setNonBlocking` / `recvNonBlocking` and the
  `error.WouldBlock` contract the socket readers build on.
- [`io.md`](io.md) — `std_file` and `std_stdin`, the L3 resources `std_stream`
  reads from.
- [`memory.md`](memory.md) — the `std.arena` model; the frame pool and the
  stream readers take caller-owned storage and never allocate.
- [`STD_README.MD`](../../../STD_README.MD) — the curated std-lib index.
