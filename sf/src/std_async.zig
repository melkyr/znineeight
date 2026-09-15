// std_async.zig — concrete cooperative task scheduler + per-task child-frame
// pool for Z98 coroutines (Track 3, std.async). No generics, no module-scope
// mutable globals: the caller supplies all storage.
//
// Frame model (umbrella m1166/m1172):
//   - The root frame lives in the caller-owned `buf` passed to @asyncInit and
//     is OUTSIDE the pool.
//   - `Context` owns the caller-sized pool for CHILD frames only; it is a
//     per-task LIFO frame stack (bump pointer + mark), not a shared allocator.
//   - `contextAlloc` advances the bump; `contextMark`/`contextRelease` bracket a
//     child so it is reclaimed exactly when it returns. Exhaustion returns
//     `error.OutOfFrame` and sets the sticky `oom` flag; it is never a crash.
//
// Scheduler dispatch (Amendment 7): `Task` stores NO step pointer. `tick`/
// `waitAll` self-dispatch with `@asyncResume(t.frame, t.arg)`, which loads the
// hidden pointer-sized step word the compiler writes at frame offset 0. Track 3
// therefore DEPENDS on the landed Track 2 compiler core for `@asyncResume` and
// the frame/`ctx` layout. (The historical `fn_ptr_struct_field` gap is CLOSED;
// `StepFn` remains the documented `__async_step_<f>` ABI alias only.)

/// Cooperative task lifecycle.
pub const TaskState = enum(u8) {
    ready = 0,
    running = 1,
    suspended = 2,
    done = 3,
    cancelled = 4,
};

/// Pool exhaustion, surfaced by the scheduler free functions.
pub const FrameError = error{OutOfFrame};

/// The documented `__async_step_<f>` ABI alias: `fn(frame, arg) ?*void`; null =
/// terminal (done), non-null = still yielded. Documentation only — the scheduler
/// never stores or passes a `StepFn` (Amendment 7 self-dispatch via
/// `@asyncResume(t.frame, t.arg)`); Track 3 fixtures set it as the first `Frame`
/// field so it lands at frame offset 0.
pub const StepFn = fn(frame: *void, arg: ?*void) ?*void;

// Branch (a) — DECIDED (operator ruling m1662). Context occupies the first 16
// bytes of the caller's pool buffer; the pool bytes follow: `pool_base =
// ctx + 16` (DERIVED — never stored). The by-value Context + separate
// `pool_base` alternative is REJECTED (redoes landed Track 2 work). The header
// is 16 bytes (not 12) so that `ctx + 16` stays 8-aligned whenever `buf` is
// 8-aligned; `buf` MUST be 8-aligned (documented precondition), which keeps
// child frames holding 8-byte-aligned members (e.g. `f64`) correctly aligned.
/// Per-task child-frame pool. The caller declares `var buf: [N]u8 = undefined;`
/// (8-aligned) and the Context sits at the HEAD of that buffer; `capacity` is
/// the usable bytes AFTER the 16-byte header; `oom` is sticky for the pool's
/// lifetime.
pub const Context = struct {
    used: usize,       // @ ctx+0
    capacity: usize,   // @ ctx+4 — usable bytes AFTER the 16-byte header
    oom: bool,         // @ ctx+8 — sticky
    // bytes 9..15 are reserved padding; `pool_base = ctx + 16` (DERIVED).
};

/// Places the Context at the head of `buf` and returns a pointer into `buf`.
/// PRECONDITION: `buf.ptr` MUST be 8-aligned (checked below; traps in both
/// modes) and `buf.len` MUST be >= 16.
pub fn contextInit(buf: []u8) *Context {
    if ((@ptrToInt(buf.ptr) & 7) != 0) {
        @panic("std.async: contextInit buffer must be 8-aligned");
    }
    var c: *Context = @ptrCast(*Context, buf.ptr);
    // -fsafe: `buf.len - 16` lowers to sub_with_overflow + an integer-overflow
    // check (kind 6), so it TRAPS on `buf.len < 16`; -ffast omits the check and
    // the subtraction wraps. Callers must pass `buf.len >= 16`.
    c.capacity = buf.len - 16;
    c.used = 0;
    c.oom = false;
    return c;
}

pub fn contextAlloc(ctx: *Context, size: usize) FrameError![*]u8 {
    if (ctx.used + size > ctx.capacity) {
        ctx.oom = true;
        return error.OutOfFrame;
    }
    var base: [*]u8 = @ptrCast([*]u8, ctx) + 16;
    var p: [*]u8 = base + ctx.used;
    ctx.used += size;
    return p;
}

pub fn contextMark(ctx: *Context) usize {
    return ctx.used;
}

pub fn contextRelease(ctx: *Context, mark: usize) void {
    // -fsafe: the subtraction traps (integer-overflow check) when mark > used;
    // -ffast: it wraps (check omitted). `used - (used - mark) == mark` in both modes.
    var delta: usize = ctx.used - mark;
    ctx.used = ctx.used - delta;
}

/// One cooperative task. `frame` is the root frame in caller `buf`; `ctx` is the
/// task's child-frame pool; `result` points at the caller's result slot (L3).
pub const Task = struct {
    frame: *void,
    ctx: *Context,
    state: TaskState,
    cancel_requested: bool,
    result: *void,
    arg: *void,
    waiting_on: *Task,
    has_waiting_on: bool,
};

pub const Scheduler = struct {
    tasks: [*]Task,
    capacity: usize,
    count: usize,
    current: usize,
};

pub fn schedulerInit(tasks: []Task) Scheduler {
    var s = Scheduler{ .tasks = tasks.ptr, .capacity = tasks.len, .count = 0, .current = 0 };
    return s;
}

pub fn addTask(s: *Scheduler, t: *Task) bool {
    if (s.count >= s.capacity) return false;
    s.tasks[s.count] = t.*;
    s.tasks[s.count].state = TaskState.ready;
    s.tasks[s.count].has_waiting_on = false;
    s.count += 1;
    return true;
}

fn allSettled(s: *Scheduler) bool {
    var i: usize = 0;
    while (i < s.count) : (i += 1) {
        if (s.tasks[i].state != TaskState.done and s.tasks[i].state != TaskState.cancelled) {
            return false;
        }
    }
    return true;
}

/// Resume every ready/suspended task once. Returns `error.OutOfFrame` when a
/// resumed task's context pool overflowed, without resuming further tasks.
pub fn tick(s: *Scheduler) FrameError!void {
    var i: usize = 0;
    while (i < s.count) : (i += 1) {
        var t: *Task = &s.tasks[i];
        var active: bool = true;
        if (t.state == TaskState.done) active = false;
        if (t.state == TaskState.cancelled) active = false;
        if (active and t.cancel_requested) {
            t.state = TaskState.cancelled;
            active = false;
        }
        if (active and t.has_waiting_on) {
            var dep: *Task = t.waiting_on;
            if (dep.state != TaskState.done and dep.state != TaskState.cancelled) {
                active = false;
            } else {
                t.has_waiting_on = false;
            }
        }
        if (active) {
            s.current = i;
            t.state = TaskState.running;
            var r: ?*void = @asyncResume(t.frame, t.arg);
            if (t.ctx.oom) return error.OutOfFrame;
            if (r == null) {
                t.state = TaskState.done;
            } else {
                t.state = TaskState.suspended;
            }
        }
    }
}

/// Mark `t` suspended (cooperative yield bookkeeping).
pub fn suspend(s: *Scheduler, t: *Task) void {
    _ = s;
    t.state = TaskState.suspended;
}

/// Tick until every task is done or cancelled.
pub fn waitAll(s: *Scheduler) FrameError!void {
    while (!allSettled(s)) {
        try tick(s);
    }
}

/// Suspend the currently-running task until `t` is done or cancelled.
pub fn awaitTask(s: *Scheduler, t: *Task) void {
    var cur: *Task = &s.tasks[s.current];
    cur.state = TaskState.suspended;
    cur.waiting_on = t;
    cur.has_waiting_on = true;
}

/// Request cooperative cancellation of `t`; observed at the next tick boundary.
pub fn cancel(s: *Scheduler, t: *Task) void {
    _ = s;
    t.cancel_requested = true;
}

pub fn cancelAll(s: *Scheduler) void {
    var i: usize = 0;
    while (i < s.count) : (i += 1) {
        if (s.tasks[i].state != TaskState.done) {
            s.tasks[i].cancel_requested = true;
        }
    }
}
